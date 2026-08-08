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

Codex loads the same source skills directly from `$CODEX_HOME/skills/<name>/SKILL.md` (default: `~/.codex/skills/<name>/SKILL.md`). Use `scripts/install-codex.sh` to symlink `skills/*` there. Do not create a separate Codex mirror; `skills/` is already the portable artifact.

## Approach modules (`skills/peerreview-approach-*`)

Loaded via `Read` references inside `skills/peerreview/SKILL.md` (Step 1.5 detection table). They have no slash command and no `commands/` mirror. Each supplies an artifact-type's dominant defect class, review lenses, and verification-gate amendments. The dated worked-examples inside a lens (`ringbuffer-prd 2026-06-13: …`) are **evidence that is part of the rule**, not a log — they document *why* the lens exists and stay with it. New profile → new module + register it in the Step 1.5 table (see `/peerreview-evolve` → Approach module management).

## Script the mechanical, prose the judgment

A step with one correct output (scaffolding, structural/format validation, counts, git plumbing, the size gate) belongs in a shared tool under `scripts/` that a skill *invokes* — not re-derived in prose each run, and never copy-pasted per project. Keep prose only for steps needing judgment. Full rationale + the test for which is which: **Article 5** of `CONSTITUTION.md`.

## Size discipline

Skill files are load-bearing context read in full every run; every edit adds pressure. The **size gate (Article 6)** caps them — `skills/peerreview/SKILL.md` ≤ 1000, `skills/peerreview-approach-*/SKILL.md` ≤ 800, `skills/peerreview-evolve/SKILL.md` ≤ 150 lines. Prefer tightening or replacing an existing line over appending a new one; a new rule must be a *rule*, not an anecdote. Over cap → compress in the same change or revert.

## Hygiene

- `.gitignore` keeps OS/editor/agent junk out (`.DS_Store`, `.claude/`).
- `.gitattributes` pins LF on every platform — this repo lives in `~/personal` (outside `~/projects`), so it is normalized LF and committed normally. The `~/projects` no-commit/no-push policy in `skills/peerreview/SKILL.md` applies to repos *under review*, never to this repo.
