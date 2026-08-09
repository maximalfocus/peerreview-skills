# peerreview Constitution

The law that governs every change to the peerreview methodology. It exists so that evolution is a **filter, not an accumulator**: a finding either passes this constitution and is integrated into a skill file, or it fails and **nothing happens** — no queue, no log, no "deferred" pile. The skills are the product; git history is the record; the raw session traces at `~/.claude/projects/` are the diagnostic source. There is no separate `evolution/` log — the former `INDEX.md` / `PATTERNS.md` / `runs/` were removed on 2026-07-03 when peerreview adopted this constitution — and re-creating one is a violation of Article 1.

**Articles 1–5 are the shared, family-agnostic law of the `*-skills` evolve methodology** — reproduced **byte-identical** in every family's own `CONSTITUTION.md` (`cdd-skills`, `system-skills`, `tutorial-skills`, `knowledge-skills`, `note-skills`, `present-skills`, `peerreview-skills`, `video-skills`); `cdd-skills/tools/constitution-sync.sh` enforces that they do not drift (cdd-skills is the reference). Articles 6–9 are specific to peerreview-skills. The `/peerreview-evolve` skill reads **this** file first and applies it as the gate.

---

## Article 1 — Pass or nothing (no logs)

A candidate change has exactly two fates:

- **Pass** → edit the target skill file(s) and commit. The commit message is the record of *what* and *why*.
- **Fail** → do nothing. Do not write it down "for later." A record no one will read is pure write-only cost.

No `evolution/` log, no proposals queue, no patterns ledger, no index. If a finding is worth acting on, act on it now; if it isn't, drop it. "Maybe someday when a project needs it" is a **fail** — it can be rediscovered from the same trigger that would have surfaced it.

## Article 2 — You are the bloat vector

The model executing an evolve pass is the entity most prone to making the methodology larger, not better — work costs it nothing, so it feels no pressure to simplify. Before adding any guidance, ask: **would a senior engineer with finite time bother writing this down, or would they trust the existing guidance and move on?** If the latter, it fails.

Deletions that preserve capability are always better than additions. Twenty lines of new guidance must justify themselves against zero. Compress after every change.

## Article 3 — The bar

A change passes only if it clears all of:

1. **High value, proven.** Not speculative, not "nice to have," not a theoretical pattern without evidence from a real project or an established industry practice. Evidence strength must match the claim: a mechanically reproducible defect or established practice may be proven in one pass; a recurring behavioral observation needs multiple independent occurrences. Rough gate: `Impact × Confidence / Effort ≥ 3` (each 1–5). Confidence is *how proven*, not how plausible.
2. **Not already covered.** Check the current skill files. Corroboration of an existing rule is not a change.
3. **Fits the size gate** (Article 6) after it lands.

## Article 4 — Instruction-surface classification

For changes to AI-agent instruction surfaces (skills, prompts, runbooks), classify the finding before absorbing it:

- **Structural** (required sections, markers, ownership), **Behavioral** (behaviors the prose must preserve), **Validation** (tests/commands proving the contract) → these are methodology-level; absorb them.
- **Runtime/tooling** (tool routing, model selection, orchestration policy) → usually informative but **not** methodology-level; do not absorb unless the methodology explicitly decides to change architecture.

## Article 5 — Script the mechanical, prose the judgment

A step with one correct output — scaffolding, structural/format validation, counts/coverage, a citation contract, regex transforms, git plumbing — belongs in a shared tool under `tools/`/`scripts/` that the skill *invokes*, never in prose re-derived each run and never copy-pasted per project. The test: if you could pin it with a unit test, script it; if "correct" depends on reading the situation (authoring goldens, classifying ambiguity, design taste), keep it prose. A skill reads as **natural language decides, tools execute.** When you add a tool, delete the prose it replaces.

## Article 6 — Size gate

peerreview is example-dense — each defect-class lens carries the worked evidence that *is* the rule — so its caps sit higher than the generator families', but they are ceilings, not licenses to grow. With the `evolution/` logs gone (Article 1) the skill files are the sole home and compression (Article 2) is the only counter-pressure. Caps: `skills/peerreview/SKILL.md` ≤ **1000** lines; `skills/peerreview-approach-*/SKILL.md` ≤ **800** lines; `skills/peerreview-evolve/SKILL.md` ≤ **150** lines. Over cap → compress in the same change or revert. Gate:

```sh
fail=0
check() { n=$(/usr/bin/wc -l < "$1") || { echo "FAIL: cannot count $1"; exit 1; }; [ "$n" -gt "$2" ] && { echo "OVER: $1 ($n > $2)"; fail=1; }; }
check skills/peerreview/SKILL.md 1000
check skills/peerreview-evolve/SKILL.md 150
for f in skills/peerreview-approach-*/SKILL.md; do check "$f" 800; done
[ $fail -eq 0 ] && echo PASS || exit 1
```

## Article 7 — Meta-conformance (required skill structure)

`skills/peerreview-evolve/SKILL.md` MUST contain: YAML front matter (`name`, `description`, `argument-hint`); a `## First: read the constitution` orientation that reads this file before acting; the filter loop (trigger modes → the gate → apply-or-discard); at least one GATE checkpoint (the commit-and-publish gate); and an after-completion "evolve this skill" note routing lessons back through this constitution.

`skills/peerreview/SKILL.md` MUST contain: front matter with a usage / `argument-hint` line; a `## First: read the constitution` orientation; a Step 0 preconditions/orientation step; at least one convergence GATE; and an after-completion section routing durable lessons to `/peerreview-evolve`. Validation is semantic, not exact-string — accept equivalent heading levels/wording as long as each role is present.

The `peerreview-approach-*` modules are `Read`-loaded references (no slash command, no `commands/` mirror — peerreview ships none). Cross-references between files must resolve to real paths. peerreview is a *co-editor* gate, not a read-only skill: it enforces integrity by **failing closed** (a fresh active review charter is mandatory and auto-derived from durable sources; materially ambiguous or absent intent → stop; the required Pi/DeepSeek ↔ Codex CLI peer unavailable → stop with no substitute; HOST owns git, the PEER never commits). The active charter is private temporary review state, never a duplicate contract added to the reviewed repo; a pre-existing user-authored `PROBLEM.md` is an input and is never deleted.

## Article 8 — Trust boundaries

- **Methodology evolution (`/peerreview-evolve`) — auto-apply + auto-publish allowed.** Skill-file changes are auto-applied and pushed after passing this constitution + the size gate + reference-integrity. The bar, the gate, and git revertibility are the safety net; no separate human approval (standing authorization — see Article 9 and `CLAUDE.md`).
- **The repo under review — governed by peerreview's own convergence gate, never by trust.** Every run derives a fresh active charter from the current instruction and durable project sources, every round re-reviews the real diff and re-runs the verification gate, and a dismissed PEER finding is confirmed against the cited `file:line`. Auto-derivation removes a routine confirmation stop but never permits circular intent inferred from implementation; absent or conflicting durable intent fails closed. The only gate pair is Pi authenticated by a DeepSeek API-key provider ↔ Codex CLI authenticated by an OpenAI ChatGPT subscription; either side unavailable fails closed with no third CLI or same-HOST substitute. Convergence requires active charter met + gates green + no substantive findings + explicit PEER `CONVERGED`, with a hard floor of 1 peer round.
- **Path-scoped git policy.** A repo under review that lives under `~/projects` is left uncommitted/unpushed for manual verification; `peerreview-skills` itself (in `~/personal`) is always committed and pushed. Reviewing ≠ owning: never rewrite history or delete files in a repo you did not create without an explicit instruction.

## Article 9 — Commit and publish

Every evolve change must reach `maximalfocus/peerreview-skills` on `main` — local-only commits are worthless. Standing user authorization (2026-06-13, recorded in `CLAUDE.md`) covers routine skill/evolution edits + their push; still confirm for destructive git ops. Concurrency (siblings/environments move `main` under you, working copy is shared):

1. **Stage only the paths this session changed** — explicit `git add <paths>`, never `-A`/`-u`/`.`. Leave files you didn't touch.
2. **Edit only task-coupled methodology sources/support** — `CONSTITUTION.md`, `skills/`, and directly invoked `scripts/`/`templates/` or their README documentation. There is no `commands/` mirror to regenerate (unlike cdd-skills).
3. **Rebase before committing; retry push on rejection** (`git pull --rebase origin main`, ≤3 attempts). Never force-push, never PR branches in this repo.
4. Verify the size gate; report the commit SHA. Scope of auto-publish: **this repo only** — repos under review follow the Path-scoped policy above.
