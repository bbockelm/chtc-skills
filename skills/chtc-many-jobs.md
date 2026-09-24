---
name: chtc-many-jobs
description: Submitting many CHTC jobs from one submit description — queue N, queue from a list, initialdir, per-job inputs and outputs, and the scale limits that need staff involvement.
sources:
  - chtc-website-source:_uw-research-computing/multiple-jobs.md
  - chtc-website-source:_uw-research-computing/multiple-job-dirs.md
  - chtc-website-source:_uw-research-computing/htc-passing-arguments.md
  - chtc-website-source:_uw-research-computing/htc/dagman-workflows.md
upstream_reviewed: 2026-09-22
---

# Many jobs from one submit description

This is what CHTC is for. HTCondor is built to take thousands of jobs from a
single submission, and doing it any other way — a loop that calls `submit_job`
once per task — hammers the access point and is the behaviour CHTC's policies
are written against.

**One `submit_job` call, one `queue` statement, N jobs.**

## `queue N`

For replicates, or when `$(Process)` alone selects the work:

```
executable = analyze.sh
arguments  = $(Process)

log    = run_$(Cluster).log
output = run_$(Cluster)_$(Process).out
error  = run_$(Cluster)_$(Process).err

request_cpus   = 1
request_memory = 2GB
request_disk   = 4GB

queue 500
```

`$(Process)` runs 0…N−1 and `$(Cluster)` is the submission id. Give every job
distinct `output`/`error` names or they collide. To start at 1:

```
plusone    = $(Process) + 1
NewProcess = $INT(plusone,%d)
```

## `queue <vars> from <list>` — the flexible form

The most useful pattern, and the one to reach for by default:

```
executable = analyze.sh
arguments  = $(sample) $(year)

transfer_input_files = osdf:///chtc/staging/a/alice/$(sample).bam

output = $(sample)_$(year).out
error  = $(sample)_$(year).err
log    = batch_$(Cluster).log

queue sample, year from samples.txt
```

with `samples.txt`:

```
SRR001, 2019
SRR002, 2019
SRR003, 2021
```

One job per line; the variables are usable anywhere in the submit file.

**Getting the list file to the job.** `samples.txt` is read by the submit
*parser* on the access point, not by the job, so it must exist there before
`submit_job` runs. That is awkward when you have no shell. Two clean ways out:

1. **Inline the list with `queue … from` and a here-list.** HTCondor accepts an
   inline item list:

   ```
   queue sample, year from (
     SRR001, 2019
     SRR002, 2019
     SRR003, 2021
   )
   ```

   This travels with the submit text and needs no file. **Prefer this** through
   the MCP interface — it is the single most useful adaptation in this skill.

2. **`queue N` plus a manifest transferred to the job**, letting the job pick its
   own line:

   ```
   transfer_input_files = manifest.txt
   arguments            = $(Process)
   queue 500
   ```

   with `sample=$(sed -n "$(( $1 + 1 ))p" manifest.txt)` inside the script. Ship
   `manifest.txt` with `upload_job_input`.

### A varying number of files per job

The last named variable absorbs the rest of the line, so a trailing file list
works:

```
queue start, end, files from (
  1995, 2000, illinois.data
  1995, 2000, illinois.data, nebraska.data
  1995, 2000, illinois.data, nebraska.data, wisconsin.data
)
```

`$(files)` becomes the whole comma-separated remainder, usable directly as
`transfer_input_files = $(files)`. Only **one** variable-length list per
submission, and it must be last.

### `queue <var> matching <pattern>`

Globs paths on the access point (`queue d matching state_*`). Useful when the
user already has directories there; useless when you are building everything
fresh. The inline list is usually a better fit here.

## Per-job directories with `initialdir`

When each job should read and write in its own directory:

```
initialdir           = $(sample_dir)
executable           = analyze.sh
transfer_input_files = input.data

queue sample_dir from ( SRR001 SRR002 SRR003 )
```

`initialdir` changes where inputs, outputs, `log`, `output` and `error` resolve
— but **not** where `executable` is found, which stays relative to the submit
directory. With `shell` instead of `executable`, the script must be transferred
relative to `initialdir` (`../analyze.sh`).

Also: if the variable holds a directory it may carry a trailing `/`, so
`output = $(sample_dir).out` creates a hidden `.out` *inside* the directory.
**Use a directory variable only in `initialdir`.**

## Variable names to avoid

Do not name your own variables `Cluster`, `ClusterID`, `Process`, `ProcID`,
`batch_name`, `output`, `input`, or `arguments`. They collide with submit-file
built-ins and fail in confusing ways.

## Scale limits

| | Limit | Action |
| --- | --- | --- |
| Jobs per submission | 10,000 | Add `max_idle = 10000`; above this, email CHTC |
| Queued per user | 50,000 | Email CHTC |
| Average runtime above 1000 jobs | ≥ 5 minutes | Bundle work per job |

Short jobs are the real danger. A thousand 20-second jobs spend more of the
system's effort on scheduling and file transfer than on computing, and they
degrade the access point for everyone. If the unit of work is seconds, have each
job loop over a hundred units:

```bash
for i in $(seq $((START)) $((START+99))); do
    ./compute "$i"
done
```

```
START = $(Process)00
queue 100        # 100 jobs × 100 units = 10,000 units
```

## Uploading inputs for a multi-proc cluster

Input spools **per proc**. `upload_job_input` targets one job id, and
`create_input_upload_url` given a bare cluster id returns **one URL per proc**,
each taking its own tar. For a large batch this is a lot of round trips — so
prefer designs where per-job inputs arrive by URL:

```
transfer_input_files = osdf:///chtc/staging/a/alice/$(sample).tar.gz?pack=auto
```

and reserve `upload_job_input` for files that are identical across the batch and
small, such as the executable.

## Testing before the full batch

Non-negotiable at this scale (see `chtc-policies-and-limits` on fair share):

1. One job. Confirm the output.
2. Three to ten jobs. Confirm they do not collide — distinct filenames, no
   shared scratch assumptions, no two jobs writing the same output path.
3. Under 500: submit the rest. Over 500: an intermediate 100–1000 first.

After step 2, check the whole batch at once instead of job by job:

```
aggregate_jobs(table = "history", constraint = "ClusterId == <id>",
               group_by = ["ExitCode"])
```

Anything but a single `ExitCode == 0` group means stop and look.

## Multi-stage workflows (DAGMan)

When stage B needs stage A's output, use DAGMan. It is available here as the
**`submit_dag`** tool: the whole workflow — the DAG text plus every file it
references — goes in one call, and DAGMan then runs it unattended, with
retries and throttling.

```
submit_dag(dag = "...", files = {"check.sh": "..."}, batch_name = "my-workflow")
```

See `chtc-dag-workflows` for how to write one, what the pre-submit checker
will and will not catch, and how to watch a running workflow.

Still prefer a single `queue … from` submission when the jobs are independent
— that is one cluster instead of a graph, and everything above applies. DAGMan
earns its complexity when there are real dependencies.

## Related skills

`chtc-dag-workflows`, `chtc-submit-basics`, `chtc-data-transfer`,
`chtc-monitoring`, `chtc-resource-requests`, `chtc-policies-and-limits`
