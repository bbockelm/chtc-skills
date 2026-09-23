---
name: chtc-gpu-jobs
description: Requesting GPUs at CHTC — the GPU Lab opt-in and job-length tiers, capability and memory requirements, backfill capacity, and why a GPU job sits idle.
sources:
  - chtc-website-source:_uw-research-computing/gpu-jobs.md
  - chtc-website-source:_uw-research-computing/gpu-lab.md
  - chtc-website-source:_uw-research-computing/htc-interactive-gpu-jobs.md
  - chtc-website-source:_uw-research-computing/htc-known-issues.md
  - templates-GPUs:README.md
upstream_reviewed: 2026-09-22
---

# GPU jobs at CHTC

CHTC has on the order of 150 shared GPUs against thousands of CPU cores, and
they are in constant demand. Two consequences shape everything here: **ask for
the least specific GPU that will work**, and **check first that the work
actually needs one**. A job that only uses a GPU because the framework was
installed with CUDA support will wait hours in the queue to run at CPU speed.

## The minimum viable GPU submit file

```
executable = run_training.sh

log    = job_$(Cluster)_$(Process).log
output = job_$(Cluster)_$(Process).out
error  = job_$(Cluster)_$(Process).err

container_image = osdf:///chtc/staging/a/alice/containers/torch-cu126.sif

request_gpus   = 1
request_cpus   = 1
request_memory = 8GB
request_disk   = 20GB

+WantGPULab    = true
+GPUJobLength  = "short"

queue 1
```

Four lines do the real work:

- **`request_gpus = 1`** — required for *every* GPU job, GPU Lab or not.
- **`request_cpus`** — always at least 1. The GPU does not run the Python
  interpreter, the data loader, or the I/O.
- **`+WantGPULab = true`** — opts into CHTC's shared GPU Lab machines. Omitting
  it is the single most common reason a GPU job sits idle forever: without it
  the job cannot match the shared GPUs at all.
- **`+GPUJobLength`** — declares which runtime tier the job wants.

## GPU Lab tiers

| `+GPUJobLength` | Max runtime | Per-user cap |
| --- | --- | --- |
| `"short"` | 12 hours | up to 2/3 of GPU Lab GPUs |
| `"medium"` (default if unset) | 24 hours | up to 1/3 of GPU Lab GPUs |
| `"long"` | 7 days | up to 4 GPUs in use |

Declaring `"short"` when the job really is short is free throughput: it triples
the share of the GPU Lab the user may occupy. Structure work to fit in 12 hours
— checkpoint, or split epochs across jobs — before reaching for `"long"`.

## Asking for a *capable enough* GPU

Prefer a floor over a model name:

```
gpus_minimum_capability = 7.5      # CUDA compute capability
gpus_minimum_memory     = 20000    # MB of GPU memory
gpus_maximum_capability = 9.0      # rarely needed
```

Compute capability loosely tracks GPU generation and is the right proxy for
"new enough". `gpus_minimum_memory` is GPU memory and is **separate from**
`request_memory`, which is host RAM — confusing these is a common source of
either a job that never matches or one that OOMs on the device.

`require_gpus` builds arbitrary expressions (`require_gpus = (Capability == 7.5)
&& (DriverVersion >= 11.3)`) but CHTC asks users to contact the facilitators
before using it. Older templates also use
`Requirements = (Target.CUDADriverVersion >= 10.1)`; prefer the
`gpus_minimum_*` form in new work.

Every narrowing costs queue time. Write code that runs across GPU generations
and does not need the newest CUDA, and the jobs start sooner.

## More capacity than the GPU Lab

**Research-group GPUs.** Some GPU servers are owned by groups and run other
people's jobs when idle. Jobs there forfeit the 72-hour guarantee and can be
interrupted. Opt in with:

```
+is_resumable = true
```

Worth it when jobs run in a few hours or less, or self-checkpoint at least every
4–6 hours. Without checkpointing, an evicted job loses everything — see
`chtc-checkpointing`.

**The `gzk` servers.** GPU Lab-like, with two differences: no `/staging` access
and no Docker. Nothing special is needed to use them, but a job that requires
`HasCHTCStaging` or uses `universe = docker` excludes itself from them. Another
reason to prefer `osdf:///` and `container_image`.

**Campus pools and the OSPool** carry substantial additional GPU capacity. See
`chtc-scaling-beyond-chtc`; containers plus `osdf:///` are effectively required.

## CUDA_VISIBLE_DEVICES

HTCondor sets `CUDA_VISIBLE_DEVICES` to the GPU(s) assigned to the job, and CUDA
reads it. **The job must not modify it or pick a device index itself** — doing so
lets two jobs land on one GPU and corrupt both. If code does
`torch.cuda.set_device(0)` or `os.environ["CUDA_VISIBLE_DEVICES"] = ...`, remove
it; index 0 within the job already *is* the assigned device.

## Multiple GPUs

`request_gpus = 2` works, but before using it:

1. Confirm the code actually uses multiple GPUs (`DataParallel`,
   `DistributedDataParallel`, `accelerate`, a multi-GPU flag). Most does not.
2. Submit a single test job and check that both devices are busy.
3. Compare the wall-clock saved against the extra queue wait. A 2-GPU job often
   finishes later than a 1-GPU job because it waits so much longer to start.

Note that CHTC's multi-GPU template pairs `request_gpus = N` with a higher
`request_cpus` (4 is typical) — the host side has to feed both devices.

## Interactive GPU work

CHTC reserves a small number of GPU Lab slots for interactive use (a handful of
RTX 2080 Ti and one A100), capped at **4 hours**.

**`condor_ssh_to_job` is unavailable on CHTC's shared GPU machines** as of April
2026 — it was being used to hold GPUs idle behind long `sleep` jobs. Through
this server that means `exec_in_job` will not attach to a batch GPU job on a
shared machine. Use instead:

- `tail_job_output` to follow a running GPU job's output, or
- `interactive_session_start(..., gpus = 1)`, which submits a genuine
  interactive job (see `chtc-interactive-sessions`).

Groups with owned or prioritised GPUs keep `condor_ssh_to_job`, so `exec_in_job`
may work on those machines.

## Diagnosing a GPU job that will not start

In order:

1. **Is `+WantGPULab = true` there?** Missing it is the most common cause.
2. **`analyze_job_match(job_id)`** — it names the predicate eliminating slots. A
   `gpus_minimum_capability` or `gpus_minimum_memory` that nothing satisfies
   shows up immediately.
3. **Loosen the request.** Drop a capability floor, reduce GPU memory, reduce
   `request_cpus`/`request_memory`, switch `"long"` to `"short"`.
4. **Consider the tier cap.** A user already at their GPU Lab share will not get
   more until earlier jobs finish.
5. **Consider CPUs instead.** CHTC's own guidance: when the work can use CPUs,
   use CPUs — there are far more of them and jobs start in minutes.

## Verifying the GPU is actually used

Put this at the top of the job script during testing:

```bash
nvidia-smi
python3 -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

Then read it with `tail_job_output` mid-run or `get_job_stdout` after. A job
reporting `False` is burning a scarce GPU on CPU work — the usual cause is a
CPU-only build of PyTorch or TensorFlow in the container
(`chtc-software-recipes`).

## Related skills

`chtc-ml-workflows`, `chtc-containers`, `chtc-checkpointing`,
`chtc-scaling-beyond-chtc`, `chtc-interactive-sessions`
