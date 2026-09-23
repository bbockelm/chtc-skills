---
name: chtc-interactive-sessions
description: Getting a shell on a CHTC execute node through interactive sessions instead of condor_submit -i — when to use one, build jobs, GPU sessions, and the rules that keep them from wasting slots.
sources:
  - chtc-website-source:_uw-research-computing/inter-submit.md
  - chtc-website-source:_uw-research-computing/htc-interactive-gpu-jobs.md
  - chtc-website-source:_uw-research-computing/htc-monitor-jobs.md
  - chtc-website-source:_uw-research-computing/user-expectations.md
upstream_reviewed: 2026-09-22
---

# Interactive work on CHTC

CHTC's rule is that computation happens in jobs, never on the access point.
When you need a shell — to compile something, poke at a dataset, reproduce a
failure by hand — that shell must come from a job. CHTC's documented way is
`condor_submit -i`; here it is an interactive session.

```
interactive_session_start(session = "build-env", cpus = 4, memory_mb = 8192,
                          disk_mb = 20480)
interactive_session_exec(session = "build-env", command = "…")
interactive_session_stop(session = "build-env")
```

The session is a job. It queues like one, holds a real slot, and runs on an
execute node — so everything you run in it is running where CHTC wants it to
run.

## When a session is the right tool

Use one when **several steps need the same machine and the same files**:
configure-then-make-then-test, exploring a dataset before writing the batch,
reproducing a job failure by hand, checking what a container actually contains.

Use a **batch job** instead when the work is one command that produces a result
— that is cheaper for everyone and does not hold a slot while you think.

Use **`exec_in_job(job_id, command)`** when the job you want to look at is
already running. It connects, runs one command, disconnects. This is the tool
for inspecting a running batch job without disturbing it, and it replaces
`condor_ssh_to_job` for quick checks — which is exactly what CHTC says that
command is for.

## Three rules

1. **The session name is the only handle.** Pass it on every call.
   `interactive_session_list` finds sessions from earlier conversations, which
   matters because a forgotten session keeps holding its slot.
2. **A session holds its CPUs and memory until stopped**, and is reclaimed after
   ~30 minutes with no calls (each call resets the countdown). **Stop sessions
   you are done with.** CHTC's agent guidance names lingering background
   processes as a specific problem; an unstopped session is one.
3. **Each `exec` is a fresh shell.** The working directory resets to the job's
   scratch directory and environment changes do not carry over. Chain dependent
   steps in one command with `&&`. Files written into the sandbox **do**
   persist for the session's life.

```
# Wrong — the cd is lost
interactive_session_exec(session="s", command="cd src")
interactive_session_exec(session="s", command="make")

# Right
interactive_session_exec(session="s", command="cd src && make -j4")
```

## Getting code into a session

The command runs on the execute machine, not the access point, so there is no
`upload_job_input` for a session. Write files with a heredoc, or fetch them:

```
interactive_session_exec(session = "s", command = """
cat > run.py <<'EOF'
import numpy as np
print(np.__version__)
EOF
python3 run.py
""")
```

```
interactive_session_exec(session = "s",
  command = "curl -sSLO https://example.org/data.tar.gz && tar xzf data.tar.gz")
```

For staged data, pass the transfer in at start time with `submit_lines`.

## Sessions with a container

Run inside the same environment the batch jobs will use — this is the point of
an interactive session for debugging:

```
interactive_session_start(
  session      = "debug",
  cpus         = 2,
  memory_mb    = 8192,
  disk_mb      = 20480,
  submit_lines = "container_image = osdf:///chtc/staging/a/alice/env.sif"
)
```

`submit_lines` takes extra submit commands, one per line, for anything the named
arguments do not cover: `container_image`, `+ProjectName`, `transfer_input_files`.
The commands that make the job a session — `executable`, `batch_name`,
`universe`, the transfer settings and `queue` — are refused, because redefining
them produces a session that submits and then cannot be attached to.

## Build jobs

CHTC designates specific machines for compiling, reached with
`+IsBuildJob = true`. They have compilers and Matlab tooling but no GPUs or
extreme memory. Sessions there are capped at **4 hours**.

```
interactive_session_start(session = "build", cpus = 8, memory_mb = 16384,
                          disk_mb = 30720, submit_lines = "+IsBuildJob = True")
```

Use this for compiling software from source. **For building a container, use
`build_container` instead** — it does the whole build-test-publish cycle in one
call and does not need a session at all (see `chtc-containers`). Reach for a
build session only if `build_container` is unavailable or you genuinely need to
iterate on a compile by hand.

## GPU sessions

```
interactive_session_start(session = "gpu-debug", gpus = 1, cpus = 2,
                          memory_mb = 16384, disk_mb = 20480,
                          submit_lines = "+WantGPULab = true")
```

CHTC reserves a small number of GPU Lab slots for interactive use — a handful of
RTX 2080 Ti and one A100 — and **caps interactive GPU jobs at 4 hours**.

Two policy points that matter:

- **`condor_ssh_to_job` is unavailable on CHTC's shared GPU machines** as of
  April 2026, because people were parking long `sleep` jobs on GPUs and
  attaching occasionally. `exec_in_job` therefore will not attach to a batch GPU
  job there. Groups with owned GPUs keep the ability.
- **Do not reproduce that pattern.** A GPU session that sits idle while you think
  is exactly the behaviour the policy exists to stop. Start it when you have the
  commands ready, run them, stop it.

To watch a running GPU batch job instead, use `tail_job_output`.

## Requirements

`requirements` narrows which machines the session may run on:

```
interactive_session_start(session = "s", requirements = 'TARGET.HasCHTCStaging == true')
```

It is ANDed with any site-wide requirement the operator sets. Narrow too far and
the session queues with nothing to match it — if a session does not start,
loosen this first, then reduce the resource requests.

## A worked debugging loop

A batch job fails and the error is unclear:

```
1. query_job_archive(ClusterId == N)         → exit code, hold reason
2. get_job_stderr(job_id)                    → the message
3. interactive_session_start with the SAME container_image and resources
4. interactive_session_exec: recreate the inputs, run the command by hand
5. iterate until it works
6. interactive_session_stop
7. fix the submit file, resubmit ONE job, watch_jobs(event="succeeded")
8. scale back up
```

Step 3's "same container and resources" is what makes the session's answer
trustworthy. A session with different software proves nothing about the job.

## Related skills

`chtc-troubleshooting`, `chtc-containers`, `chtc-gpu-jobs`, `chtc-monitoring`
