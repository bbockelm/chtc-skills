---
name: chtc-software-recipes
description: CHTC's tested container definitions for Python, Conda, R, Julia, PyTorch, CUDA, Matlab and others, adapted as starting definitions to pass to build_container.
sources:
  - recipes:software/
  - chtc-website-source:_uw-research-computing/python-jobs.md
  - chtc-website-source:_uw-research-computing/r-jobs.md
  - chtc-website-source:_uw-research-computing/julia-jobs.md
  - chtc-website-source:_uw-research-computing/matlab-jobs.md
  - chtc-website-source:_uw-research-computing/conda-installation.md
  - chtc-website-source:_uw-research-computing/licensed-software.md
upstream_reviewed: 2026-09-22
---

# CHTC software recipes

CHTC maintains tested Apptainer definition files at
<https://github.com/CHTC/recipes> (`software/`). Start from one of these rather
than writing a definition from scratch — they encode fixes that are not obvious
and that CHTC support will assume you have.

Everything below goes in the `definition` argument of `build_container`; see
`chtc-containers` for the mechanics and for the `chmod 777 /tmp` rule that
applies to every definition that uses `apt`.

Available upstream: AlphaFold, Conda, CUDA, Gurobi, Julia, Mamba, Matlab,
MINEOS, OpenMPI, ORCA, PALM, Python, PyTorch, R, SLEAP, Stata, SUMO.

## Python (pip)

```
Bootstrap: docker
From: python:3.11

%post
    python3 -m pip install --no-cache-dir numpy pandas scikit-learn
```

- Change the `From:` tag to pick the Python version (`python:3.12`,
  `python:3.9-slim`, `python:3.11-alpine`).
- Put **all** packages in one `pip install` so pip can resolve shared
  dependencies together.
- Pin with `package==1.2.3` when reproducibility matters — and it usually does
  for a batch that will run over weeks.
- `python3 -m pip` rather than bare `pip`, so the install lands in the
  interpreter you will actually run.

`verify = "python3 -c 'import numpy, pandas, sklearn; print(numpy.__version__)'"`

## Conda / Mamba

Environment from a YAML file — the reproducible form, and the one to prefer:

```
Bootstrap: docker
From: continuumio/miniconda3:latest

%files
    environment.yaml /environment.yaml

%post
    conda env create -f /environment.yaml
```

The `environment.yaml` must reach the build. `build_container` takes the
definition text, not a file bundle, so inline the environment instead of using
`%files`:

```
Bootstrap: docker
From: continuumio/miniconda3:latest

%post
    cat > /environment.yaml <<'EOF'
    name: analysis
    channels: [conda-forge, bioconda]
    dependencies:
      - python=3.11
      - numpy
      - pysam
    EOF
    conda env create -f /environment.yaml
    echo "conda activate analysis" >> ~/.bashrc

%environment
    export PATH=/opt/conda/envs/analysis/bin:$PATH
```

Setting `PATH` in `%environment` is what makes the environment's interpreter the
default at run time; relying on `conda activate` from a job script is fragile.

Simplest form, one environment in `base`:

```
Bootstrap: docker
From: continuumio/miniconda3:latest

%post
    conda install -y python=3.10 numpy pandas
```

> CHTC used to document `conda pack` / tarball installs unpacked per job. Prefer
> a container: it is faster to transfer, cached by `osdf:///`, and runs outside
> CHTC.

## R

```
Bootstrap: docker
From: rocker/tidyverse:4.3.1

%post
    R -e "install.packages(c('data.table','lme4'), dependencies=TRUE, repos='http://cran.rstudio.com/')"
```

Rocker bases: `rocker/r-ver:<v>` (minimal), `rocker/tidyverse:<v>`,
`rocker/geospatial:<v>`. The R version in the tag matters and should match what
the user developed against.

For a project with an `renv.lock`, CHTC's `renv` recipe restores it inside the
image. It needs `renv.lock`, `activate.R` and `settings.json` copied in; inline
them with heredocs the same way as the Conda YAML above, and **make the
`rocker/r-ver` tag match the R version that generated the lock file**.

`verify = "Rscript -e 'library(data.table); sessionInfo()'"`

## Julia

```
Bootstrap: docker
From: julia:1.10

%post
    export JULIA_DEPOT_PATH="/opt/julia"
    julia -e 'using Pkg; Pkg.add(["DataFrames","CSV"]); Pkg.instantiate(); Pkg.precompile()'

%environment
    export JULIA_DEPOT_PATH=":/opt/julia"
```

Note the leading colon in `%environment` — it appends `/opt/julia` to the depot
path rather than replacing it, which lets the job still have a writable depot in
its scratch directory. `Pkg.precompile()` at build time saves that cost on every
job.

## PyTorch and CUDA

```
Bootstrap: docker
From: nvcr.io/nvidia/pytorch:25.02-py3

%post
    python3 -m pip install --no-cache-dir pandas transformers
```

Or from a CUDA base:

```
Bootstrap: docker
From: nvidia/cuda:12.6.3-runtime-ubuntu22.04

%post
    chmod 777 /tmp
    apt-get update -y
    apt-get install -y python3 python3-pip
    python3 -m pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cu126
```

The NGC images (`nvcr.io/nvidia/pytorch`, `.../tensorflow`) are large but save a
great deal of dependency work. `-runtime` CUDA tags are smaller than `-devel`;
use `-devel` only if the build compiles CUDA code.

**Get the GPU-enabled build of the framework.** A CPU-only `pip install torch`
in a GPU job runs, slowly, on the CPU and nobody notices for days. Make `verify`
catch it — though note it runs on a build machine, which may not have a GPU, so
check the *build flavour*, not device availability:

```
verify = "python3 -c 'import torch; print(torch.__version__); assert torch.version.cuda'"
```

See `chtc-gpu-jobs` for choosing CUDA capability, and `chtc-ml-workflows` for
workflow shape.

## Matlab (licensed)

CHTC's Matlab recipe installs from `mathworks/matlab-deps:<release>` with
`mpm`, and **only the toolboxes CHTC is licensed for may be installed** — the
list is `software/Matlab/chtc_licensed_toolboxes.txt` in the recipes repo.
`MATLAB_RELEASE` must match the `From:` tag.

Compiled Matlab (`mcc`) plus the free MATLAB Runtime is usually the better
answer for a large batch: no license checkout per job, so no license-server
bottleneck. CHTC's `Matlab/mcc-compiler` recipe covers it.

Other licensed software (Stata, Gurobi, ORCA, Abaqus) has its own terms —
several require the user's own license file, which should be treated as a
credential and never baked into a shared image. Check with the facilitators
before building something licensed into a container that lands in a shared
staging path.

## Domain software

AlphaFold, SLEAP, SUMO, PALM, MINEOS, ORCA, OpenMPI and Gurobi all have
definitions upstream. If a user names one of these, read the upstream recipe
rather than improvising — several carry non-obvious build flags. The SUMO
definition is also the worked "advanced example" in CHTC's build guide, and is
the best template for compile-from-source software:

```
Bootstrap: docker
From: ubuntu:22.04

%post
    chmod 777 /tmp
    apt-get update -y
    apt-get install -y git cmake g++ python3-dev swig libeigen3-dev   # etc.

    git clone --recursive https://github.com/eclipse/sumo
    export SUMO_HOME=/sumo
    mkdir sumo/build/cmake-build && cd sumo/build/cmake-build
    cmake ../.. && make

%environment
    export SUMO_HOME=/sumo
    export PATH=/sumo/bin:$PATH
```

Pattern worth copying: build in `%post`, then re-export the same variables in
`%environment`, because `%post` variables do not survive into the run.

## Checking the recipes for updates

These are summaries. The upstream repository is the source of truth and moves;
before relying on a version tag here, check
<https://github.com/CHTC/recipes/tree/main/software>. See this repository's
`AGENTS.md` for how the summaries are kept current.

## Related skills

`chtc-containers`, `chtc-gpu-jobs`, `chtc-ml-workflows`, `chtc-submit-basics`
