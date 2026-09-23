---
name: chtc-monitoring
description: Watching CHTC jobs through the MCP server — the no-polling rule, event watches instead of condor_watch_q, reading a running job's output, and querying finished batches.
sources:
  - chtc-website-source:_uw-research-computing/htc-monitor-jobs.md
  - chtc-website-source:_uw-research-computing/condor_q.md
  - chtc-website-source:_uw-research-computing/user-expectations.md
  - chtc-website-source:_uw-research-computing/agent-recommendations.md
upstream_reviewed: 2026-09-22
---

# Monitoring jobs at CHTC

CHTC has one firm rule here and it is aimed squarely at agents: **do not poll**.
`watch condor_q` is explicitly prohibited, and CHTC's AI-agent guidance names
polling `condor_q` in tight loops as a specific thing not to let an agent do. A
high-frequency query loop overwhelms the schedd and slows every user's jobs.

This server gives you a better answer than restraint: a watch mechanism that
tells you when something happens rather than making you ask.

## Tool map

| CHTC command | Use instead |
| --- | --- |
| `condor_q` | `query_jobs` — one-off snapshot |
| `condor_q` to count | `aggregate_jobs` with `group_by` |
| `condor_watch_q` | `watch_jobs` + `check_watches` |
| `watch condor_q` | **never** — this is what watches replace |
| `condor_q -hold` | `query_jobs` projecting `HoldReason`, `HoldReasonCode` |
| `condor_q -better-analyze` | `analyze_job_match` |
| `condor_q -l <id>` | `get_job` |
| `condor_tail` | `tail_job_output` |
| `condor_ssh_to_job` | `exec_in_job` |
| `condor_history` | `query_job_archive`, or `query_history_db` |

## Waiting: the correct pattern

```
watch_jobs(constraint = "ClusterId == 12345", event = "done")
      → watch_id
check_watches(wait_seconds = 300)
      → fired, or progress
check_watches(wait_seconds = 300)     # repeat until answered
```

- `watch_jobs` **registers the question once**. Calling it again resolves to the
  same watch; it does not check and does not wait.
- `check_watches` is the one that reports and the one that waits. Call it again
  until it answers.
- If the condition is already true when you register, it fires immediately — so
  it is safe to register after submitting, or after the jobs have finished.

Events: `done`, `succeeded`, `failed`, `held`, `running`, `custom`. Defaults for
`mode` are `all` for `done`/`succeeded` and `any` for `failed`/`held`/`running`,
which is the plain reading of each.

**Do not write `constraint = "JobStatus == 4"` to wait for completion.** A
finished job leaves the queue, so that condition is never observed. Use
`event = "done"`, which is resolved across the queue *and* the history archive.

A useful pair for a long batch — react to the first failure without waiting for
the whole thing:

```
watch_jobs(constraint = "ClusterId == 12345", event = "failed", label = "trouble")
watch_jobs(constraint = "ClusterId == 12345", event = "done",   label = "finished")
```

A constraint matching nothing is accepted rather than rejected — it will fire if
matching jobs appear later — and the response says so, because far more often it
means a wrong ClusterId than a genuine future match. Read that line.

## Snapshots

```
query_jobs(constraint = "ClusterId == 12345",
           projection = ["ClusterId","ProcId","JobStatus","RemoteHost",
                         "HoldReason","NumJobStarts","EnteredCurrentStatus"])
```

`JobStatus`: 1 idle, 2 running, 3 removed, 4 completed, 5 held, 6 transferring
output, 7 suspended.

**Always pass a projection.** The default returns a small fixed set of
attributes, and an attribute that is absent because it was not projected looks
exactly like an attribute that is zero.

For "how many are idle/running/held", count server-side rather than listing:

```
aggregate_jobs(constraint = "ClusterId == 12345", group_by = ["JobStatus"])
```

Only the grouped result crosses the wire. This is the right tool for a
thousand-job batch and the wrong thing to do by fetching a thousand ads.

## Reading a running job

`tail_job_output(job_id)` reads stdout/stderr **from the execute node**, live.
This is how you find out whether a job is progressing or wedged, without waiting
for it to end.

- Pass back the offsets it returns to get only what is new.
- **Poll no more than once every 5 seconds**, and prefer a watch if what you
  actually want is an event.
- It is the wrong tool once the job has finished — then use `get_job_stdout` /
  `get_job_stderr`, which read the transferred files.

`stream_output = true` in the submit file makes output appear as it is produced
rather than in buffered chunks, which makes tailing much more useful.

To look around inside a running job — list the sandbox, check a process, read an
intermediate file — `exec_in_job(job_id, command)` connects, runs one command,
and disconnects. This is `condor_ssh_to_job` for a single command, and it works
on ordinary batch jobs, not only sessions.

> **Not available on CHTC's shared GPU machines.** `condor_ssh_to_job` was
> disabled there in April 2026 because it was being used to hold GPUs idle. Use
> `tail_job_output`, or start a real interactive GPU session
> (`chtc-interactive-sessions`).

## Finished jobs

```
query_job_archive(constraint = "ClusterId == 12345",
                  projection = ["ProcId","ExitCode","ExitBySignal",
                                "RemoteWallClockTime","MemoryUsage","DiskUsage",
                                "NumJobStarts","LastHoldReason"])
```

Use `query_history_db` when available — it reads a durable mirror rather than
scanning the schedd's history, which matters above a few hundred records.

Related:

- `query_job_epochs` — one record per execution attempt, for jobs that started
  more than once. The tool for "why did this restart four times".
- `query_transfer_history` — per-transfer detail, for diagnosing slow or failing
  file transfers.
- `query_jobs_as_of` — the queue as it looked at a past instant, where the
  database supports it.

## A monitoring pattern for a real batch

```
1. submit_job                                     → cluster N
2. upload_job_input (executable, shared inputs)
3. watch_jobs(ClusterId == N, event="running")    → confirm it matched at all
4. tail_job_output on one proc                    → confirm it is doing the work
5. watch_jobs(ClusterId == N, event="held",  label="held")
   watch_jobs(ClusterId == N, event="done",  label="done")
6. check_watches(wait_seconds=600) until answered
7. aggregate_jobs(table="history", ClusterId == N, group_by=["ExitCode"])
8. query_job_archive for the failures only
```

Step 3 is worth the call: a job that never reaches `running` is a matching
problem (`analyze_job_match`), not a job problem, and you find that out in
minutes rather than hours.

## Things this interface does not have

- **No `condor_status`** — you cannot enumerate the pool. `analyze_job_match`
  answers the question people usually had.
- **No `condor_vacate_job`** — you cannot deliberately evict a job.
- **No queue-wide view of other users' jobs** unless you are an MCP admin; every
  answer states which scope it used. `whoami`, where available, says what you
  are authorised as.

## Related skills

`chtc-troubleshooting`, `chtc-submit-basics`, `chtc-many-jobs`,
`chtc-interactive-sessions`
