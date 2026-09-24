---
name: chtc-dag-workflows
description: Running multi-stage CHTC workflows with DAGMan through the submit_dag tool — writing the DAG, getting every referenced file into the one spool, and watching a running workflow.
sources:
  - chtc-website-source:_uw-research-computing/htc/dagman-workflows.md
  - chtc-website-source:_uw-research-computing/htc/dagman-simple-example.md
  - chtc-website-source:_uw-research-computing/htc/tutorial-dagman-intermediate.md
  - chtc-website-source:_uw-research-computing/machine-learning-htc.md
upstream_reviewed: 2026-09-23
---

# DAGMan workflows at CHTC

When stage B needs stage A's output, the answer is DAGMan: HTCondor's built-in
workflow manager. It submits the nodes in dependency order, retries what fails,
throttles what would flood the queue, and recovers if it is interrupted — for
days, unattended, with nobody watching.

CHTC's documentation has you write a `.dag` file and run `condor_submit_dag`.
Through this server it is one tool call, **`submit_dag`**, and the whole
workflow travels in that call.

## The one rule that shapes everything

**The workflow's sandbox is spooled once, at submit time.** Every file the DAG
names — node submit files, PRE/POST scripts, small inputs — must be in the
`files` argument of the same call. There is no second chance: a name that was
not sent then can never be added afterwards.

So the shape of a `submit_dag` call is:

```
submit_dag(
  dag        = "<the whole DAG text>",
  files      = { "check.sh": "...", "extra.sub": "..." },
  batch_name = "my-workflow",
  dry_run    = false
)
```

Two consequences worth internalising before you write anything:

1. **Prefer inline `SUBMIT-DESCRIPTION` blocks** over separate `.sub` files.
   The whole workflow becomes one self-contained document with nothing else to
   stage, which removes the entire class of "I forgot to send that file".
2. **`files` names must be bare.** No directories — the spool is flat, and the
   schedd flattens it to basenames. `"scripts/setup.sh"` is refused outright
   with a message saying so.

## A worked workflow

A prepare step, a fan-out, and a gather — the shape most CHTC workflows take:

```
SUBMIT-DESCRIPTION prep {
    executable            = /bin/bash
    transfer_executable   = false
    arguments             = "-c 'seq 1 3 > params.txt'"
    transfer_output_files = params.txt
    output                = prep.out
    error                 = prep.err
    log                   = workflow.log
    request_cpus          = 1
    request_memory        = 512MB
    request_disk          = 512MB
}

SUBMIT-DESCRIPTION analyze {
    executable            = /bin/bash
    transfer_executable   = false
    arguments             = "-c 'echo result-$(sample) > result_$(sample).txt'"
    transfer_output_files = result_$(sample).txt
    output                = analyze_$(sample).out
    error                 = analyze_$(sample).err
    log                   = workflow.log
    request_cpus          = 1
    request_memory        = 512MB
    request_disk          = 512MB
}

SUBMIT-DESCRIPTION combine {
    executable            = /bin/bash
    transfer_executable   = false
    arguments             = "-c 'cat result_*.txt > combined.txt'"
    transfer_input_files  = result_1.txt, result_2.txt, result_3.txt
    transfer_output_files = combined.txt
    output                = combine.out
    error                 = combine.err
    log                   = workflow.log
    request_cpus          = 1
    request_memory        = 512MB
    request_disk          = 512MB
}

JOB PREP prep

JOB A1 analyze
VARS A1 sample="1"
JOB A2 analyze
VARS A2 sample="2"
JOB A3 analyze
VARS A3 sample="3"

JOB COMBINE combine

RETRY A2 2

PARENT PREP     CHILD A1 A2 A3
PARENT A1 A2 A3 CHILD COMBINE
```

Points that are easy to get wrong:

- **`VARS` is how one description becomes many nodes.** `$(sample)` in the
  description is filled per node. This is the DAG equivalent of
  `queue … from` (see `chtc-many-jobs`), and the same warning applies: `$(...)`
  is submit-file macro expansion, not shell substitution.
- **Node outputs land in the workflow's directory**, which is how a downstream
  node picks them up by name in `transfer_input_files`. Declare them in the
  producer's `transfer_output_files` or they are not returned at all — the
  default-transfer rule from `chtc-submit-basics` applies per node.
- **One shared `log`** across all nodes is conventional and fine.
- **`RETRY <node> <n>`** is the cheapest reliability you will ever add. Use it
  on anything that touches the network or a shared filesystem.
- Resource requests are per node, and everything in `chtc-resource-requests`
  applies to each one.

## Check it before you submit

`dry_run: true` parses the workflow, reports what would be submitted, and
submits nothing. Use it for anything non-trivial — it costs one call and
catches the structural mistakes.

What is **fatal** (the workflow is refused):

| Error | Meaning |
| --- | --- |
| `the graph has a cycle: a -> b -> c -> a` | Not a DAG. Note the node names come back lowercased. |
| `CHILD GHOST names a node that is not declared` | A `PARENT`/`CHILD` naming a node with no `JOB` line |
| `<file> is not among the supplied files (SPLICE ...)` | A `SPLICE` file must be in `files` — DAGMan inlines it at parse time |
| a name in `files` containing `/` | The spool is flat |

What comes back as a **note** (submitted anyway):

- **A `SUBDAG EXTERNAL` whose `.dag` an earlier node generates.** Expected and
  fully supported — DAGMan does not read a sub-DAG until that node is ready.
  Same for a node whose `.sub` file is generated at runtime.
- **A file a node transfers in that no node declares as output.** The checker
  cross-references `transfer_output_files` across the workflow, so this note
  means it could not prove an ancestor produces the file.

> **Expect false alarms on that last one when `VARS` are involved.** A producer
> declaring `transfer_output_files = result_$(sample).txt` does not textually
> match a consumer asking for `result_1.txt`, so the check reports the file as
> unaccounted for even though the workflow is correct. Read those notes, satisfy
> yourself that some ancestor really does produce each file, and move on.

## Getting data in and out

`dag` plus `files` is capped at **1 MiB**. That is a budget for workflow
description, not for data.

| What | How |
| --- | --- |
| The DAG, submit files, PRE/POST scripts, small configs | `files` in the `submit_dag` call |
| Reference data, datasets, container images | `transfer_input_files` on the node, as an `osdf:///` / `pelican://` / `https://` URL |
| Large results | `transfer_output_remaps` / `output_destination` on the node |

The execute machines fetch URLs directly, which is both faster and the only
thing that scales. See `chtc-data-transfer` and `chtc-staging-large-data`.

## Watching a running workflow

`submit_dag` returns the DAGMan manager job's `cluster_id`. Everything hangs
off that:

```
# The manager plus every node job it has submitted so far
query_jobs(
  constraint = "ClusterId == 11133027 || DAGManJobId == 11133027",
  projection = ["ClusterId","ProcId","JobStatus","DAGNodeName","DAGManJobId","HoldReason"]
)
```

`DAGNodeName` is the node's name from the DAG, which is what makes this
readable: you see `PREP`, `A1`, `A2` rather than bare cluster ids. The manager
itself runs in the scheduler universe on the access point and shows as
`/usr/bin/condor_dagman`.

To wait for the whole workflow, watch the manager — it leaves the queue when
the DAG is finished:

```
watch_jobs(constraint = "ClusterId == 11133027", event = "done")
check_watches(wait_seconds = 30)   # call again until it answers
```

Other useful moves:

- `tail_job_output` on a *node* job to watch it run.
- `query_job_archive` over `DAGManJobId == <cluster>` for how each node ended.
- Removing the manager job removes the workflow: the manager carries
  `OtherJobRemoveRequirements = "DAGManJobId =?= $(Cluster)"`, so
  `remove_job` on it takes the node jobs with it.

## Throttles

`max_jobs`, `max_idle`, `max_pre`, `max_post` are arguments to `submit_dag`,
not lines in the DAG. They matter at CHTC scale: a fan-out of 5000 nodes
submitted at once is exactly the burst `chtc-policies-and-limits` warns about.
Set `max_idle = 1000` or so on a large workflow and DAGMan feeds the queue
instead of flooding it.

## When a DAG is the wrong tool

- **A single fan-out with no dependencies** is a `queue … from` submission, not
  a DAG. One `submit_job` call, one cluster, far less machinery. See
  `chtc-many-jobs`.
- **Two stages, run once, while you are watching** is fine to drive by hand:
  submit A, `watch_jobs(event = "succeeded")`, submit B. You get to inspect A's
  output before committing to B.

Reach for DAGMan when the graph is real, when it must survive the end of this
conversation, or when you want retries and throttling you do not have to
implement.

## Related skills

`chtc-many-jobs`, `chtc-submit-basics`, `chtc-data-transfer`,
`chtc-monitoring`, `chtc-ml-workflows`, `chtc-resource-requests`
