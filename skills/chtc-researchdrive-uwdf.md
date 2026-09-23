---
name: chtc-researchdrive-uwdf
description: Transferring files directly between UW ResearchDrive and CHTC jobs with the pelican:// plugin, skipping the copy into CHTC storage.
sources:
  - chtc-website-source:_uw-research-computing/htc-uwdf-researchdrive.md
  - chtc-website-source:_uw-research-computing/transfer-data-researchdrive.md
upstream_reviewed: 2026-09-22
---

# ResearchDrive as job storage (UWDF / pelican://)

UW–Madison's [ResearchDrive](https://it.wisc.edu/services/researchdrive/) can be
read from and written to **directly by jobs**, through the UW Data Federation
and the Pelican Platform — the same technology behind `osdf:///`. ResearchDrive
acts as the staging location, and the copy into `/staging` disappears entirely.

This fits the way you have to work here particularly well. Staging data into
`/staging` needs a shell on the transfer server; a `pelican://` path in the
submit file needs nothing but the submit file.

## When it is the right answer

Good fit when the user:

- already has access to their PI's ResearchDrive,
- has the data there already,
- works with large datasets, or reuses the same data across many jobs.

Not available when:

- the ResearchDrive is a **restricted** share — those are ineligible,
- the data is outside the `CHTC` subdirectory (see below),
- the PI has not enabled the integration.

ResearchDrive's free tier caps at 25 TB per share; PIs can pay for more and are
billed only on the overage.

## Enabling it

Only a PI can enable it, through CHTC's request form, and it takes roughly 3–5
business days for CHTC and the ResearchDrive team to coordinate. If the user's
`pelican://` transfers fail with a not-found or permission error, confirm the
integration exists before debugging anything else — this is the usual cause.

## The CHTC subdirectory

**CHTC can only reach a directory literally named `CHTC` at the top level of the
PI's ResearchDrive.** Nothing outside it is visible, including symlinks that
point outside it. This is deliberate containment: many jobs can write into a
ResearchDrive, so the blast radius of a bug or a wrong path is bounded.

Consequence for you: if the data the user names is elsewhere in the share, the
path will not work and no amount of URL fiddling will fix it. They have to move
or copy it into `CHTC/` first.

## Paths

```
pelican://chtc.wisc.edu/researchdrive/<PI NetID>/CHTC/<path>
```

Input:

```
transfer_input_files = pelican://chtc.wisc.edu/researchdrive/bbadger/CHTC/inputs/sample_042.bam
```

Output, selectively:

```
transfer_output_files  = calls.vcf, summary.csv
transfer_output_remaps = "calls.vcf = pelican://chtc.wisc.edu/researchdrive/bbadger/CHTC/results/calls_$(Process).vcf"
# summary.csv is unremapped and comes back to the submit directory
```

Output, everything:

```
output_destination = pelican://chtc.wisc.edu/researchdrive/bbadger/CHTC/results/run17/
```

Do not combine `output_destination` with `transfer_output_remaps`.

Because the prefix is long and repeated, define it once:

```
RD = pelican://chtc.wisc.edu/researchdrive/bbadger/CHTC

transfer_input_files   = $(RD)/inputs/$(sample).bam
transfer_output_files  = calls.vcf
transfer_output_remaps = "calls.vcf = $(RD)/results/$(sample).vcf"

queue sample from samples.txt
```

That is also the pattern that makes a thousand-job batch readable.

## The caching rule applies here too

Pelican caches objects by path. A file whose contents change without its path
changing may be delivered stale, or inconsistently across a batch. **Version the
filename or the directory** — `reference-v4/`, `inputs-2026-09/` — for anything
that is regenerated. If the user reports results that do not match what they
believe is in ResearchDrive, this is the first thing to check.

## Choosing between ResearchDrive, /staging and S3

| | Use when |
| --- | --- |
| `pelican://` ResearchDrive | The data already lives there; the PI has the integration; you have no shell to stage with |
| `osdf:///` from `/staging` | Data is CHTC-local and reused heavily; container images; 1–30 GB files |
| `file:///` from `/staging` | 30–100 GB files, CHTC-only jobs, or `/staging/groups` |
| CHTC S3 | Large data that must be reachable outside CHTC and does not fit the above |

ResearchDrive removes a copy step, which is worth real time on large datasets.
`/staging` plus `osdf:///` is better for something read by thousands of jobs,
because it sits behind the OSDF caches.

## Related skills

`chtc-data-transfer`, `chtc-staging-large-data`, `chtc-scaling-beyond-chtc`
