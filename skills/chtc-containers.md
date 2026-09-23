---
name: chtc-containers
description: Building and using Apptainer containers at CHTC through the build_container tool instead of an interactive build job, plus the definition-file conventions CHTC's own recipes follow.
sources:
  - chtc-website-source:_uw-research-computing/apptainer-htc.md
  - chtc-website-source:_uw-research-computing/apptainer-build.md
  - chtc-website-source:_uw-research-computing/htc-docker-to-apptainer.md
  - chtc-website-source:_uw-research-computing/docker-jobs.md
  - chtc-website-source:_uw-research-computing/os-request-htc.md
  - chtc-website-source:_uw-research-computing/htc-known-issues.md
  - recipes:software/
upstream_reviewed: 2026-09-22
---

# Containers at CHTC

A container is the answer to almost every software question at CHTC. It carries
the operating system, libraries and program with the job, so the job stops
caring which execute node it lands on — which means it matches far more slots,
runs on campus pools and the OSPool, and behaves identically everywhere. CHTC
recommends Apptainer specifically; the OSPool supports it best.

CHTC's published procedure is: write a `.def` file, start an interactive build
job (`condor_submit -i` with `+IsBuildJob = true`), run `apptainer build`,
`apptainer shell` to test it, then `mv` the `.sif` into `/staging`.

**Through this server that entire procedure is one tool call.**

## Building: `build_container`

```
build_container(
  name        = "analysis-py311.sif",
  definition  = "<the .def file text, verbatim>",
  verify      = "python3 -c 'import numpy, pandas; print(numpy.__version__)'",
  cpus        = 8,
  memory_mb   = 16384,
  disk_mb     = 30720
)
```

What the tool supplies for you, and you should therefore **not** write yourself:
the submit attributes that reach build-capable slots (`+IsBuildJob`), the
resource requests, image-cache handling, and the transfer of the finished `.sif`
to its destination. There is no interactive session, no `apptainer build`
command, and no `mv` to `/staging`.

It returns **as soon as the job is submitted** — a real image takes minutes to
tens of minutes. Then:

```
watch_jobs(constraint = "ClusterId == <returned id>", event = "done")
check_watches(wait_seconds = 300)
get_job_stdout(job_id)     # the build log
get_job_stderr(job_id)
```

### Always pass `verify`

`verify` runs a shell command inside the freshly built image; if it exits
non-zero **the image is not published**. This matters because the destination is
a shared path other people may pick up from, and an image that cannot run the
thing it was built for is worse than no image. It also replaces the
`apptainer shell -e` manual test from the CHTC guide, which you cannot do.

Make it exercise the actual software, not just its presence:

```
verify = "python3 -c 'import torch; assert torch.__version__.startswith(\"2.\")'"
verify = "Rscript -e 'library(tidyverse); sessionInfo()'"
verify = "my-program --version && my-program --selftest"
```

A failed build or failed verify publishes nothing but still returns its logs, so
it stays diagnosable. Read `get_job_stdout` and fix the definition.

### Destination

Omit `destination` and the site's configured staging base applies, with `name`
appended — typically per-user, resolved from your authenticated identity. Set it
explicitly only when you need a specific location:

```
destination = "osdf:///chtc/staging/a/alice/containers/analysis-py311.sif"
```

**The destination directory must already exist.** Object stores do not create
one on write and the job fails if it is missing.

### Sizing the build

`disk_mb` must hold the unpacked root filesystem *plus* the finished image *plus*
the layer cache — several times the size of the image you expect. CHTC's own
interactive-build template asks for 8 CPUs, 16 GB memory and 30 GB disk, which
is a reasonable default. **A build that dies abruptly with no error message is
almost always out of disk.** Increase `disk_mb` first.

### Dockerfiles

If a Dockerfile is what exists, pass it as `dockerfile` instead of `definition`
and Apptainer builds it directly via its `buildkit:` bootstrap. Never both. This
needs a container builder on the build machine, which not every site has; if
none is found the job fails saying so, and the fallback is to translate the
Dockerfile into a `.def` (the mapping is close: `FROM` → `Bootstrap: docker` /
`From:`, `RUN` → `%post`, `COPY` → `%files`, `ENV` → `%environment`).

### If `build_container` is not available

Some deployments do not expose it. Fall back to an interactive session, which is
CHTC's documented procedure with the shell coming from
`interactive_session_exec`:

```
interactive_session_start(session="build", cpus=8, memory_mb=16384, disk_mb=30720,
                          submit_lines="+IsBuildJob = True")
interactive_session_exec(session="build",
  command="cat > image.def <<'EOF'\n<def text>\nEOF\napptainer build image.sif image.def",
  timeout_seconds=1800)
interactive_session_exec(session="build", command="apptainer exec image.sif python3 -c 'import numpy'")
interactive_session_stop(session="build")
```

Note the session is capped at 4 hours like any build job, and you must still get
the `.sif` to a durable location — `mv` it to `/staging` inside the session.

## Writing the definition file

```
Bootstrap: docker
From: python:3.11

%files
    requirements.txt /opt/requirements.txt

%post
    chmod 777 /tmp
    apt-get update -y
    apt-get install -y --no-install-recommends git build-essential
    python3 -m pip install --no-cache-dir -r /opt/requirements.txt

%environment
    export PATH="/opt/myprogram/bin:$PATH"

%labels
    Author  Bucky Badger
    Purpose RNA-seq quantification
```

Section reference:

| Section | Purpose |
| --- | --- |
| Header (`Bootstrap:` / `From:`) | The base image to start from |
| `%files` | Copy files from the build host into the image |
| `%post` | Everything that installs or compiles |
| `%environment` | Variables set when the container *runs* (like a `.bashrc`) |
| `%labels` / `%help` | Metadata and usage text |

`%runscript` is **ignored** when the container runs on CHTC's HTC system — the
job's `executable` is what runs. Don't rely on it.

### Rules that come from CHTC experience, not from Apptainer

1. **`chmod 777 /tmp` as the first line of `%post`.** Without it, `apt` fails
   with `Couldn't create temporary file /tmp/apt.conf...`. This is a CHTC-build
   specific workaround — do not carry it into definitions built elsewhere.
2. **Everything non-interactive.** Use `-y` on `apt`/`dnf`. A prompt the build
   cannot answer becomes a timeout and a failed build.
3. **Variables set in `%post` do not survive into the run.** Put anything the
   job needs in `%environment`.
4. **A container's filesystem is read-only at run time.** Only the mounted
   working directory is writable, which is why job scripts need
   `export HOME=$PWD` (see below).
5. **Builds are all-or-nothing.** A failure leaves no `.sif` and the next attempt
   starts from scratch. Getting a definition right on the first try is rare —
   this is why `verify` and the build log matter.
6. **Multi-stage is possible**: build one image, then `Bootstrap: localimage` /
   `From: first.sif` in a second definition.

### Base image choices

- `Bootstrap: docker` / `From: <registry path>` covers Docker Hub, NVIDIA NGC
  (`nvcr.io/nvidia/...`), Quay, and the rest.
- Bare distro images from Docker Hub lack common tools (`vim`, `wget`, `git`).
  OSG maintains curated base Linux containers with a fuller set.
- Pick a base that already carries most of the dependencies. It is cheaper and
  far more reliable than building them.

CHTC publishes tested definition files for Python, Conda, R, Julia, Matlab,
PyTorch, CUDA and more — see `chtc-software-recipes` before writing one from
scratch.

## Using a container in a job

```
container_image = osdf:///chtc/staging/a/alice/containers/analysis-py311.sif

executable      = run_analysis.sh
transfer_input_files = params.json

log    = job_$(Cluster)_$(Process).log
output = job_$(Cluster)_$(Process).out
error  = job_$(Cluster)_$(Process).err

request_cpus   = 1
request_memory = 4GB
request_disk   = 10GB       # must include room for the .sif itself

queue
```

Which URL form to use for `container_image`:

| Form | When |
| --- | --- |
| `osdf:///chtc/staging/...` | **Default.** Required if the job may run on campus pools or the OSPool |
| `file:///staging/...` | CHTC-only jobs; also needs `requirements = (HasCHTCStaging == true)` |
| `my-container.sif` (in `/home`) | Small images only; not recommended |
| `docker://user/repo:tag` | Pulled and converted at run time — convenient, but every job pays the pull |

**`request_disk` must include the image.** A 6 GB `.sif` plus 2 GB of inputs
needs well over 8 GB of disk.

From the job's point of view nothing else changes: HTCondor claims a slot, pulls
or transfers the image, transfers inputs, runs the `executable` inside the
container as the submitting user with the working directory mounted, and
transfers outputs back. You never write an `apptainer` command in the job
script.

### Docker universe

CHTC supports `universe = docker` with `docker_image = ...`, and older templates
(including parts of `templates-GPUs`) use it. Prefer `container_image` with an
Apptainer image: it runs on more machines, works outside CHTC, and avoids the
docker-universe quirk where output files from an *interactive* docker job are
not returned. Some CHTC GPU servers (the `gzk` machines) have no Docker at all.

## Gotchas that produce held or failing jobs

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Cannot pull image user/repo:tag` | Image built on an Apple Silicon Mac | Rebuild with `docker build --platform linux/amd64 .`, or build with `build_container` on the pool |
| Error mentioning `/home/<netid>` or `/` | Program writing to a non-writable path | `export HOME=$PWD` at the top of the job script |
| `apt` fails in `%post` | `/tmp` permissions | `chmod 777 /tmp` first in `%post` |
| Build killed with no message | Out of disk | Raise `disk_mb` |
| `Can't open master pty Bad file descriptor` | Interactive Apptainer on an old EL7 node | `requirements = (OpSysMajorVer > 7)` |
| Held on transfer of the image | Wrong URL scheme, or `file:///` without `HasCHTCStaging` | See the URL table above |

## Related skills

`chtc-software-recipes`, `chtc-data-transfer`, `chtc-gpu-jobs`,
`chtc-interactive-sessions`, `chtc-troubleshooting`
