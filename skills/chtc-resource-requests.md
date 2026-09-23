---
name: chtc-resource-requests
description: How to choose request_cpus, request_memory and request_disk at CHTC, and how to read what a finished job actually used through the history tools instead of the .log file.
sources:
  - chtc-website-source:_uw-research-computing/testing-and-scaling-up.md
  - chtc-website-source:_uw-research-computing/htcondor-job-submission.md
  - chtc-website-source:_uw-research-computing/variable-memory.md
upstream_reviewed: 2026-09-22
---

# Getting resource requests right

Requests are a matching contract. Ask for more than the job needs and it matches
fewer slots, waits longer, and crowds out the user's other work; ask for less and
HTCondor holds it. Neither failure announces itself as a resource problem, so
this is worth a deliberate step rather than a guess.

The CHTC advice here is unchanged by the MCP interface — what changes is that
you read the usage numbers from the history tools rather than from the tail of a
`.log` file you no longer have shell access to.

## Starting points for the first test job

**CPUs — start at 1.** Requesting more cores does not make software use more
cores; most software is single-threaded by default. Match the request to the
thread count the program is actually configured for (`-t`, `--threads`,
`OMP_NUM_THREADS`, `nproc` inside the script). Single-CPU jobs start sooner and
give better total throughput than a smaller number of wide jobs. CHTC has
limited support for large multicore work on the HTC system — over roughly 16–20
cores, talk to the facilitators.

**Disk — add it up.** Input files + the executable + everything the job writes +
`stdout`/`stderr`. If inputs arrive compressed, count the *uncompressed* size
too, since both copies exist on disk at once. Container images count: a `.sif`
transferred into the job occupies disk in the sandbox. Over-request on the first
test; trim afterwards.

**Memory — borrow a number.** If the work has run on a laptop, use that laptop's
RAM as the ceiling. Over-request on the first test, then measure. Above ~200 GB
you are on CHTC's dedicated high-memory machines and should email the
facilitators first.

**GPU memory** is separate from `request_memory` and is requested with
`gpus_minimum_memory` (see `chtc-gpu-jobs`).

## Measuring what a job used

After the job finishes, query the history rather than reading the `.log`:

```
query_job_archive(
  constraint = "ClusterId == 12345",
  projection = ["ClusterId","ProcId","ExitCode","JobStatus",
                "RequestCpus","CpusUsage",
                "RequestMemory","MemoryUsage","ResidentSetSize",
                "RequestDisk","DiskUsage",
                "RemoteWallClockTime","NumJobStarts"]
)
```

Units, which are not consistent and cause real errors:

| Attribute | Unit | Note |
| --- | --- | --- |
| `RequestMemory`, `MemoryUsage` | MB | |
| `ResidentSetSize` | KB | peak RSS observed |
| `RequestDisk`, `DiskUsage` | KB | |
| `RemoteWallClockTime` | seconds | summed over all starts |
| `CpusUsage` | cores | average, fractional |

If `query_history_db` is available on this access point, prefer it for anything
touching more than a few hundred finished jobs — it reads a durable mirror
instead of scanning the schedd's history file.

For the shape of a whole batch rather than one job, group it:

```
aggregate_jobs(table = "history", constraint = "ClusterId == 12345",
               group_by = ["ExitCode"])
```

## Turning measurements into requests

Set each request to the observed peak plus headroom, not to the average:

- **Memory:** peak `ResidentSetSize` (÷1024 for MB) × 1.3, rounded up to a
  sensible boundary. Memory is the request most likely to vary with input size,
  so measure on your *largest* input, not a typical one.
- **Disk:** peak `DiskUsage` × 1.3.
- **CPUs:** if `CpusUsage` is ~1.0 on a 4-CPU request, the software is not
  threading; drop the request to 1 and the jobs will start much sooner.

If inputs span a wide size range, run tests on both the smallest and the largest
so the request covers the range. If the range is very wide, it is better to
submit two batches with different requests than one batch sized for the worst
case.

### Memory that varies per job

For a batch where memory need is a known function of the input, set it per job
from the queue statement rather than sizing everything for the largest:

```
request_memory = $(mem)
queue sample, mem from samples.txt
```

When only a *few* jobs in a batch spike, CHTC's recommended answer is
`retry_request_memory`: size the batch for the common case and let the outliers
retry larger, instead of over-requesting for every job.

```
request_memory       = 1 GB
retry_request_memory = 4 GB
```

A job evicted for exceeding its memory is automatically restarted with the
larger request. Expressions work too — `retry_request_memory = RequestMemory*4`
— but stick to integer multipliers; addition and floating point are not
recommended.

## Reading a failure as a resource problem

| Symptom | Reading |
| --- | --- |
| `JobStatus == 5`, `HoldReasonCode == 34` | Exceeded `request_memory` |
| `JobStatus == 5`, `HoldReasonCode == 26` | Exceeded `request_disk` |
| Killed abruptly mid-build with no message | Almost always disk |
| `ExitCode == 137` | OOM-killed inside the job (often a container) |
| Job idle for hours, `analyze_job_match` narrows on a request | Request too large for the pool |

`analyze_job_match(job_id)` is the direct tool for the last row: it decomposes
the job's `Requirements` and reports which predicate is eliminating slots. A
request that no slot satisfies shows up there immediately.

## Related skills

`chtc-submit-basics`, `chtc-troubleshooting`, `chtc-policies-and-limits`,
`chtc-gpu-jobs`
