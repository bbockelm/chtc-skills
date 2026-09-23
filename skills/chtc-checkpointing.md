---
name: chtc-checkpointing
description: Exit-driven self-checkpointing at CHTC — how exit code 85 works, the submit-file settings, the timeout wrapper pattern, and how to verify resume without a shell.
sources:
  - chtc-website-source:_uw-research-computing/checkpointing.md
  - chtc-website-source:_uw-research-computing/gpu-jobs.md
  - chtc-website-source:_uw-research-computing/scaling-htc.md
upstream_reviewed: 2026-09-22
---

# Checkpointing at CHTC

Checkpointing turns a job that cannot run into one that can. It is the answer to
the 72-hour cap, the 12/24-hour GPU Lab tiers, and eviction from backfill GPUs,
campus pools and the OSPool. It also *increases* throughput: shorter jobs match
more slots, qualify for the short GPU tier, and raise the concurrent-job cap.

CHTC recommends **exit-driven** checkpointing, which is simple enough to retrofit
onto most programs.

## How it works

1. The program runs until it reaches a checkpoint.
2. It writes its state to a file and **exits with code 85**.
3. HTCondor recognises 85, saves the files named in `transfer_checkpoint_files`
   into protected spool storage, and returns the job to the queue.
4. When it next starts — possibly on a different machine — HTCondor restores
   those files into the sandbox.
5. The program finds them, resumes, and eventually exits **0** for real.

Exit 0 means finished. Exit 85 means "save this and run me again". Any other
code is a failure.

## Submit file

```
executable = my_program
arguments  = --input data.h5

checkpoint_exit_code      = 85
transfer_checkpoint_files = state.ckpt, partial_results/

+is_resumable = true          # optional: opens backfill capacity

output = run.out
error  = run.err
log    = run.log

request_cpus   = 1
request_memory = 4GB
request_disk   = 20GB

queue
```

- `transfer_checkpoint_files` lists everything needed to resume — not just the
  model weights but the optimiser state, the iteration counter, the RNG state,
  any partial output. Directories are allowed.
- `+is_resumable = true` tells CHTC the job tolerates interruption, which makes
  it eligible for research-group backfill GPUs. Optional, and only appropriate
  if checkpoints really are frequent (every 4–6 hours or better).
- For jobs that must preserve output across eviction rather than only across
  checkpoints, `when_to_transfer_output = ON_EXIT_OR_EVICT` is the companion
  setting CHTC's ML templates use.

## Making the program checkpoint

The program must do four things. This is CHTC's Fibonacci example reduced to its
structure:

```python
CHECKPOINT = 'state.ckpt'

# 1. Resume if a checkpoint exists, otherwise start fresh
try:
    with open(CHECKPOINT) as f:
        iteration, a, b = (int(line) for line in f)
except IOError:
    iteration, a, b = 0, 0, 1

while iteration < total:
    a, b = b, a + b
    iteration += 1

    # 2. Save periodically
    if iteration % CHECKPOINT_FREQUENCY == 0 and iteration < total:
        with open(CHECKPOINT, 'w') as f:
            f.write(f"{iteration}\n{a}\n{b}\n")
        sys.exit(85)          # 3. Exit 85 after saving

write_result(b)
sys.exit(0)                   # 4. Exit 0 when genuinely done
```

Two failure modes worth guarding against:

- **Writing the checkpoint non-atomically.** If the job is killed mid-write, the
  checkpoint is corrupt and the resume crashes. Write to a temporary name and
  rename — rename is atomic on a local filesystem.
- **Saving too little.** A checkpoint with weights but no optimiser state or
  epoch counter resumes *and silently restarts the learning-rate schedule*.
  Nothing errors; the results are just worse. Verify explicitly.

## When the program cannot exit on its own

Many tools write checkpoints but keep running. Wrap them:

```bash
#!/bin/bash

timeout 4h do_science arg1 arg2
status=$?

if [ $status -eq 124 ]; then    # 124 = timeout fired
    exit 85
fi

exit $status
```

Set the wrapper as the `executable`; no `arguments` line is needed since the
command is inside. The wrapper does **not** create checkpoints — the program
must still be writing them, and the timeout must be long enough for a complete
one to exist.

CHTC's guidance on the timeout: **1–5 hours is the sweet spot, 10 hours the
maximum**. Under an hour and the job spends its life transferring and
restarting; over ten and it stops fitting the window that makes it eligible for
campus pools and the OSPool.

## Is the work a good fit?

The program must be able to save progress and resume from it. Look in its
documentation for "checkpoint", "resume", "restart", or "checkpoint/restart" —
many scientific tools have it and do not advertise it prominently. If it is not
there and the code is not the user's, checkpointing is not available and the
answer is to talk to the facilitators about a runtime extension.

Naturally suited: iterative simulation, MCMC, training loops, anything with an
outer loop over independent chunks.
Not suited: a single monolithic solve with no intermediate state.

## Verifying resume — without a shell

CHTC's documented test is `condor_vacate_job` to evict the job deliberately, and
then inspecting `/var/lib/condor/spool/<last 4 digits of cluster>/<proc>` on the
access point. **Neither is available through this server**: there is no vacate
tool and no filesystem access.

What you can do instead:

1. **Test the resume logic directly**, in an interactive session, which is
   strictly better than testing it by eviction because it is deterministic:

   ```
   interactive_session_start(session = "ckpt-test", cpus = 1, memory_mb = 4096)
   interactive_session_exec(session = "ckpt-test",
     command = "./my_program --input small.h5; echo EXIT=$?; ls -la state.ckpt")
   # expect EXIT=85 and a checkpoint file
   interactive_session_exec(session = "ckpt-test",
     command = "./my_program --input small.h5; echo EXIT=$?")
   # expect it to RESUME, not restart — check the log line it prints
   interactive_session_stop(session = "ckpt-test")
   ```

   Make the program print where it resumed from, so "resumed" is observable and
   not assumed.

2. **Submit one short real job** with a checkpoint frequency small enough that
   it cycles several times, and confirm it did:

   ```
   query_job_epochs(constraint = "ClusterId == N")
   ```

   One record per execution attempt. Several records plus a final `ExitCode` of
   0 is a working checkpoint cycle. `NumJobStarts` in the job ad tells the same
   story more briefly.

3. **Watch it live**: `tail_job_output` shows the resume message each time the
   job restarts.

If the user wants the eviction test specifically, ask them to run
`condor_vacate_job <id>` from the access point.

## Checkpointing and scaling out

Checkpointing is the prerequisite for most of CHTC's extra capacity:

| Capacity | What it wants |
| --- | --- |
| Backfill / research-group GPUs | `+is_resumable = true`, checkpoints every 4–6 h |
| Campus pools (`want_campus_pools`) | Jobs under ~12 h, or checkpointing |
| OSPool (`want_ospool`) | Jobs under ~10 h, or checkpointing |
| Past the 72-hour cap | Checkpointing, or a facilitator conversation |

A job that checkpoints every 4 hours can run anywhere and takes however long it
takes. That is usually a far better outcome than negotiating a longer runtime on
CHTC-only hardware.

## Related skills

`chtc-ml-workflows`, `chtc-gpu-jobs`, `chtc-scaling-beyond-chtc`,
`chtc-interactive-sessions`, `chtc-policies-and-limits`
