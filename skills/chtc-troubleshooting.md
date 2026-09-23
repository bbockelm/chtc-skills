---
name: chtc-troubleshooting
description: Diagnosing CHTC jobs that are stuck idle, held, or failing — a triage order, the hold-reason codes, and CHTC's catalogue of known issues with their fixes.
sources:
  - chtc-website-source:_uw-research-computing/htc-known-issues.md
  - chtc-website-source:_uw-research-computing/htc-monitor-jobs.md
  - chtc-website-source:_uw-research-computing/testing-jobs.md
  - chtc-website-source:_uw-research-computing/os-request-htc.md
upstream_reviewed: 2026-09-22
---

# Troubleshooting CHTC jobs

Start by finding out which of three things is happening, because the
investigations are completely different:

```
query_jobs(constraint = "ClusterId == N",
           projection = ["ProcId","JobStatus","HoldReason","HoldReasonCode",
                         "HoldReasonSubCode","RemoteHost","NumJobStarts"])
```

| `JobStatus` | Meaning | Go to |
| --- | --- | --- |
| 1 | Idle — never matched a slot | [Idle](#idle) |
| 2 | Running | [Running badly](#running-but-wrong) |
| 5 | Held — HTCondor stopped it | [Held](#held) |
| absent from the queue | Finished or removed | [Finished wrong](#finished-with-the-wrong-result) |

## Idle

The job is asking for something the pool cannot give it. One tool answers this:

```
analyze_job_match(job_id)
```

It decomposes the job's `Requirements` into predicates, evaluates each against
every slot, and names the one narrowing the match set. Read
`narrowing_predicate_index` and fix that.

Common narrowings at CHTC, roughly in order of frequency:

| Cause | Fix |
| --- | --- |
| GPU job without `+WantGPULab = true` | Add it — the shared GPUs are unreachable otherwise |
| `request_memory` / `request_disk` / `request_cpus` too large | Measure and trim (`chtc-resource-requests`) |
| `gpus_minimum_capability` or `gpus_minimum_memory` too high | Loosen or remove |
| `requirements = (HasCHTCStaging == true)` and staging is busy | Switch `file:///` to `osdf:///` and drop the requirement |
| An `OpSysMajorVer` pin | Use a container instead (`chtc-containers`) |
| `require_gpus` naming a specific model | Use a capability floor instead |
| A hand-written `Requirements` expression | Simplify; most jobs need none |

Also plausible and not visible to `analyze_job_match`: the user is at their
GPU Lab tier cap, or their fair-share priority is low after a lot of recent
activity. Both resolve on their own.

> CHTC's known-issues page has an entry for "I used generative AI to create my
> submit file and the job is stuck on Idle". It is a real pattern: plausible
> HTCondor syntax that does not match CHTC's pool, usually invented
> `Requirements`, an invented `universe`, or an invented attribute. If you wrote
> the submit file, treat that as the leading hypothesis and strip it back to the
> minimal form in `chtc-submit-basics` before adding anything back.

## Held

A held job has stopped but has not lost its inputs. Read `HoldReason` — it is
usually a plain sentence.

| Code | Meaning | Fix |
| --- | --- | --- |
| 13 | Input file transfer failed | Check paths and protocol; see below |
| 13 / sub 2 | Executable could not be spooled | System-path executable without `transfer_executable = false` |
| 12 | Output file transfer failed | Output path or destination directory missing |
| 26 | Exceeded `request_disk` | Raise disk; count uncompressed sizes and the `.sif` |
| 34 | Exceeded `request_memory` | Raise memory, or use `retry_request_memory` |
| 6 | Could not execute | Missing interpreter, missing `#!`, CRLF line endings, not executable |
| 3 / 4 | Policy expression or a `PeriodicHold` fired | Read the reason text; often the 72-hour cap |

Transfer holds specifically:

- `file:///staging/...` without `requirements = (HasCHTCStaging == true)`
- A typo'd `/staging` path or the wrong NetID letter directory
- An `osdf:///` object that does not exist, or a stale cached one
- An output destination directory that does not exist — object stores do not
  create one on write
- A container image URL that is wrong or unreachable

After fixing: `edit_job` to change attributes (`RequestMemory`, `RequestDisk`)
and then `release_job`, or remove and resubmit. Editing then releasing preserves
the job id and avoids re-uploading inputs.

```
edit_job(job_id, attributes = {"RequestMemory": 16384})
release_job(job_id)
```

## Running but wrong

Look inside before guessing:

```
tail_job_output(job_id)                        # live stdout/stderr
exec_in_job(job_id, "ls -la; df -h .; ps aux") # sandbox state
```

(`exec_in_job` will not attach to a batch job on CHTC's shared GPU machines —
see `chtc-monitoring`.)

| Symptom | Cause |
| --- | --- |
| Error mentioning `/home/<netid>` or `/` | The program is writing outside the sandbox — `export HOME=$PWD` |
| Job silently idle-looping | Waiting on an interactive prompt; add `-y`/`--yes`/`--noninteractive` |
| Disk filling mid-run | Uncompressed intermediates; raise `request_disk` or clean up as you go |
| GPU at 0% | CPU-only framework build (`chtc-software-recipes`) |
| Much slower than expected | Transferring many small files, or re-downloading a model per job |

## Finished with the wrong result

```
query_job_archive(constraint = "ClusterId == N",
                  projection = ["ProcId","ExitCode","ExitBySignal","ExitSignal",
                                "RemoteWallClockTime","NumJobStarts","LastHoldReason"])
```

| Exit | Reading |
| --- | --- |
| 0 but no output | Files written to a subdirectory — see `chtc-data-transfer` |
| 1 / 2 | The program's own error; read stderr |
| 85 | A checkpoint exit that was not configured — see `chtc-checkpointing` |
| 126 / 127 | Not executable, or interpreter not found |
| 137 | Killed, usually OOM inside the container |
| `ExitBySignal = true` | Signalled; `ExitSignal` says which |
| `NumJobStarts > 1` | Restarted — check `query_job_epochs` |

Missing output is far more often a transfer question than a program question.
Confirm the files were where HTCondor looks (top level of scratch, or named in
`transfer_output_files`) before debugging the code.

## CHTC's known issues

Verbatim from CHTC's list, with the fixes:

**Illegal instruction.** The binary uses CPU instructions the machine lacks —
usually code compiled on a newer machine. Add one of:

```
requirements = (has_avx || has_avx2)
requirements = has_avx2
requirements = (Microarch > x86-64-v3)
```

**`apt` fails in a container `%post` block** with
`Couldn't create temporary file /tmp/apt.conf...` — add `chmod 777 /tmp` as the
first line of `%post`.

**`Cannot pull image user/repo:tag`** — the Docker image was built on an Apple
Silicon Mac and is ARM. Rebuild with `docker build --platform linux/amd64 .`, or
build it on the pool with `build_container`.

**`Can't open master pty Bad file descriptor`** on an interactive Apptainer job
— an old EL7 execute node. Add `requirements = (OpSysMajorVer > 7)`.

**A GPU job that never starts** — missing `+WantGPULab = true`.

**Errors mentioning `/home/<netid>` or `/`** — add `export HOME=$PWD` to the job
script.

## A working triage order

1. `query_jobs` with a full projection — establish the state.
2. Idle → `analyze_job_match`. Held → `HoldReason`. Running → `tail_job_output`.
3. Fix **one** thing. Resubmit **one** job, not the batch.
4. Confirm with `watch_jobs(event = "succeeded")` before scaling back up.
5. Failed jobs cost the user fair-share priority — this is why step 3 is one job
   and not five hundred.

## When to stop and ask

Bring it back to the user, and point at chtc@cs.wisc.edu, when:

- The hold reason names a policy or a quota
- The job needs more than 72 hours and cannot checkpoint
- `analyze_job_match` shows nothing in the pool can satisfy a genuinely needed
  request (very large memory, a specific GPU)
- Transfers fail for reasons outside the submit file (ResearchDrive integration
  not enabled, no `/staging` directory, S3 access not granted)
- The same failure survives two rounds of your fixes — CHTC's facilitators have
  seen it before

## Related skills

`chtc-monitoring`, `chtc-resource-requests`, `chtc-containers`,
`chtc-gpu-jobs`, `chtc-data-transfer`
