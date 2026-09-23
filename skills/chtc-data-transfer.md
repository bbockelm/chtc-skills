---
name: chtc-data-transfer
description: Choosing how data reaches and leaves a CHTC job — which transfer protocol for which file size, the osdf/pelican plugins, output remaps, and the MCP upload and retrieval tools.
sources:
  - chtc-website-source:_uw-research-computing/htc-job-file-transfer.md
  - chtc-website-source:_uw-research-computing/file-avail-largedata.md
  - chtc-website-source:_uw-research-computing/transfer-files-computer.md
upstream_reviewed: 2026-09-22
---

# Getting data into and out of CHTC jobs

CHTC's model is **transfer, not share**. Execute nodes do not mount the user's
home directory; every file a job needs is copied into a scratch sandbox before
it starts, and every file it produces is copied out afterwards. Getting the
protocol right for the file size is the difference between a batch that flies
and one that overloads the filesystem — and CHTC treats misuse of the large-data
paths as a policy violation, not a performance tip.

Through this interface you have one extra reason to prefer transfer: there is no
shell on the access point, so "copy it to your home directory first" is not a
step you can take. Lean into the automated paths. They are the ones CHTC wants
used anyway.

## Choose by size and location

Per **individual** file, not per batch:

| Size | Where it lives | Submit-file syntax |
| --- | --- | --- |
| 0 – 1 GB | `/home` | `transfer_input_files = input.txt` |
| 1 – 30 GB | `/staging` | `transfer_input_files = osdf:///chtc/staging/<u>/<netid>/input.dat` |
| 30 – 100 GB | `/staging` | `transfer_input_files = file:///staging/<u>/<netid>/input.dat` |
| 1 – 100 GB | `/staging/groups` | `transfer_input_files = file:///staging/groups/<group>/input.dat` |
| any | a web server | `transfer_input_files = https://example.org/input.dat` |
| any | ResearchDrive | `transfer_input_files = pelican://chtc.wisc.edu/researchdrive/<PI>/CHTC/input.dat` |
| 100 GB+ | — | Ask the facilitators |

`<u>` is the first letter of the NetID: NetID `alice` → `/staging/a/alice` →
`osdf:///chtc/staging/a/alice/...`.

Multiple protocols mix freely in one list:

```
transfer_input_files = params.json, osdf:///chtc/staging/a/alice/ref.tar.gz, https://example.org/model.bin
```

### Two requirements you must remember

**`file:///` needs the staging filesystem mounted**, so the job must require it:

```
requirements = (HasCHTCStaging == true)
```

Omitting this is a classic cause of a job that holds on transfer. `osdf:///`
does *not* need it — that is part of why `osdf:///` is preferred, and it is
what lets the job run outside CHTC (see `chtc-scaling-beyond-chtc`).

**`osdf:///` caches.** The Pelican-backed plugin caches objects by path to make
repeated transfers fast. Change a file's contents without changing its name and
jobs may get the old version, or a mixture. **Always version the path or the
filename** — `ref-v3.tar.gz`, or a dated directory — rather than overwriting in
place. `file:///` and plain `/home` transfers do not cache.

Only personal `/staging` directories are reachable over `osdf:///`;
`/staging/groups` must use `file:///`.

### Unpacking during transfer

Append `?pack=auto` to an `osdf://` or `pelican://` path and the plugin unpacks
the archive as it lands:

```
transfer_input_files = osdf:///chtc/staging/a/alice/dataset.tar.gz?pack=auto
```

This saves requesting disk for both the tarball and its contents, and removes an
unpack step from the job script. Not available for `file:///` or ordinary
transfers, and not recommended above ~30 GB.

## Getting files in through the MCP server

| Situation | Tool |
| --- | --- |
| The executable, scripts, small config (< ~100 KB total) | `upload_job_input` with `files: [{filename, data, is_executable}]` |
| A large local file or directory | `create_input_upload_url`, then shell out: `tar cf - data/ \| curl -T - '<url>'` |
| Data reachable by URL | Put the URL in `transfer_input_files`; don't route it through you |
| Data already in `/staging` or ResearchDrive | Put the `osdf:///` or `pelican://` path in `transfer_input_files` |

`create_input_upload_url` matters more than it looks: it returns a credential-free,
short-lived URL that the bytes go to **directly**, so a 5 GB input never passes
through the conversation. Input spools per proc, so a bare cluster id returns
one URL per proc and each takes its own tar.

Never read a large file in order to upload it. If you find yourself about to,
reach for `create_input_upload_url` or a URL instead.

## Getting files out

### The default, and its trap

HTCondor returns **new or changed files in the job's top-level scratch
directory**. Files the job wrote into a subdirectory are *not* returned and are
destroyed with the sandbox. This surprises nearly every new user.

Three ways out, in order of preference:

```
# 1. Name what you want, including subdirectory paths
transfer_output_files = summary.csv, plots/figure1.png

# 2. Tar it in the job script before exiting
tar czf results.tar.gz results/
# with: transfer_output_files = results.tar.gz

# 3. Write to the top level in the first place
```

### Sending output somewhere other than /home

Large outputs should not land in `/home`. Remap them:

```
transfer_output_files  = big.dat, summary.csv
transfer_output_remaps = "big.dat = osdf:///chtc/staging/a/alice/big.dat"
# summary.csv, unremapped, comes back to the submit directory
```

Or send everything to one destination:

```
output_destination = osdf:///chtc/staging/a/alice/run17/
```

Do not use `output_destination` and `transfer_output_remaps` together.
`transfer_output_remaps` takes a single pair of quotes around the whole
semicolon-separated list — a very common syntax error.

### Reading output back through the server

- `get_job_stdout(job_id)` / `get_job_stderr(job_id)` — after the job finishes.
- `get_job_output(job_id)` — every file in the returned sandbox; each file is
  truncated above 100 KB.
- `tail_job_output(job_id)` — while it is **running**, read from the execute
  node. Pass back the offsets it returns to get only what is new; poll no more
  often than every 5 seconds.

`get_job_*` read transferred files and are the wrong tools mid-run;
`tail_job_output` is the reverse. For big results, prefer sending them to
`/staging` or ResearchDrive and telling the user where they are, over pulling
tens of megabytes through the conversation.

## Design rules worth following

1. **Few, large files beat many, small ones** — everywhere, but especially on
   `/staging`, whose filesystem is tuned for exactly that and whose item quota
   (1000 by default) enforces it. Ideally one input file per job.
2. **Never transfer a directory from `/staging` recursively.** Tar it once and
   transfer the tarball.
3. **Compress before transferring**, then request disk for both the archive and
   its expansion — or use `?pack=auto` and skip the doubled footprint.
4. **Reuse beats re-transfer.** A reference dataset used by 5000 jobs belongs in
   `/staging` behind an `osdf:///` URL, where the cache serves it, not in
   `/home` where each job pulls a fresh copy.
5. **Version paths you intend to change.** See the caching note above.

## Related skills

`chtc-staging-large-data`, `chtc-researchdrive-uwdf`, `chtc-submit-basics`,
`chtc-scaling-beyond-chtc`, `chtc-containers`
