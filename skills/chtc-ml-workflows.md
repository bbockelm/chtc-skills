---
name: chtc-ml-workflows
description: Shaping machine-learning and LLM work for CHTC — splitting training from inference, per-run parallelism, checkpointed training, and batch inference, adapted from CHTC's GPU templates.
sources:
  - chtc-website-source:_uw-research-computing/machine-learning-htc.md
  - templates-GPUs:ml_workflow/
  - templates-GPUs:vllm_batch_inference/
  - templates-GPUs:llm/
  - templates-GPUs:multi_gpu/
  - templates-GPUs:checkpointing/
upstream_reviewed: 2026-09-22
---

# ML and LLM workflows on CHTC

CHTC describes three stages: **develop and test**, **distribute**, **improve**.
The advice in each is about workflow shape, and none of it changes because you
are driving the access point through an MCP server. What changes is that you can
execute the loop yourself instead of describing it — so the discipline matters
more, not less.

## Shape the work before you submit anything

The mistake CHTC's guide is written against is building one script that does
everything and submitting it as one long GPU job. Split it:

```
        preprocess (CPU)
              │
    ┌─────────┼─────────┐        ← many independent training jobs:
  train       train     train      hyperparameters, folds, seeds
    └─────────┼─────────┘
           evaluate (CPU)
              │
      inference (CPU or GPU, one job per shard)
```

Two benefits, and the second is the one people miss:

1. **Reusable pieces.** One general training script driven by arguments becomes
   a hyperparameter sweep by changing a `queue` statement
   (`chtc-many-jobs`).
2. **Right hardware per stage.** Preprocessing and evaluation rarely need a GPU.
   Sending them to CPU slots means they start in minutes rather than hours, and
   leaves the scarce GPUs for the part that needs them.

CHTC has ~150 shared GPUs and thousands of CPU cores. **When the work can use
CPUs, use CPUs.** For inference over a large corpus, a hundred CPU jobs often
finish sooner end to end than a handful of GPU jobs waiting in the queue.

## Develop and test

Write down the environment before building anything: language version,
packages, library and CUDA versions, environment variables. Then build it once
as a container (`chtc-containers`, `chtc-software-recipes`) and reuse it for
every job. CHTC does not consult on code development, but it does expect
containerised environments.

Test with a **subset of the data** — a few hundred images, a hundred prompts.
The goal of the first job is to prove the plumbing: data arrives, the GPU is
visible, the model writes where you expect, outputs come back. Accuracy comes
later.

Instrument the first job:

```bash
nvidia-smi
python3 -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

and read it with `tail_job_output` while it runs. A silent CPU-only fallback is
the most expensive mistake available here.

## Training that survives eviction

Long training runs at CHTC should checkpoint. It is what converts a 5-day job
that cannot run into a sequence of 10-hour jobs that can, and it unlocks the
backfill GPUs (`+is_resumable`) and the OSPool. CHTC's own ML template does
exactly this:

```
container_image = osdf:///chtc/staging/a/alice/containers/torch-cu126.sif

executable = /bin/bash
transfer_executable = false
arguments  = train_with_checkpoint.sh

checkpoint_exit_code      = 85
transfer_checkpoint_files = output/model.pth
+is_resumable             = true
when_to_transfer_output   = ON_EXIT_OR_EVICT

transfer_input_files  = train_with_checkpoint.sh, osdf:///chtc/staging/a/alice/train.zip
transfer_output_files = output

request_gpus            = 1
gpus_minimum_capability = 7.5
gpus_minimum_memory     = 4096
request_cpus            = 2
request_memory          = 12GB
request_disk            = 30GB

+WantGPULab   = true
+GPUJobLength = "short"

queue
```

The training script saves a checkpoint (optimiser state included, not just
weights), exits **85**, and on restart loads the checkpoint and continues. Full
mechanics in `chtc-checkpointing`. A checkpoint that only saves weights and
loses the optimiser and epoch counter will silently restart the schedule and
produce a worse model — verify resume behaviour before scaling.

## Hyperparameter sweeps

This is the natural high-throughput shape and the reason to be on CHTC at all.

```
executable = /bin/bash
transfer_executable = false
arguments  = train.sh --lr $(lr) --batch $(batch) --seed $(seed)

container_image = osdf:///chtc/staging/a/alice/containers/torch-cu126.sif
transfer_input_files  = train.sh, osdf:///chtc/staging/a/alice/train.zip
transfer_output_files = output
transfer_output_remaps = "output = osdf:///chtc/staging/a/alice/sweeps/$(lr)_$(batch)_$(seed)/"

request_gpus = 1
+WantGPULab   = true
+GPUJobLength = "short"

queue lr, batch, seed from sweep.txt
```

Give every run a distinct output path — `$(lr)_$(batch)_$(seed)` or
`$(Process)` — or the runs overwrite each other. Then compare results with
`query_job_archive` over the cluster rather than opening files one at a time.

If the sweep is large, run 5–10 configurations first, confirm the outputs are
distinct and complete, then submit the rest.

## Batch inference and LLMs

CHTC's vLLM template is the model to copy for offline LLM work: one job reads a
JSONL of prompts, writes a JSONL of completions, and transfers it back.

```
executable = run.sh
transfer_input_files  = batch_inference.py, inputs_$(Process).jsonl
transfer_output_files = outputs_$(Process).jsonl

container_image = osdf:///chtc/staging/a/alice/containers/vllm.sif

request_gpus   = 1
require_gpus   = GlobalMemoryMb >= 20000
request_cpus   = 2
request_memory = 16GB
request_disk   = 40GB

+WantGPULab   = true
+GPUJobLength = "short"
stream_output = true

queue 20
```

Points specific to this shape:

- **Shard the input.** Twenty jobs of 5000 prompts each beat one job of 100,000
  prompts: they start sooner, fail smaller, and fit the short tier.
- **Stage the model weights, don't download them per job.** Pulling a 15 GB
  model from Hugging Face in every one of 20 jobs is 300 GB of traffic and a
  rate-limit waiting to happen. Bake weights into the container, or stage them
  once to `/staging` and transfer over `osdf:///`.
- **Size `gpus_minimum_memory` / `require_gpus` to the model.** A 7B model in
  bf16 needs roughly 16 GB plus KV cache; asking for a floor is what keeps the
  job off GPUs where it would OOM.
- **`stream_output = true`** makes progress visible in the output file as it is
  produced, which pairs well with `tail_job_output`.
- **Never put an API key or HF token in the submit file, the script, or the
  container.** Use `store_service_credential` on the access point, or have the
  user pass it another way. Submit files and images are readable and images land
  in shared paths. CHTC's own templates note the W&B API-key leakage risk for
  the same reason.

## Multi-GPU

Only when the code genuinely does data or model parallelism. CHTC's multi-GPU
template pairs `request_gpus = N` with `request_cpus = 4` and a capability floor.
Measure: the queue wait for 2 GPUs frequently exceeds the training time saved.
Try a larger batch on one GPU with gradient accumulation first.

## Improving the workflow

- **Chain the stages with DAGMan** (`submit_dag`) once the shape is settled:
  preprocess, sweep, evaluate becomes one workflow that runs unattended with
  retries. See `chtc-dag-workflows`.
- **Monitor runs** with Weights & Biases or similar — mind the key handling above.
- **Checkpoint to shorten jobs**, which raises the concurrent-job cap on the GPU
  Lab short tier and opens backfill and OSPool capacity.
- **Move what does not need a GPU to CPU jobs.**
- **Read the actual resource usage** after the first runs and trim the requests
  (`chtc-resource-requests`). GPU jobs are often over-requested on host memory,
  which costs queue time for nothing.

## Related skills

`chtc-gpu-jobs`, `chtc-checkpointing`, `chtc-containers`,
`chtc-software-recipes`, `chtc-many-jobs`, `chtc-dag-workflows`,
`chtc-scaling-beyond-chtc`
