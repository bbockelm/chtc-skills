---
name: chtc-overview
description: Start here — what the CHTC HTC system is, how to work on it through this MCP server instead of a shell, and which CHTC skill to read for a given task.
sources:
  - chtc-website-source:_uw-research-computing/htc-overview.md
  - chtc-website-source:_uw-research-computing/agent-recommendations.md
  - chtc-website-source:_uw-research-computing/user-expectations.md
upstream_reviewed: 2026-09-22
---

# CHTC overview: how to work here

The Center for High Throughput Computing (CHTC) at UW–Madison runs the **HTC
system**: a set of HTCondor access points (`ap2001.chtc.wisc.edu`,
`ap2002.chtc.wisc.edu`, and others) in front of tens of thousands of CPU cores
and a few hundred shared GPUs, plus opt-in access to campus pools and the
national Open Science Pool (OSPool).

You are talking to one of those access points through its MCP server. That
changes how the published CHTC documentation applies to you, and the CHTC
skills in this library are the documentation rewritten for that situation.

## The one rule that shapes everything

**Nothing computational runs on the access point.** This is CHTC's oldest and
most strictly enforced policy: the AP is a shared login and submission host, and
a process that burns CPU or memory there degrades the queue for every user on
the machine. CHTC staff will kill such processes and may disable the account.

Working through this MCP server is the *easy* way to comply, because the server
gives you no way to run a command on the AP at all. Every tool here either
manipulates the job queue or runs your command **inside a job**, on an execute
node, where the work belongs. If a task needs a shell, that shell comes from
`interactive_session_start` / `interactive_session_exec`, which is a job.

CHTC's own guidance for AI agents (`agent-recommendations`) asks that agents not
run scientific workloads on the AP, not poll `condor_q` in tight loops, not
start background services, and not install large software environments without
confirmation. Translated to this interface:

| CHTC asks agents to… | How you comply here |
| --- | --- |
| Not run the workload on the AP | Every tool runs remotely; there is no AP shell |
| Not poll `condor_q` in a loop | Use `watch_jobs` + `check_watches`, never repeated `query_jobs` |
| Not install big software on the AP | Build containers with `build_container` (runs as a job) |
| Not start background services | Stop `interactive_session_*` sessions when done |
| Not touch files outside the project | Job sandboxes are per-job and disposable |

The user remains responsible for what you do under their account. "The agent did
it" is not a defence for wasted GPU hours, a flooded queue, or deleted data.

## The working model

1. **Describe the job**, don't script it. You write an HTCondor submit
   description and hand it to `submit_job`. HTCondor does the running.
2. **Get inputs to the job by transfer, not by shared filesystem.** Small files
   go in `upload_job_input`; large ones come from `osdf:///` or `pelican://`
   URLs. See `chtc-data-transfer`.
3. **Test one job, then a handful, then the batch.** Resource requests are
   guesses until a real job reports its usage. See
   `chtc-resource-requests`.
4. **Wait by event, not by clock.** Register a watch and let it fire.
5. **Read results with the output tools**, not by listing a home directory.

## Which skill to read

| Task | Skill |
| --- | --- |
| Write and submit a first job | `chtc-submit-basics` |
| Decide `request_cpus` / `_memory` / `_disk` | `chtc-resource-requests` |
| Submit hundreds or thousands of jobs | `chtc-many-jobs` |
| Get input in / output out | `chtc-data-transfer` |
| Data bigger than ~1 GB per file | `chtc-staging-large-data` |
| Data already on ResearchDrive | `chtc-researchdrive-uwdf` |
| Build or choose a software environment | `chtc-containers` |
| Find a starting definition for Python/R/Conda/… | `chtc-software-recipes` |
| Request a GPU | `chtc-gpu-jobs` |
| Train or run inference on models | `chtc-ml-workflows` |
| Jobs longer than the runtime limit | `chtc-checkpointing` |
| Get more capacity than CHTC alone | `chtc-scaling-beyond-chtc` |
| Watch jobs, read output as they run | `chtc-monitoring` |
| A job is idle, held, or failing | `chtc-troubleshooting` |
| Need a shell on an execute node | `chtc-interactive-sessions` |
| Runtime caps, quotas, what needs staff approval | `chtc-policies-and-limits` |

## What this system is good at

CHTC is a **high-throughput** system, not a supercomputer. It shines when work
decomposes into many independent tasks that each fit on one machine — parameter
sweeps, per-sample bioinformatics, Monte Carlo replicates, per-image inference,
hyperparameter search. One 1000-hour job is a poor fit; a thousand 1-hour jobs
is an excellent one.

That decomposition advice is unchanged by the MCP interface, and it is the
single highest-leverage thing to get right. Before optimising a submit file, ask
whether the work can be split. Ideal per-job runtime is **20 minutes to a few
hours**: long enough that scheduling overhead is negligible (CHTC asks for a
5-minute average minimum above 1000 jobs), short enough to survive eviction and
to fit the 10–12 hour window that makes a job eligible for campus pools and the
OSPool.

## Things this interface cannot do

Be honest with the user when one of these comes up rather than inventing a tool:

- **No `condor_status`.** You cannot enumerate the pool's machines.
  `analyze_job_match` explains why a *specific job* is or is not matching, which
  covers most of what people actually wanted `condor_status` for.
- **No quota inspection.** `quota -vs`, `get_quotas` and `ncdu` are AP shell
  commands. Ask the user to run them, or to email chtc@cs.wisc.edu.
- **No DAGMan submission.** `condor_submit_dag` is not exposed. Chain stages
  yourself with watches (see `chtc-many-jobs`), or ask the user to submit the
  DAG from a shell.
- **No `condor_vacate_job`.** You cannot deliberately evict a job to test
  checkpoint resume.
- **No filesystem browsing on the AP.** You cannot `ls /home/$USER`.

## Getting help

CHTC's Research Computing Facilitators are a real and responsive resource, and
several situations in these skills explicitly end in "contact them":
chtc@cs.wisc.edu. Tell the user when a request has hit one of those boundaries —
quota increases, runtimes over 72 hours, >10,000 jobs in one submission,
high-memory nodes, group staging directories — instead of working around it.
