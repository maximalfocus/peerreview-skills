# peerreview-skills repo conventions

Evolution here is governed by [`CONSTITUTION.md`](CONSTITUTION.md) — a **filter, not an accumulator**. A finding either passes the constitution and is integrated into a skill file, or it fails and **nothing happens**. There is no `evolution/` log; the former `INDEX.md` / `PATTERNS.md` / `runs/` were removed on 2026-07-03 (git history is the record, the raw session traces are the diagnostic source). Re-creating any such log is a violation of Article 1.

## Commit and push after edits — do not wait to be asked

The user has standing authorization (2026-06-13) to commit and push routine work in this repo without being prompted each time. When a task that modifies `skills/` or `CONSTITUTION.md` reaches a clean stopping point, commit and push it yourself.

- **Stage only this task's changeset.** Use explicit `git add <paths>` — **never `git add -A`**. This repo can carry unrelated dirty files from sibling/parallel sessions; sweeping them into an unrelated commit is the failure mode to avoid.
- **Write a real message** in the repo's `evolve:` / `fix:` / `research:` style, ending with the `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer.
- **Commit directly to `main`.** `git pull --rebase origin main` before committing so the push is a fast-forward; retry the rebase+push on a non-fast-forward rejection (≤3). Never force-push, never branch/PR for routine evolve edits.
- Scope of the standing authorization: routine skill/evolution edits + their push. Still confirm for destructive git ops (history rewrite, force-push, file deletions) and any outward-facing action beyond this push.

This is the same discipline `CONSTITUTION.md` Article 9 encodes.

## Single source of truth: `skills/<name>/SKILL.md`

Both skills are authored only in `skills/<name>/SKILL.md`:
- `skills/peerreview/SKILL.md` — the `/peerreview` cross-model co-editing gate.
- `skills/peerreview-evolve/SKILL.md` — the `/peerreview-evolve` methodology-evolution filter.

`skills/peerreview/` is symlinked into `~/.claude/skills/peerreview/` (only `SKILL.md` is symlinked — so inside a skill, reference `scripts/` and `templates/` by absolute repo path `~/personal/peerreview-skills/...`, never a base-dir-relative path).

There is **no `commands/` mirror** (unlike cdd-skills) — peerreview is user-initiated with no `~/.claude/commands/` dependency. Keep it that way unless a concrete need appears.

Every HOST loads the same source skills directly — Claude Code from `~/.claude/skills/<name>/`, the Codex CLI from `~/.codex/skills/<name>/`, Pi from `~/.pi/agent/skills/<name>/`. Symlink `skills/*` there; do not create a separate mirror because `skills/` is already the portable artifact. The peer ladder is resolved by `scripts/select-peer.sh`, never in prose: tier 1 is Claude Code (Claude subscription) ↔ the Codex CLI (`codex login`, ChatGPT subscription); tier 2 is `dsh` for CDD-harnessed repos and Pi on a DeepSeek API-key provider otherwise, and is reached only when no tier-1 peer is reachable. The PEER vendor is never the HOST vendor. Authenticate each side before using it as the peer; a side used only as a PEER needs its CLI and auth, not the skills.

## Approach modules (`skills/peerreview-approach-*`)

Loaded via `Read` references inside `skills/peerreview/SKILL.md` (Step 1.5 detection table). They have no slash command and no `commands/` mirror. Each supplies an artifact-type's dominant defect class, review lenses, and verification-gate amendments. The dated worked-examples inside a lens (`ringbuffer-prd 2026-06-13: …`) are **evidence that is part of the rule**, not a log — they document *why* the lens exists and stay with it. New profile → new module + register it in the Step 1.5 table (see `/peerreview-evolve` → Approach module management).

## Script the mechanical, prose the judgment

A step with one correct output (scaffolding, structural/format validation, counts, git plumbing, the size gate) belongs in a shared tool under `scripts/` that a skill *invokes* — not re-derived in prose each run, and never copy-pasted per project. Keep prose only for steps needing judgment. Full rationale + the test for which is which: **Article 5** of `CONSTITUTION.md`.

## Size discipline

Skill files are load-bearing context read in full every run; every edit adds pressure. The **size gate (Article 6)** caps them — `skills/peerreview/SKILL.md` ≤ 1000, `skills/peerreview-approach-*/SKILL.md` ≤ 800, `skills/peerreview-evolve/SKILL.md` ≤ 150 lines. Prefer tightening or replacing an existing line over appending a new one; a new rule must be a *rule*, not an anecdote. Over cap → compress in the same change or revert.

## Hygiene

- `.gitignore` keeps OS/editor/agent junk out (`.DS_Store`, `.claude/`).
- `.gitattributes` pins LF on every platform — this repo lives in `~/personal` (outside `~/projects`), so it is normalized LF and committed normally. The `~/projects` no-commit/no-push policy in `skills/peerreview/SKILL.md` applies to repos *under review*, never to this repo.

## Naming conventions

Adopted 2026-09-03. Cite the rule IDs in issues and review comments.

- **Issue title (N-1).** Imperative outcome, sentence case. No type prefix, no
  trailing period, no issue number, no requirement/slice ID. Say what is true
  when the issue closes, not only the symptom. One coherent outcome per issue —
  a conjunction alone is not a reason to split; split only when the joined parts
  are independently deliverable and verifiable. This is a review rule, not a
  mechanical grammar.
- **PR title (N-2).** Character-identical to the issue it delivers. If the
  wording is wrong, edit the issue first, then match it.
- **Branch (N-3).** Routine work commits directly to `main` here, which
  overrides N-3. When a change does use a branch, name it
  `issue/<issue-number>-<lowercase-kebab-slug>`.
- **Commit subject (N-4).** `<type>(<scope>)?: <lowercase imperative>`, at most
  72 authored characters — a provider-added trailing ` (#N)` sits outside that
  budget. Scope is one kebab-case identifier: no spaces, no colon, one scope
  only. Evidence, rationale and measurements belong in the body, never the
  subject.
  Types: `evolve` `fix` `research` `peerreview` `feat` `docs` `test` `refactor`
  `chore` `ci`
  (`evolve`/`fix`/`research` are this repo's established style; `peerreview:` is
  emitted by round commits — keep them.)
- **Squash subjects are a known exception, until landing is changed.** `gh pr
  merge --squash` without `--subject` derives the commit subject from the
  untyped N-2 PR title, so N-4 cannot hold for the squash commit today. Until
  landing builds `<type>: <issue title, initial letter lowercased> (#<PR>)` from
  a `Delivery-Type:` field in the PR body, set the squash subject by hand at
  merge time, or accept the untyped one. Do not "fix" it by putting a type
  prefix on the PR title — that breaks N-2 instead.
- **Private material.** This repository is private today; the rule is
  prospective, because a leak recorded now survives into any later publication.
  Never name the private companion product-contract repository (this project's
  `{project}-prd` sibling), one of its documents, or one of its sections in a
  branch, commit, issue, or PR — not even in order to say what must not be
  named. A requirement or slice identifier
  (`R-###`, `S-###`, `SLICE-###`, `FR-###`, `NFR-###`) is forbidden only where
  it is defined *solely* in that companion. `S-###`/`FR-###` are defined only
  there. Never rely on a history rewrite as cleanup — commits survive in
  provider-retained PR refs, and issue/PR text is provider metadata outside git
  entirely.
- **Labels.** None by default. Add one only when a repository template requires
  it or it names a partition someone actually queries; a label applied uniformly
  to every issue partitions nothing.
