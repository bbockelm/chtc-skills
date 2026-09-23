---
name: chtc-submit-basics
description: How to write and submit a CHTC HTC job through this MCP server — submit-file conventions used at CHTC, getting the executable and inputs to the job, and the test-first sequence.
sources:
  - chtc-website-source:_uw-research-computing/htcondor-job-submission.md
  - chtc-website-source:_uw-research-computing/testing-and-scaling-up.md
  - chtc-website-source:_uw-research-computing/htc-job-file-transfer.md
upstream_reviewed: 2026-09-22
---

# Submitting a job at CHTC

CHTC's own tutorial has the user log in, write `hello-world.sh` with `nano`,
`chmod +x` it, and run `condor_submit hello-world.sub`. Through this server the
job is the same; the choreography is different. There is no login, no editor,
and no `chmod`.

## The sequence

```
submit_job(submit_file = "...")         →  cluster id
upload_job_input(job_id, files = [...]) →  executable + small inputs
watch_jobs(constraint = "ClusterId == N", event = "done")
check_watches(wait_seconds = ...)
get_job_stdout(job_id) / get_job_stderr(job_id) / get_job_output(job_id)
```

`submit_job` takes the submit description as text. `upload_job_input` puts files
into the job's input spool *after* submission and before it starts — this is
what replaces "create the file in your home directory". Pass
`is_executable: true` for the script that will be the `executable`; that is the
`chmod +x` step.

A job with files still to be uploaded sits in the spooling state; once
`upload_job_input` returns it becomes Idle and can be matched.

## A CHTC submit file

```
# analysis.sub

executable              = run_analysis.sh
arguments               = $(Process)

log                     = analysis_$(Cluster)_$(Process).log
output                  = analysis_$(Cluster)_$(Process).out
error                   = analysis_$(Cluster)_$(Process).err

transfer_input_files    = sample.csv

request_cpus            = 1
request_memory          = 2GB
request_disk            = 4GB

queue 1
```

Points that are CHTC-specific or easy to get wrong:

- **`log` is not optional in practice.** The `.log` file is where HTCondor
  records the resource-usage table you need for right-sizing, and it is the file
  CHTC support will ask about. Always set it.
- **`request_cpus`, `request_memory`, `request_disk` are effectively
  mandatory.** CHTC expects explicit requests. `request_memory` in bare numbers
  is MB, `request_disk` in bare numbers is KB — prefer explicit `2GB` / `4GB` to
  avoid the factor-of-1000 class of mistake.
- **`$(Process)`** is 0-based and unique per job in the cluster; `$(Cluster)` is
  the submission's id. Use them to keep per-job filenames distinct, or many jobs
  will overwrite each other's output.
- **`universe`** rarely needs setting. Omit it unless you are using
  `universe = docker`, and prefer `container_image` over the docker universe
  (see `chtc-containers`).
- **`should_transfer_files` / `when_to_transfer_output`** appear in older CHTC
  examples. They are the defaults now; leaving them out is fine and leaving them
  in is harmless.

### `executable`/`arguments` versus `shell`

CHTC documents both. They differ in who transfers the script:

```
# Option A — executable + arguments  (RECOMMENDED here)
executable = run_analysis.sh
arguments  = $(Process)
# HTCondor transfers run_analysis.sh automatically.
# upload_job_input it with is_executable = true.

# Option B — shell
shell                = ./run_analysis.sh $(Process)
transfer_input_files = run_analysis.sh
# You must list the script yourself, and it must be executable.
```

Prefer **Option A** through this interface: one fewer thing to get wrong, and
the `is_executable` flag on `upload_job_input` handles the permission bit. Use
`shell` only for a one-liner you do not want to ship a file for, and keep it
simple — quoting and special characters cause more trouble than they save.

### `transfer_executable = false`

If the executable is a system binary that already exists on the execute node —
`/bin/bash`, `/usr/bin/python3` — set `transfer_executable = false`. Otherwise
HTCondor tries to spool a copy that does not exist and the job holds on file
transfer (HoldReasonCode 13, subcode 2). `submit_job` rejects that combination
up front rather than letting you find out an hour later.

```
executable          = /bin/bash
transfer_executable = false
arguments           = -c "echo hello"
```

### `$(...)` is macro expansion, not shell substitution

The submit parser eats every `$(...)` before the shell ever sees it. An
undefined name expands to nothing and the job runs a corrupted command line:

```
arguments = -c "echo HOST:$(hostname)"    # bash receives: -c "echo HOST:"
```

`$(Cluster)`, `$(Process)`, `$(ProcId)`, `$(ItemIndex)`, `$(Step)`, `$(Row)` and
your own submit-file variables are the intended use. Anything that needs the
shell belongs in a script you upload.

## Getting inputs in

| Input | How |
| --- | --- |
| The executable, small scripts, config | `upload_job_input` (aim under ~100 KB total) |
| Data already on the web | `transfer_input_files = https://...` |
| Data in the user's `/staging` | `transfer_input_files = osdf:///chtc/staging/<u>/<netid>/file` |
| Data on ResearchDrive | `transfer_input_files = pelican://chtc.wisc.edu/researchdrive/<PI>/CHTC/file` |
| Anything large on your own machine | `create_input_upload_url`, then `tar cf - … \| curl -T - '<url>'` |

Do not paste a multi-megabyte data file through `upload_job_input`; it goes
through the conversation. `create_input_upload_url` exists precisely so the bytes
go straight to the access point. Full detail in `chtc-data-transfer`.

## Getting outputs back

By default HTCondor returns **new or changed files in the job's top-level
scratch directory** to the submit directory. Files written into subdirectories
are silently not returned — the single most common "where did my results go"
at CHTC. Either write to the top level, tar the directory before exiting, or
name the paths explicitly:

```
transfer_output_files = results.tar.gz
```

Then read them with `get_job_stdout`, `get_job_stderr`, and `get_job_output`.
For large outputs, send them straight to `/staging` or ResearchDrive with
`transfer_output_remaps` or `output_destination` rather than routing them
through `/home` (see `chtc-data-transfer`).

## Two environment gotchas that bite almost everyone

Put these in the job script by default:

```bash
#!/bin/bash
set -euo pipefail
export HOME=$PWD        # /home and / are not writable on execute nodes
```

Many tools (pip, conda, R, matplotlib, huggingface, torch) try to write a cache
into `$HOME` and fail with an error mentioning `/home/<netid>` or `/`. Setting
`HOME` to the scratch directory fixes the whole class.

The second: the job starts in a scratch directory that is deleted when the job
ends. Nothing persists between jobs except what you transfer out.

## Test first — this is a policy, not a style preference

CHTC's fair-share scheduler lowers a user's priority for jobs that run,
including jobs that fail. A batch of 5000 jobs that all die on the same typo
costs the user days of priority and produces nothing.

1. **One job.** Confirm it completes and the output is what you expect.
2. **Three to ten jobs from one submit file.** Confirm they do not collide —
   distinct output filenames, no shared scratch assumptions.
3. **Scale up.** Under 500 jobs, go straight there. Over 500, do an intermediate
   run of 100–1000 first.

Read the resource-usage table at the bottom of the `.log` (or query it, see
`chtc-resource-requests`) after step 1 and adjust the requests before step 3.

## Related skills

`chtc-resource-requests`, `chtc-data-transfer`, `chtc-many-jobs`,
`chtc-monitoring`, `chtc-troubleshooting`, `chtc-containers`
