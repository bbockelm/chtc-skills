# chtc-skills

CHTC's user documentation, rewritten as skill files for the
[HTCondor MCP server](https://github.com/bbockelm/golang-htcondor).

An agent driving a CHTC access point through MCP has the tools but not the local
knowledge: it does not know that a GPU job needs `+WantGPULab = true`, that
`osdf:///` caches by path, that `/staging` has a 1000-item quota, or that a build
job is capped at four hours. This repository puts that knowledge where the agent
will look for it.

## Using it

Point the MCP server's skills directory at `skills/`:

```
HTTP_API_MCP_SKILLS_DIR=/path/to/chtc-skills/skills
```

The agent then sees `skills_list` (ids, names, one-line descriptions) and
`skills_get` (the full document). Start with `chtc-overview`, which routes to
the rest.

## The skills

| Skill | Covers |
| --- | --- |
| `chtc-overview` | Start here — the working model and which skill to read next |
| `chtc-policies-and-limits` | Runtime caps, job counts, quotas, data policy, fair share |
| `chtc-submit-basics` | Writing and submitting a job; the CHTC submit-file conventions |
| `chtc-resource-requests` | Sizing CPU, memory and disk from measured usage |
| `chtc-many-jobs` | `queue N`, `queue … from`, `initialdir`, scale limits |
| `chtc-data-transfer` | Which protocol for which file size; getting results back |
| `chtc-staging-large-data` | `/staging` policy and use without a shell |
| `chtc-researchdrive-uwdf` | `pelican://` transfers to and from ResearchDrive |
| `chtc-containers` | Building Apptainer images with `build_container` |
| `chtc-software-recipes` | Starting definitions for Python, Conda, R, Julia, PyTorch, … |
| `chtc-gpu-jobs` | GPU Lab opt-in, tiers, capability floors, backfill |
| `chtc-ml-workflows` | Training/inference decomposition, sweeps, batch LLM inference |
| `chtc-checkpointing` | Exit-code-85 self-checkpointing and verifying resume |
| `chtc-scaling-beyond-chtc` | `want_campus_pools` / `want_ospool` |
| `chtc-monitoring` | Watches instead of polling; reading a running job |
| `chtc-troubleshooting` | Idle, held and failing jobs; CHTC's known issues |
| `chtc-interactive-sessions` | Shells on execute nodes; build and GPU sessions |

## Sources

Vendored as submodules under `upstream/`:

- [CHTC/chtc-website-source](https://github.com/CHTC/chtc-website-source) —
  `_uw-research-computing/` only
- [CHTC/templates-GPUs](https://github.com/CHTC/templates-GPUs)
- [CHTC/recipes](https://github.com/CHTC/recipes)

```bash
git clone --recurse-submodules <this repo>
# or, in an existing clone:
git submodule update --init --recursive
```

Each skill lists the upstream files it was written from in its `sources:` front
matter. The submodule pointers committed here record the upstream state the
skills were last checked against.

## Keeping it current

```bash
tools/upstream-changes.sh          # what moved upstream since the last review
tools/upstream-changes.sh --patch  # full diffs
tools/upstream-changes.sh --pin    # record the review, after updating skills
```

[`AGENTS.md`](AGENTS.md) is the brief for the agent doing that review: the
translation rules, what is deliberately out of scope, and the known
inconsistencies in the upstream documentation.

## Scope

**In:** CHTC's HTC (HTCondor) system.

**Out:** the HPC/Slurm cluster, account creation, SSH and editor setup, and shell
tutorials. These skills assume an agent that reaches CHTC only through the MCP
server and has no shell on the access point.

## Caveats

These documents are a translation, not a copy. Where CHTC's published
documentation and these skills disagree, **CHTC's documentation is
authoritative**: <https://chtc.cs.wisc.edu/uw-research-computing/>. Questions
about policy, quotas or capacity go to chtc@cs.wisc.edu.
