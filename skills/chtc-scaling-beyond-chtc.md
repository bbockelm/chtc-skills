---
name: chtc-scaling-beyond-chtc
description: Opting CHTC jobs into UW campus pools and the OSPool with want_campus_pools and want_ospool — whether the work qualifies, what must change first, and how to test.
sources:
  - chtc-website-source:_uw-research-computing/scaling-htc.md
  - chtc-website-source:_uw-research-computing/htc-overview.md
  - chtc-website-source:_uw-research-computing/apptainer-htc.md
upstream_reviewed: 2026-09-22
---

# Scaling beyond CHTC

CHTC users can opt their jobs into two additional pools:

- **UW campus pools** — HTCondor pools run by other UW groups (Biochemistry,
  Statistics, IceCube, CMS) that accept outside jobs when not fully used.
- **The OSPool** — the national Open Science Pool, operated by CHTC as the home
  of the PATh project, with capacity contributed by campuses and labs across the
  US.

The payoff is large and concrete: CHTC states that most users who submit to
CHTC, the campus pools and the OSPool together can get **more than 100,000 core
hours in a single day**. For a workload that fits, this is usually the highest
-value change available.

## Two lines

```
want_campus_pools = true
want_ospool       = true
```

That is the whole opt-in. Jobs still run at CHTC too; these add capacity rather
than redirecting.

## Does the work qualify?

| | Requirement | Why |
| --- | --- | --- |
| **Runtime** | Under ~10 hours per job, or checkpointing at least that often | These machines are backfill; jobs get evicted |
| **Data** | Up to ~20 GB in/out per job, over `/home` transfer or an `osdf:///` URL | Other transfer paths don't exist off-site |
| **Software** | An Apptainer container | The only reliable way to get a consistent environment |

Check all three before adding the lines. A job that fails any of them will be
evicted repeatedly, wasting capacity and the user's fair-share priority, and
looking like a mysterious intermittent failure.

## What usually has to change first

**Containerise.** Almost anything that runs at CHTC will run elsewhere, but only
a container guarantees it. Apptainer specifically — the OSPool supports it best.
Already on Apptainer: nothing to do. On Docker: convert (`chtc-containers`).
Not containerised: that is the prerequisite.

**Switch transfers to `osdf:///`.** This is the change people forget:

```
# CHTC-only — will not work off-site
container_image      = file:///staging/a/alice/env.sif
transfer_input_files = file:///staging/a/alice/ref.tar.gz
requirements         = (HasCHTCStaging == true)

# Works everywhere
container_image      = osdf:///chtc/staging/a/alice/env.sif
transfer_input_files = osdf:///chtc/staging/a/alice/ref.tar.gz
# no HasCHTCStaging requirement
```

`file:///` needs the `/staging` filesystem mounted, which only CHTC machines
have; `requirements = (HasCHTCStaging == true)` pins the job to CHTC and
silently negates the opt-in. `osdf:///` travels over the OSDF and is cached near
the execute site, so a reference dataset read by thousands of jobs is fetched
from a nearby cache rather than from Madison every time.

`pelican://` ResearchDrive paths behave the same way and work off-site.

**Shorten the jobs.** If they run 30 hours, either split the work or checkpoint
(`chtc-checkpointing`). Do not just add the two lines and hope.

**Drop CHTC-specific requirements.** `HasCHTCStaging`, `+WantGPULab`,
`+GPUJobLength`, `+IsBuildJob` and CHTC machine names mean nothing off-site;
some actively exclude the extra capacity.

## Testing off-site first

CHTC asks for a test run of 10–2000 jobs **forced off CHTC**, so failures
specific to the external pools surface before a full batch:

```
requirements      = (Poolname =!= "CHTC")
want_campus_pools = true
want_ospool       = true
```

If the submit file already has a `requirements` line, AND the new clause onto it
with `&&`.

Then check the batch as a whole rather than job by job:

```
aggregate_jobs(table = "history", constraint = "ClusterId == N",
               group_by = ["ExitCode"])
```

and look at where they ran:

```
query_job_archive(constraint = "ClusterId == N",
                  projection = ["ProcId","ExitCode","LastRemoteHost",
                                "RemoteWallClockTime","NumJobStarts"])
```

`NumJobStarts` well above 1 across the batch means eviction is happening faster
than the jobs finish — the jobs are too long for this capacity.

**Then remove the `Poolname` requirement** and keep `want_campus_pools` /
`want_ospool` for the production run. Leaving it in permanently excludes CHTC's
own machines, which is the opposite of the goal.

## What to expect

- **More jobs running at once**, sometimes dramatically.
- **More variability.** Heterogeneous hardware, so per-job runtimes spread out.
- **Occasional restarts.** Eviction is normal here, not a fault. Watch
  `NumJobStarts`; make sure a restarted job is safe to restart — idempotent, or
  checkpointing.
- **GPUs.** There is real GPU capacity in the campus pools and the OSPool, and
  for GPU work this is often the fastest route to more throughput. The same
  qualification rules apply, plus a container with a CUDA build that does not
  demand the very newest driver.

## When it will not help

- Jobs needing more than ~20 GB of data movement each
- Jobs needing `/staging` over `file:///`, or CHTC high-memory nodes
- Long, non-checkpointable jobs
- Anything with licensing that is CHTC-site-bound (see `chtc-software-recipes`)

If the user's work has large data or long jobs, CHTC explicitly asks to be
contacted rather than having people improvise: chtc@cs.wisc.edu.

## Related skills

`chtc-containers`, `chtc-checkpointing`, `chtc-data-transfer`,
`chtc-gpu-jobs`, `chtc-policies-and-limits`
