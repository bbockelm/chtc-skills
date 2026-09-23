---
name: chtc-staging-large-data
description: Using CHTC's /staging filesystem for files over ~1 GB — what it is for, its policies, and how to get data in and out of it without a shell on the access point.
sources:
  - chtc-website-source:_uw-research-computing/file-avail-largedata.md
  - chtc-website-source:_uw-research-computing/htc-job-file-transfer.md
  - chtc-website-source:_uw-research-computing/file-avail-s3.md
upstream_reviewed: 2026-09-22
---

# /staging: large data at CHTC

`/staging` is a separate filesystem from `/home`, tuned for **a small number of
large files**. It is not extra home-directory space, and CHTC enforces that
distinction: the guide's own words are that violating the staging policies gets
staging access or the account revoked until corrective measures are taken.

| | `/home` | `/staging` |
| --- | --- | --- |
| Purpose | Submit files, scripts, small inputs and outputs | Stages large files and container images into jobs |
| Good for | Many small files (< 1 GB) | Few large files (> 1 GB) |
| Default quota | 40 GB, no item limit | 100 GB, **1000 items** |
| Jobs submitted from here? | Yes | **Never** |

Personal directory: `/staging/<first letter of NetID>/<NetID>` — NetID `alice`
→ `/staging/a/alice`. A blank `get_quotas` on the access point means the user
does not have one yet; CHTC creates them on request.

## What belongs here

Only input and output files that are **individually** too large for ordinary
HTCondor file transfer — roughly, individual files over 1 GB. That includes:

- Reference datasets and genome indices reused across many jobs
- Apptainer `.sif` container images (see `chtc-containers`)
- Large per-job inputs and large per-job outputs
- Model weights

What does **not** belong here: thousands of small files, a source tree, a conda
environment as loose files, or anything that is really a home directory in
disguise. The 1000-item quota is the guardrail; if a user is bumping into it,
the answer is almost always to tar things up, not to ask for more items.

## Using staged data in a job

```
# Submitted from /home, never from /staging.

executable            = run_analysis.sh
transfer_input_files  = osdf:///chtc/staging/a/alice/reference-v4.tar.gz?pack=auto, params.json

# Only needed if any path uses file:/// — osdf:/// does not require it
# requirements        = (HasCHTCStaging == true)

request_cpus   = 1
request_memory = 8GB
request_disk   = 60GB      # must cover staged inputs + outputs + expansion

transfer_output_files  = results.tar.gz
transfer_output_remaps = "results.tar.gz = osdf:///chtc/staging/a/alice/out/results_$(Process).tar.gz"

queue
```

Three things this example gets right and that are easy to get wrong:

1. **`request_disk` covers the staged data.** Files copied in from `/staging`
   occupy the job's sandbox. Size the request for inputs + outputs + any
   uncompressed expansion, or the job is killed mid-run for disk.
2. **`osdf:///` for 1–30 GB, `file:///` for 30–100 GB.** `file:///` additionally
   requires `requirements = (HasCHTCStaging == true)`, and confines the job to
   CHTC-owned machines. `/staging/groups` is only reachable over `file:///`.
3. **Outputs go back to `/staging`, not to `/home`.** A 40 GB result written
   into a 40 GB home quota is a bad afternoon.

Remember the caching rule from `chtc-data-transfer`: `osdf:///` caches by path.
If a staged file's contents change, change its name or its directory. This is
the single most likely way to get silently wrong results.

## Getting data into /staging without a shell

You cannot `scp` from here, and CHTC requires that uploads to `/staging` go
through the dedicated transfer server `transfer.chtc.wisc.edu` and **not**
through an access point. Your options, in order:

1. **Have a job write it.** If the data is generated or fetched rather than
   local — downloaded from a public archive, produced by an earlier stage — run
   a job that fetches or produces it and remaps its output into `/staging`.
   This needs no shell at all and is usually the right answer.

   ```
   executable             = fetch.sh          # curls the archive, verifies checksum
   transfer_output_files  = dataset.tar.gz
   transfer_output_remaps = "dataset.tar.gz = osdf:///chtc/staging/a/alice/dataset-2026-09.tar.gz"
   request_disk           = 120GB
   ```

2. **Hand the user the command.** For data that only exists on their laptop:

   ```
   tar czf dataset.tar.gz dataset/
   scp dataset.tar.gz alice@transfer.chtc.wisc.edu:/staging/a/alice/
   ```

   Be explicit that it is the transfer server, not `ap2001`.

3. **`create_input_upload_url`** puts bytes into a *job's input spool*, not into
   `/staging`. It is the right tool for per-job inputs; it is not a `/staging`
   upload path. Combine it with option 1 if the data must then be persisted.

Getting data out is the mirror image: have a job remap its output into
`/staging`, and the user retrieves it from the transfer server.

## Reduce file counts before you stage

`/staging` is optimised for few large files and quota-limited to 1000 items.
Combine and compress:

```
tar czf sample_batch_03.tar.gz sample_batch_03/
```

Prefer one archive per job over a directory of loose files per job, and never
transfer a `/staging` directory recursively into a job — that generates one
transfer per file and is exactly the pattern the policy is written against.

## Clean up

CHTC expects data to be removed from `/staging` as soon as the jobs needing it
have finished, even if it will be needed again later — copy it back then. None
of it is backed up, and staff may remove data at any time to preserve
performance. When you finish a campaign for a user, say plainly what is left in
`/staging` and that it should be cleared.

## S3 buckets

CHTC also offers S3 buckets for large data that must be reachable from **outside**
CHTC — principally for jobs running on the OSPool. Intended for individual
inputs over 100 MB and individual outputs over 3–4 GB, with keys managed by CHTC
so no credentials appear in the submit file. Access is granted on request after
facilitator review.

In practice, `osdf:///` from `/staging` already reaches OSPool capacity, so S3
is the answer for a narrower set of cases. Point the user at the facilitators
rather than assuming they have a bucket.

## Related skills

`chtc-data-transfer`, `chtc-researchdrive-uwdf`, `chtc-containers`,
`chtc-policies-and-limits`
