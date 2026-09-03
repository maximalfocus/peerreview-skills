# peerreview-skills

A cross-model co-editing **peer-review gate** for skill-generated repos.

## Problem this repo solves

Skill workflows (cdd, system, tutorial, present, …) produce repos whose
artifacts are "believed done" but never adversarially checked against the
problem they were meant to solve. `/peerreview` closes that gap: the HOST acts
as reviewer/manager and an independent **cross-vendor** PEER co-edits until a fresh
active review charter is objectively satisfied and verification is green. The PEER is
resolved mechanically, never chosen in prose: tier 1 is Claude Code ↔ the Codex CLI;
tier 2 is a disclosed degradation reached only when no tier-1 peer is reachable.

## How it works

- **Charter-first without a duplicate contract.** Each run derives a private,
  temporary `PROBLEM.md` (schema: [`templates/PROBLEM.md`](templates/PROBLEM.md))
  from the current instruction and durable PRD/PLAN/spec/tests/docs. It proceeds
  without routine confirmation, but stops if durable intent is absent or conflicts.
- `/peerreview` reads the active charter **adversarially**, works out a review plan
  and a *round forecast* (transparency only), then loops:
  HOST reviews → PEER co-edits (the driver `scripts/select-peer.sh` resolves:
  `claude-round.sh`, `codex-round.sh`, `pi-round.sh`, or `dsh-round.sh`) → HOST
  re-verifies the real diff and re-runs the gate → commit the round. Each side has
  its own auth contract: a Claude subscription, an OpenAI ChatGPT subscription
  (`codex login`), Pi on the `deepseek` API-key provider, `DEEPSEEK_API_KEY` for `dsh`.
- **Fail closed.** If no cross-vendor peer is reachable, or the resolved one is
  unauthenticated, quota-blocked, or returns no report, the review stops. **The PEER
  vendor is never the HOST vendor** — a same-vendor pass is a degraded review, not a
  peer review — so there is no same-vendor substitute and a DeepSeek HOST has no
  tier-2 fallback.
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
├── scripts/claude-round.sh             ← Claude Code co-edit + verdict driver (tier 1)
├── scripts/codex-round.sh              ← Codex CLI co-edit + verdict driver (tier 1)
├── scripts/pi-round.sh                 ← Pi/DeepSeek co-edit + verdict driver (tier 2)
├── scripts/dsh-round.sh                ← DeepSeek Harness driver (tier 2, CDD repos)
├── scripts/round-support.sh            ← portable per-round deadline + failure tail
├── scripts/git-guard.sh                ← shared PEER git-mutation guard
├── scripts/delivery-branch.sh          ← review-on-a-branch, landed as one commit
├── scripts/chat-review-temp.sh         ← ephemeral `--chat` workspace lifecycle
├── scripts/peer-auth.sh                ← credential-safe per-side auth preflight
├── scripts/select-peer.sh              ← deterministic HOST→PEER routing
├── scripts/charter-temp.sh             ← private active-charter lifecycle
├── scripts/review-anchor.sh            ← durable convergence-tag checkpoints
├── scripts/validate-knowledge-artifacts.py ← deterministic knowledge-repo checks
├── tests/round-drivers.sh              ← peer routing, driver, and guard smoke tests
├── LICENSE                             ← MIT
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
manual verification on another machine (see `skills/peerreview/SKILL.md` →
*Path-scoped git policy*, and *Author-specific conventions* below); elsewhere
`/peerreview` commits and pushes the converged repo.

## Install

`/peerreview` runs as HOST inside Claude Code, the Codex CLI, Pi, or the DeepSeek
Harness, and resolves its PEER mechanically with `scripts/select-peer.sh`. Tier 1 is
**Claude Code (Claude subscription) ↔ Codex CLI (OpenAI ChatGPT subscription)**. Tier 2
is reached only when no tier-1 peer is authenticated and reachable, and is `dsh` for
CDD-harnessed repositories and Pi for every other repository; it is a disclosed
degradation, named in the terminal report. The PEER vendor is never the HOST vendor.

Install the skills for each side you intend to run `/peerreview` **as HOST**. A side
used only as a PEER needs its CLI and authentication, not the skills — every driver
carries the whole brief in the round prompt.

### Checkout location — the installation contract

Clone this repository to **`~/personal/peerreview-skills`**. The skill files name
their own checkout by that absolute path (`~/personal/peerreview-skills/scripts/…`,
the `Read`-loaded approach modules, `CONSTITUTION.md`) because a HOST resolves a
symlinked skill through the symlink, so a path relative to the skill file would not
reach `scripts/` or `templates/`. The path is the contract, not an assumption about
any particular machine: to keep the checkout elsewhere, rewrite it once after cloning
and keep the rewrite when you pull:

```sh
git grep -l '~/personal/peerreview-skills' -- skills CLAUDE.md CONSTITUTION.md README.md \
  | xargs perl -pi -e 's|~/personal/peerreview-skills|/your/path/peerreview-skills|g'
```

### Author-specific conventions

Two conventions in the skill files come from the author's setup. Neither is required
to run `/peerreview`; each is named here so a reader can tell contract from habit.

- **Path-scoped git policy (`~/projects`).** Repositories under `~/projects` are
  reviewed without any git write, because the author verifies and commits them by
  hand on another machine. If you have no such directory the policy never triggers;
  if you want the same behaviour for a different directory, edit the *Path-scoped git
  policy* section of `skills/peerreview/SKILL.md`.
- **Sibling checkouts under `~/personal/`.** The `cdd-*` profiles render a progress map
  from `~/personal/cdd-skills`, the `knowledge-artifacts` profile reads the format
  contract from `~/personal/knowledge-skills` when available, and the `cdd-prd` profile
  looks for a reviewed project's siblings as `~/personal/{project}-*`. These are the
  author's sibling checkouts; without them those profile-specific steps are unavailable
  and a review of such a repository must say so in its report. All other profiles are
  unaffected.

### Claude Code — tier 1

Sign in with a Claude subscription (`claude auth login`; raw API-key auth is not this
contract), then symlink the source skills:

```sh
ln -s ~/personal/peerreview-skills/skills/peerreview        ~/.claude/skills/peerreview
ln -s ~/personal/peerreview-skills/skills/peerreview-evolve ~/.claude/skills/peerreview-evolve
```

The approach modules are `Read`-loaded by absolute repository path, so they need no
symlink of their own.

### Codex CLI — tier 1

Log in with `codex login` (ChatGPT subscription — API-key auth is not this contract),
then symlink the same source skills:

```sh
ln -s ~/personal/peerreview-skills/skills/peerreview        ~/.codex/skills/peerreview
ln -s ~/personal/peerreview-skills/skills/peerreview-evolve ~/.codex/skills/peerreview-evolve
```

Restart Codex after installation so it rebuilds the skill index.

### Pi — tier 2

Select a DeepSeek model provider (API key present, e.g. via `DEEPSEEK_API_KEY`), then
symlink the same source skills:

```sh
ln -s ~/personal/peerreview-skills/skills/peerreview        ~/.pi/agent/skills/peerreview
ln -s ~/personal/peerreview-skills/skills/peerreview-evolve ~/.pi/agent/skills/peerreview-evolve
```

Restart Pi after installation so it rebuilds the skill index. A Pi HOST must be on
`PI_PROVIDER=deepseek`, because that pins the vendor the peer ladder resolves against.

### DeepSeek Harness (`dsh`) — tier 2

The tier-2 peer for CDD-harnessed repositories. As a PEER it needs no skill
installation: `dsh-round.sh` has no session resume and passes the complete brief on
argv every round. It requires `DEEPSEEK_API_KEY` and a headless profile that composes
offline (`dsh --profile headless --dump-config`).

## Producer integration

Producers persist their own authoritative PRD/PLAN/specification, not review
scaffolding. `/peerreview` projects those sources into its temporary active
charter. A legacy producer-authored root `PROBLEM.md` remains a valid durable
input and is never removed. `/peerreview` is **user-initiated only** — producers
suggest it rather than auto-invoking it. The sole exception is explicit `/cdd-auto`,
whose invocation authorizes mandatory per-wave calls to the canonical skill.

## License

MIT — see [`LICENSE`](LICENSE).
