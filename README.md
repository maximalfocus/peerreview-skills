# peerreview-skills

A cross-model co-editing **peer-review gate** for skill-generated repos.

## Problem this repo solves

Skill workflows (cdd, system, tutorial, present, …) produce repos whose
artifacts are "believed done" but never adversarially checked against the
problem they were meant to solve. `/peerreview` closes that gap: the HOST acts
as reviewer/manager and the fixed independent pair co-edits (Pi/DeepSeek host →
Codex CLI peer; Codex CLI host → Pi/DeepSeek peer) until a fresh active review
charter is objectively satisfied and verification is green.

## How it works

- **Charter-first without a duplicate contract.** Each run derives a private,
  temporary `PROBLEM.md` (schema: [`templates/PROBLEM.md`](templates/PROBLEM.md))
  from the current instruction and durable PRD/PLAN/spec/tests/docs. It proceeds
  without routine confirmation, but stops if durable intent is absent or conflicts.
- `/peerreview` reads the active charter **adversarially**, works out a review plan
  and a *round forecast* (transparency only), then loops:
  HOST reviews → PEER co-edits (`scripts/pi-round.sh` or
  `scripts/codex-round.sh`) → HOST re-verifies the real diff and re-runs the
  gate → commit the round. Pi is pinned to the `deepseek` API-key provider;
  Codex CLI must use an OpenAI ChatGPT subscription (`codex login`).
- **Fail closed.** If either required side is missing, unauthenticated,
  quota-blocked, or returns no report, the review stops—there is no third CLI or
  same-HOST substitute.
- **Convergence, not a round cap, is the stop condition.** Successful reviews
  create annotated `peerreview/converged/*` tag checkpoints. Later reviews use
  anchor→HEAD plus impact closure unless risk requires a full-tree pass.
- **HOST owns git. PEER never commits or pushes.** The temporary charter never
  enters the reviewed repo and is cleaned on every terminal path; an existing
  user-authored `PROBLEM.md` is an input and is never edited or deleted.

## Layout

```
peerreview-skills/
├── CONSTITUTION.md                     ← the law: evolution is a filter, not a log (Articles 1–5 shared cross-family)
├── CLAUDE.md                           ← repo conventions
├── skills/peerreview/SKILL.md          ← the /peerreview gate (single source of truth)
├── skills/peerreview-evolve/SKILL.md   ← the /peerreview-evolve methodology filter
├── skills/peerreview-approach-*/       ← per-artifact review-lens modules (Read-loaded)
├── templates/PROBLEM.md                ← the active review-charter schema
├── scripts/pi-round.sh                 ← Pi/DeepSeek co-edit + verdict driver
├── scripts/codex-round.sh              ← Codex CLI co-edit + verdict driver
├── scripts/git-guard.sh                ← shared PEER git-mutation guard
├── scripts/peer-auth.sh                ← credential-safe fixed-pair preflight
├── scripts/select-peer.sh              ← deterministic HOST→PEER routing
├── scripts/charter-temp.sh             ← private active-charter lifecycle
├── scripts/review-anchor.sh            ← durable convergence-tag checkpoints
├── scripts/validate-knowledge-artifacts.py ← deterministic knowledge-repo checks
├── tests/round-drivers.sh              ← fixed-pair driver smoke tests
└── README.md
```

Evolution is governed by [`CONSTITUTION.md`](CONSTITUTION.md): a lesson either
passes the constitution and is edited into a skill file, or it fails and nothing
happens. **There is no `evolution/` log** — git history is the record; the raw
session traces (Pi: `$TMPDIR/peerreview-pi-sessions/`; Codex CLI:
`~/.codex/sessions/`) are the diagnostic source. (The former
`INDEX.md` / `PATTERNS.md` / `runs/` were removed on 2026-07-03 when peerreview
adopted this constitution.)

Reviewed repos under `~/projects` are left **uncommitted and unpushed** for
manual verification on a Windows machine (see `skills/peerreview/SKILL.md` →
*Path-scoped git policy*); elsewhere `/peerreview` commits and pushes the
converged repo.

## Install

The fixed pair is **Pi (DeepSeek API key) ↔ Codex CLI (OpenAI ChatGPT
subscription)**; `/peerreview` runs as HOST inside either and fails closed
anywhere else (Claude Code can still load the skill, but `select-peer.sh`
rejects it as an unsupported HOST). Symlink the same source skills into each
side's skill directory.

### Pi

Pi is the DeepSeek API-key side of the pair: select a DeepSeek model provider
(API key present, e.g. via `DEEPSEEK_API_KEY`), then symlink the same source
skills:

```sh
ln -s ~/personal/peerreview-skills/skills/peerreview        ~/.pi/agent/skills/peerreview
ln -s ~/personal/peerreview-skills/skills/peerreview-evolve ~/.pi/agent/skills/peerreview-evolve
```

Restart Pi after installation so it rebuilds the skill index.

### Codex CLI

The Codex CLI is the OpenAI-subscription side of the pair: log in with
`codex login` (ChatGPT subscription — API-key auth is not this contract), then
symlink the same source skills:

```sh
ln -s ~/personal/peerreview-skills/skills/peerreview        ~/.codex/skills/peerreview
ln -s ~/personal/peerreview-skills/skills/peerreview-evolve ~/.codex/skills/peerreview-evolve
```

Restart Codex after installation so it rebuilds the skill index.

## Producer integration

Producers persist their own authoritative PRD/PLAN/specification, not review
scaffolding. `/peerreview` projects those sources into its temporary active
charter. A legacy producer-authored root `PROBLEM.md` remains a valid durable
input and is never removed. `/peerreview` is **user-initiated only** — producers
suggest it rather than auto-invoking it. The sole exception is explicit `/cdd-auto`,
whose invocation authorizes mandatory per-wave calls to the canonical skill.
