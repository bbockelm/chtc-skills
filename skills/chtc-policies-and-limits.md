---
name: chtc-policies-and-limits
description: The CHTC limits and policies that change what you should submit — runtime caps, job-count limits, storage quotas, data handling rules, and what requires emailing the facilitators.
sources:
  - chtc-website-source:_uw-research-computing/htc-overview.md
  - chtc-website-source:_uw-research-computing/user-expectations.md
  - chtc-website-source:_uw-research-computing/file-avail-largedata.md
  - chtc-website-source:_uw-research-computing/gpu-jobs.md
  - chtc-website-source:_uw-research-computing/high-memory-jobs.md
upstream_reviewed: 2026-09-22
---

# CHTC policies and limits

These are defaults, not walls. CHTC's stated position is that they want users
running at far larger scale than the defaults allow, and that hitting a limit is
a reason to email chtc@cs.wisc.edu, not a reason to give up or to engineer
around it. Say so to the user when you hit one.

## Runtime

| Where the job runs | Maximum runtime |
| --- | --- |
| CHTC HTC pool, CPU job | **72 hours**, then held |
| GPU Lab, `+GPUJobLength = "short"` | 12 hours |
| GPU Lab, `+GPUJobLength = "medium"` (default) | 24 hours |
| GPU Lab, `+GPUJobLength = "long"` | 7 days, max 4 GPUs in use |
| Backfill / research-group GPUs (`+is_resumable`) | No guarantee; evictable |
| Campus pools or OSPool (`want_campus_pools` / `want_ospool`) | No guarantee; aim for <10 h |
| Interactive GPU job | 4 hours |
| Interactive build job (`+IsBuildJob = true`) | 4 hours |

A job that exceeds its cap goes to **held** (JobStatus 5), not to failed. It has
not lost its inputs; see `chtc-troubleshooting`.

Longer than 72 hours: either implement checkpointing (`chtc-checkpointing`) or
ask the facilitators. Do not attempt to evade the cap.

## Job counts and rates

| Limit | Value | What to do instead |
| --- | --- | --- |
| Jobs per submission | 10,000 | Split, or email CHTC |
| Total queued per user | 50,000 | Email CHTC |
| Minimum average runtime above 1000 jobs | **5 minutes** | Bundle several calculations into one job |
| Above 10,000 jobs | add `max_idle = 10000` | Keeps the schedd healthy |

Many *short* jobs are worse for the access point than a few long ones. If the
user's unit of work is 30 seconds, the right fix is to have each job process a
batch of units, not to submit 100,000 jobs.

## Storage quotas

| Location | Default disk quota | Default item quota | For |
| --- | --- | --- | --- |
| `/home/<netid>` | 40 GB (older docs say 20 GB) | none | Submit files, scripts, small inputs, outputs |
| `/staging/<first letter>/<netid>` | 100 GB | 1000 items | Few, large files (>1 GB each), container images |
| `/staging/groups/<group>` | by arrangement | by arrangement | Shared group data |
| CHTC S3 buckets | by request | by request | Large data that must be reachable outside CHTC |

You cannot check a quota from this interface. Ask the user to run `quota -vs`
(for `/home`) or `get_quotas` (for `/staging`) on the access point, or to use
CHTC's quota request form.

A blank `get_quotas` means the user has no `/staging` directory yet — CHTC
creates one on request.

## Data policies

These are non-negotiable and worth repeating to a user who is about to lean on
CHTC as a data store:

- **Nothing at CHTC is backed up.** `/home`, `/staging`, and S3 buckets can all
  be lost. A primary copy of anything essential belongs somewhere else.
- **Storage is for actively-queued work.** Data should be removed as soon as the
  jobs that need it have finished. Staff reserve the right to delete data to
  preserve filesystem performance, and violating the `/staging` intended-use
  policy can get staging access or the account revoked.
- **CHTC is not HIPAA compliant and not CUI compliant.** Do not help move such
  data here.
- **Export-controlled data requires prior review** by the UW–Madison Export
  Control Office (exportcontrol@grad.wisc.edu).
- **Accounts are per-person and must not be shared.** A shared account is
  disabled on discovery. This applies to credentials you might be tempted to
  store with `store_service_credential` too — store the user's own.

## Specialised hardware

**High memory.** Jobs over ~200 GB of memory match CHTC's dedicated high-memory
servers (16 × 512 GB, 2 × 2 TB). CHTC asks to be emailed before a user runs
high-memory work for the first time or runs a new kind of it. Requesting
hundreds of GB restricts the job to a handful of machines, so the queue wait is
long — check first that the memory is genuinely needed (see
`chtc-resource-requests`).

**GPUs.** See `chtc-gpu-jobs`. The GPU Lab has its own runtime tiers and
per-user share limits, listed above.

**Operating system.** The execute pool is heterogeneous. Prefer a container over
an OS requirement — it lets the job run almost anywhere. If you must pin,
`requirements = (OpSysMajorVer >= 9)` is the form; note that code compiled on a
newer EL release may not run on an older one.

## Fair share

CHTC is not first-in-first-out. A user who has run a lot recently gets lower
priority; an idle user's jobs start sooner. Priority recovers on its own over
time.

Two consequences that should change your behaviour:

1. **Failed jobs cost real priority.** Submitting 5000 jobs that all die on a
   typo lowers the user's priority for days and produces nothing. This is the
   concrete reason for the test-one-then-a-few-then-all discipline.
2. **Smaller and more flexible requests start sooner.** A job asking for 1 CPU
   and 2 GB matches far more slots than one asking for 16 CPUs and 64 GB, and a
   job that accepts any GPU matches more than one that names a model. Throughput
   usually comes from many small jobs, not from a few large ones.

## What requires contacting the facilitators

Bring these back to the user rather than trying to solve them:

- Runtime beyond 72 hours that checkpointing cannot cover
- More than 10,000 jobs in one submission, or more than 50,000 queued
- A quota increase on `/home`, `/staging`, or S3 (after clearing old data)
- A new or group `/staging` directory
- First-time high-memory work, or large-scale multicore work
- Individual files over 100 GB
- S3 bucket creation access
- Anything involving restricted, export-controlled, or clinical data

Email: chtc@cs.wisc.edu
