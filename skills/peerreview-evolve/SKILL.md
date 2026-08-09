---
name: peerreview-evolve
description: "peerreview methodology evolution — filter review lessons and pull-based research through the constitution: pass → integrate into a skill and commit; fail → do nothing. No logs."
disable-model-invocation: true
allowed-tools: Read Write Edit Grep Glob Bash(git *) Bash(wc *) Bash(ls *) Bash(bash *)
argument-hint: "[research|post-review|simplify]"
---

# /peerreview-evolve — Evolve the peerreview methodology

You improve the peerreview skill family from real use. Evolution is a **filter, not an accumulator**: every candidate change has exactly two fates — **pass** the constitution → edit the target skill and commit; **fail** → do nothing. There is no research log, no proposals queue, no patterns ledger. The skills are the product; **git history is the record**; the raw session traces at `~/.claude/projects/` are the diagnostic source.

## First: read the constitution

Read [`~/personal/peerreview-skills/CONSTITUTION.md`](../../CONSTITUTION.md) — the law that governs any change here (the bar, the size gate, instruction-surface classification, the deterministic-step contract, meta-conformance, the trust boundaries, and the commit-and-publish rules). It is the gate; this file is only the procedure. Then read the skill files you might touch (`skills/peerreview/SKILL.md`, `skills/peerreview-approach-*/SKILL.md`) and this skill's own git history (`git log --oneline -- skills/<name>/SKILL.md`, plus commit bodies) for prior lessons.

## Evidence, not summaries

There are no summary logs to read — reconstruct what actually happened from primary sources:
- **Raw session traces**: under Pi, inspect `$PI_SESSION_FILE`; under Claude Code, use `~/.claude/projects/{sanitized-path}/{session-id}.jsonl` (replace `/` with `-`, prefix with `-`); under the Codex CLI, use the newest `~/.codex/sessions/{YYYY}/{MM}/{DD}/rollout-*.jsonl` for the reviewed repo. Grep selectively for verdicts, dismissed-then-confirmed findings, `NOT CONVERGED` streaks, fallback disclosures, and gate errors.
- **Git history** of the skills and of the reviewed repos — `git log`, `git diff`. A recurring defect class the review keeps catching (or keeps *missing* until a re-run) is the signal that a lens should sharpen or a new one should exist.

## Trigger modes

Same gate in all three; they differ only in what surfaces the candidate.

### Mode 1 — Post-review (after a `/peerreview` run)

1. Read the raw session traces for the run (grep for verdict rounds, dismissed findings, fallbacks, gate errors). Diagnose from raw data, not memory.
2. Detect candidates across the traces + git history. Match proof to the claim: a mechanically reproducible defect-class gap may be proven in one review; a behavioral generalization needs multiple independent occurrences. Count primary evidence, not evolve attempts.
3. For each proven candidate, draft the minimal skill edit (usually a lens in the matching `peerreview-approach-*` module, or a Step in the main skill) and run it through the gate below.

### Mode 2 — On-demand research (a review-surfaced gap OR a user-pulled source/topic in `$ARGUMENTS`)

Research is **pull-based, never scheduled** — the trigger (a real gap or a deliberate human pull) is the relevance filter. Stay on the trigger; do not breadth-sweep adjacent domains. Web-search the specific tool/standard/practice, then evaluate each finding against the constitution (already covered? proven? which instruction-surface layer? Impact×Confidence/Effort ≥ 3?). A finding that is runtime/tooling, not methodology (Article 4), does not graduate.

### Mode 3 — Simplification (monthly, on a size-gate breach, or `$ARGUMENTS: simplify`)

Counteract accretion. Measure line/section counts; flag files that grew, overlapping lenses across modules, guidance no review ever exercised, and worked-examples a model upgrade may have outgrown (re-test load-bearingness one piece at a time). Then **Merge / Promote / Demote / Remove / Compress** — deletions that preserve capability win (Article 2). Collapse a family of near-identical worked examples into one running-summary line.

## The gate (apply this to every candidate, every mode)

For each candidate change, in priority order:

1. **Judge against `CONSTITUTION.md`** — the bar (Article 3), instruction-surface class (Article 4), deterministic-step contract (Article 5). If it fails any, **discard it and stop** — do not record it anywhere.
2. **Apply** the edit to the target skill file(s). Prefer replacing/compressing existing guidance over adding; a lens belongs in its `peerreview-approach-*` module, the anecdote-as-evidence stays terse and inline.
3. **Validate mechanically:** cross-references resolve to real files; meta-conformance holds (Article 7); the **size gate passes** (Article 6) — if a file goes over cap, compress in the same change or revert.
4. **Keep or discard:** kept = it simplifies or adds review capability peerreview genuinely lacked and passes validation; discard (revert to the pre-change git state) = validation failed or it adds complexity without clear value. A discard leaves no trace.
5. **Commit** each kept change (Article 9). The commit message is the only record of what and why — make it real.

If a candidate crashes mid-apply, revert it and continue to the next; never abort the whole pass for one failed experiment.

## Approach module management

New artifact-type profile with no matching `peerreview-approach-*`? Create `skills/peerreview-approach-{profile}/SKILL.md` (dominant defect class, review lenses, verification-gate amendments, what NOT to flag, forecast hint), register it in the main skill's **Step 1.5 detection table**, commit. A profile seen once inline in Step 2 graduates to its own module on the 2nd repo that matches it.

### GATE: Commit and publish (before skill exit)

Every kept change must reach `maximalfocus/peerreview-skills` on `main` — follow **Article 9** of the constitution: stage only this session's explicit paths (never `git add -A`), edit `CONSTITUTION.md` and `skills/` only (there is no `commands/` mirror), `git pull --rebase origin main` before committing, retry the push on non-fast-forward rejection (≤3), never force-push or branch. Verify the size gate and report the commit SHA(s). Scope: this repo only — repos under review follow the Path-scoped git policy.

## After completion: evolve this skill

This meta-skill evolves itself. After a pass, ask: did the gate filter correctly (nothing valuable dropped, nothing speculative kept)? Is pull-based triggering surfacing the right work? If a real gap slipped through, that is the signal to sharpen the constitution — fix `CONSTITUTION.md` or this file and commit. If not, do nothing.

`$ARGUMENTS`: optional — `research` (supply the topic/source to pull), `post-review`, `simplify`, or a specific research topic. If omitted, auto-detect from context.
