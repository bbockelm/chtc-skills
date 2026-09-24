# AGENTS.md — maintaining the CHTC skill library

This repository turns CHTC's user documentation into **skill files for the
HTCondor MCP server**. The upstream repositories are vendored as submodules
under `upstream/`; the deliverable is `skills/`.

This file is the working brief for the agent doing the weekly review. Read it in
full before changing anything in `skills/`.

## What this repository is

| Path | What it is |
| --- | --- |
| `skills/` | The deliverable. One Markdown file per skill; this is what the MCP server ingests. |
| `upstream/chtc-website-source` | Submodule. CHTC's website; only `_uw-research-computing/` matters. |
| `upstream/templates-GPUs` | Submodule. CHTC's GPU job templates. |
| `upstream/recipes` | Submodule. CHTC's container build recipes. |
| `tools/upstream-changes.sh` | Shows what changed upstream since the last review. |

The submodule pointers committed here **are the review record**: whatever commit
a submodule is pinned to is the last upstream state these skills were checked
against. Do not bump them casually — bump them as part of a review, in the same
commit as the skill updates they justify.

## Serving the skills

Point the MCP server's skills directory at `skills/`:

```
HTTP_API_MCP_SKILLS_DIR=/path/to/chtc-skills/skills
```

The server loads every `.md` file under the directory, skipping hidden files and
not following symlinks. It exposes `skills_list` (id, name, description) and
`skills_get` (the full Markdown body).

## Skill file format

```markdown
---
name: chtc-gpu-jobs
description: One sentence. This is the ONLY thing an agent sees when listing skills.
sources:
  - chtc-website-source:_uw-research-computing/gpu-jobs.md
  - templates-GPUs:README.md
upstream_reviewed: 2026-09-22
---

# GPU jobs at CHTC

...body...
```

Rules the server imposes:

- **The id** is the path under `skills/` with `.md` removed. `chtc-gpu-jobs.md`
  → id `chtc-gpu-jobs`. Keep the filename and the `name:` identical so
  `skills_get` works with either.
- **`name` and `description`** come from the front matter. If absent, the server
  derives them from the first `# heading` and first paragraph — don't rely on
  that, write them.
- **`description` must be one sentence** and must say *when to reach for this
  skill*, not what CHTC is. It is the entire basis on which an agent chooses.
- Unknown front-matter keys (`sources`, `upstream_reviewed`) are ignored by the
  loader and are ours to use.
- One file is capped at 1 MiB; the library at 2000 files. Not a live concern.

Conventions this repository adds:

- **`sources:`** lists every upstream file the skill was written from, as
  `<submodule name>:<path within it>`. This is what makes the weekly review
  mechanical. Every skill must have at least one. Keep them accurate — a stale
  `sources:` entry is worse than a missing one, because the review will trust it.
- **`upstream_reviewed:`** is the date a human or agent last checked this skill
  against its sources. Bump it on every review, even when nothing changed.
- Names are `chtc-` prefixed and kebab-case.
- Cross-reference sibling skills by bare name in a `## Related skills` section.

## The translation process

This is the substance of the job. CHTC's documentation is written for a person
at a shell on an access point. The reader here is an agent with a set of MCP
tools and **no shell on the access point at all**. Rewriting is not
find-and-replace; the procedure often collapses or changes shape.

### 1. Decide whether the content is in scope

**In scope:** anything about the HTC (HTCondor) system — submitting, resources,
data, containers, GPUs, workflows, monitoring, policy.

**Out of scope, deliberately:**

- **The HPC cluster** (`hpc-*.md`, Slurm, Spack, `hpc/`). Different system,
  different scheduler; this MCP server does not reach it. If a user asks, say so.
- **Getting an account, connecting, SSH keys, VS Code, Open OnDemand**
  (`connecting.md`, `configure-ssh.md`, `vs-code.md`, `ood*.md`). Prerequisites
  that happen before this interface exists.
- **Shell tutorials** (`basic-shell-commands.md`, `dos-unix.md`).
- Events, news, staff pages, the researcher forum.

### 2. Replace the tools

| CHTC command | MCP tool |
| --- | --- |
| `condor_submit file.sub` | `submit_job(submit_file=...)` |
| creating files in `/home`, `chmod +x` | `upload_job_input(files=[{filename, data, is_executable}])` |
| `scp` of a large input | `create_input_upload_url` then `tar … \| curl -T -` |
| `condor_q` | `query_jobs` (always with a projection) |
| `condor_q` to count | `aggregate_jobs(group_by=[...])` |
| `condor_watch_q`, `watch condor_q` | `watch_jobs` + `check_watches` |
| `condor_q -hold` | `query_jobs` projecting `HoldReason`, `HoldReasonCode` |
| `condor_q -better-analyze` | `analyze_job_match` |
| `condor_q -l` | `get_job` |
| `condor_tail` | `tail_job_output` |
| `condor_ssh_to_job` (quick check) | `exec_in_job` |
| `condor_submit -i` | `interactive_session_start` / `_exec` / `_stop` |
| `condor_rm` | `remove_job`, `remove_jobs` |
| `condor_hold` / `condor_release` | `hold_job` / `release_job` |
| `condor_qedit` | `edit_job` |
| `condor_history` | `query_job_archive`, `query_history_db` |
| reading `.log` for usage | `query_job_archive` with a usage projection |
| retrieving results by `ls`/`cat` | `get_job_stdout`, `get_job_stderr`, `get_job_output` |
| `apptainer build` in an interactive job | `build_container(definition=..., verify=...)` |
| `docker build` + `docker push` | `build_container(dockerfile=..., verify=...)` |
| `condor_submit_dag workflow.dag` | `submit_dag(dag=..., files=...)` |

**No equivalent exists** for these; say so plainly in the skill rather than
inventing one:

`condor_status` · `condor_vacate_job` · `quota -vs` · `get_quotas` · `ncdu` ·
any direct filesystem access on the access point.

Where there is a partial substitute, name it: `analyze_job_match` covers most of
what people wanted `condor_status` for; `query_job_epochs` observes restarts
without `condor_vacate_job`.

### 3. Delete the choreography, keep the content

Cut without replacement: logging in, `nano`/`vim` steps, `chmod +x` as a user
action, `ls` to confirm a file exists, `cd` into a directory, `wget` of a tutorial
script, screenshots, YouTube embeds, Jekyll `{% ... %}` tags, "Congratulations,
you've run a job!".

Keep and often expand: **why** a step exists, what goes wrong without it, units,
limits, and the numbers. A CHTC guide's value is the operational knowledge
around the commands, and that survives the translation intact.

### 4. Preserve what does not change

Some advice is about the shape of the work and is identical under any interface.
It is often the most valuable content in the library. Carry it over as-is:

- Decomposing work into many independent tasks; ideal per-job runtimes
- Test one, then a few, then the batch
- Right-sizing resource requests from measured usage
- Smaller and more flexible requests start sooner
- Fair share, and that failed jobs cost real priority
- Checkpointing to fit runtime caps and unlock backfill capacity
- Containers as the software answer
- Nothing is backed up; storage is for active work
- Which limits need a facilitator conversation

### 5. Lean into automated transfer

Where CHTC's documentation offers a choice between a shared-filesystem route and
an automated-transfer route, **document the automated one and explain why**:

- `osdf:///` over `file:///` — no `HasCHTCStaging` requirement, cached, works
  off-site. Always note the caching hazard: change the path when contents change.
- `pelican://` ResearchDrive over copying into `/staging` first.
- `container_image` with an `osdf:///` URL over a `.sif` in `/home`, and over
  `universe = docker`.
- `transfer_output_remaps` / `output_destination` over writing into `/home` and
  moving it later.
- `create_input_upload_url` over reading a large file into the conversation.
- URLs in `transfer_input_files` over staging a copy first.

Where the shared filesystem is genuinely the only route (`/staging/groups`, 30–100
GB files), say that, and say what it costs — CHTC-only execution.

### 6. Rewrite containers around `build_container`

CHTC's container guides are a five-step manual procedure: write the `.def`,
start an interactive build job, run `apptainer build`, `apptainer shell` to test,
`mv` to `/staging`. All five collapse into one `build_container` call.

What must survive the collapse: the definition-file *content* rules — the header,
`%post`/`%environment`/`%files` semantics, `chmod 777 /tmp`, non-interactive
installs, `%runscript` being ignored, `%post` variables not surviving into the
run, and disk sizing. Those are what the user still has to get right.

`verify` deserves emphasis wherever it appears: it is the replacement for the
`apptainer shell` manual test, which is otherwise simply lost.

### 7. Write for an agent

- Lead with the decision, not the background.
- Tables for anything that is a lookup: sizes, limits, codes, tool mappings.
- Concrete submit files and tool calls, not prose descriptions of them.
- Name the failure mode, not just the correct action — an agent that knows what
  a mistake looks like can recover from it.
- Do not restate the MCP server's own instructions (job states, the basic
  submit/upload/watch loop, `$(...)` macro expansion). Those are already in the
  server's system prompt. Add the CHTC-specific layer on top.
- Do not pad. A skill that says less but is all true beats a long one.

## The weekly review

Assume upstream has moved and these skills have not.

### 1. Find what changed

```bash
tools/upstream-changes.sh              # commits + changed files, scoped
tools/upstream-changes.sh --patch      # full diffs when the summary is unclear
```

It compares each submodule's pinned commit (the last review) against the current
upstream tip, restricted to the paths that feed skills, and moves the checkouts
to the tip so you read current text.

### 2. Map changed files to skills

```bash
grep -l 'gpu-jobs.md' skills/*.md
```

Every skill declares its `sources:`. A changed upstream file with **no** skill
claiming it is the interesting case — decide whether it is out of scope (see
§1), or whether CHTC has published something that needs a new skill.

### 3. Judge each change

| Upstream change | Response |
| --- | --- |
| A number moved (quota, runtime, GPU count, tier) | Update it. These go stale fastest. |
| A submit-file attribute added or renamed | Update; check whether other skills repeat it. |
| A new guide in `_uw-research-computing/` | In scope? Extend an existing skill, or add one. |
| A guide deleted or archived | Remove the content; check `sources:` for dangling paths. |
| A new recipe in `recipes/software/` | Add to `chtc-software-recipes` if commonly needed. |
| A new GPU template | Fold the *pattern* into `chtc-gpu-jobs`/`chtc-ml-workflows`; don't transcribe. |
| Prose reworded, examples retyped | Usually nothing. Don't churn. |
| A policy change (like the April 2026 `condor_ssh_to_job` change) | High priority. Policy changes alter what an agent may do. |

Bias toward doing nothing on cosmetic changes. Skills that churn weekly are
harder to trust than skills that move when something real moves.

### 4. Also review the MCP side

Upstream CHTC is only half the input. Check whether the MCP server's tools have
changed — new tools, renamed arguments, tools that appeared or disappeared in
this deployment. A skill that tells an agent to call a tool that does not exist
is worse than no skill. `get_version` reports the deployed build.

In particular, re-check whether `build_container`, `create_input_upload_url`,
`query_history_db` and `aggregate_jobs` are present on the target access point;
several skills describe fallbacks for their absence and those fallbacks should
stay accurate.

### 5. Update and record

For every skill you touched, and every skill whose sources you checked and found
unchanged, set `upstream_reviewed:` to today. Then:

```bash
tools/upstream-changes.sh --pin        # stage the new submodule pointers
git add skills/
git commit
```

**Pin and update in the same commit.** A commit that bumps the submodules without
updating the skills silently claims a review that did not happen.

### 6. Report

Say, in the response:

- Which upstream files changed and which skills were updated as a result
- Anything that changed upstream and was deliberately *not* reflected, and why
- Any upstream change you could not verify (a number with no authoritative
  source, a policy with an unclear effective date)
- Anything that looks out of date in the upstream docs themselves

## Known upstream inconsistencies

Carried knowingly; re-check them during review rather than rediscovering them.

- **`/home` default quota** is given as 20 GB in `htc-overview.md` and 40 GB in
  `htc-job-file-transfer.md`. The skills use 40 GB and flag the discrepancy.
- **Operating system references are stale.** `htc-overview.md` still says the
  submit servers run CentOS 7 and the default execute OS is CentOS 8 Stream;
  `os-request-htc.md` discusses EL9/EL10. The skills avoid asserting a specific
  default OS and recommend containers instead.
- **Docker universe** appears throughout `templates-GPUs`, while the website now
  recommends Apptainer and `container_image`. The skills prefer Apptainer and
  explain the trade-off rather than mirroring the templates.
- **GPU counts and models** (`site.data.gpus`, the ~150 shared GPUs figure) come
  from a data file rendered into the page. Treat any specific model or count in
  a skill as approximate and avoid adding more of them.
- **`condor_ssh_to_job` on shared GPU machines** was disabled April 2026. Check
  whether the policy has moved again.

## Adding a new skill

1. Confirm it is not a section of an existing skill. Prefer extending.
2. Name it `chtc-<topic>.md`, `name:` matching the filename.
3. Write the `description:` first, as one sentence answering "when would an
   agent need this?". If that sentence is hard to write, the skill's scope is
   wrong.
4. List every `sources:` file and set `upstream_reviewed:`.
5. Add it to the routing table in `skills/chtc-overview.md` — an agent that
   never learns a skill exists will never call it.
6. Add `## Related skills` links, and add the new skill to its siblings' lists.
