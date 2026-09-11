---
name: peerreview
description: >-
  Cross-model co-editing peer-review gate. A HOST harness and an independent cross-vendor PEER
  co-edit until a fresh active charter is satisfied and verification is green. Tier-1 peers are
  Claude Code and the Codex CLI; Pi/DeepSeek-Harness are the tier-2 fallback. The charter is
  ephemeral, convergence has a hard floor of 1 peer round and no upper cap. User-initiated,
  directly or by the user delegating it to an agent, including explicit /cdd-auto delegation.
allowed-tools: >-
  Read Write Edit Grep Glob Task Bash(git *) Bash(claude *) Bash(codex *) Bash(pi *) Bash(dsh *)
  Bash(ls *) Bash(test *) Bash(mkdir *) Bash(bash *) Bash(python3 *) Bash(ruby *) Bash(npm *)
  Bash(npx *) Bash(sed *) Bash(grep *) Bash(awk *) Bash(cat *)
argument-hint: "[repo_path] [--chat] [--dry-run]"
---

# /peerreview — cross-model co-editing peer-review gate

You are the **reviewer and manager**. The independent **PEER model** is the **co-editor**. You run a
bounded-by-convergence loop that ends only when the repo objectively solves the problem it claims to
— not after a fixed number of rounds.

This skill is **user-initiated**: directly, or by the user explicitly delegating a review to an
agent, which then runs this skill unchanged. A producer skill may suggest it but must not invoke it
on its own initiative. `/cdd-auto` is one such delegation: the user's explicit auto invocation
authorizes its mandatory per-wave calls to this canonical skill. Treat each as a normal
`/peerreview` run—never let cdd-auto imitate or bypass this workflow.

## First: read the constitution

The methodology is governed by
[`~/personal/peerreview-skills/CONSTITUTION.md`](../../CONSTITUTION.md). You do not need it to *run*
a review, but any change to this skill — and the after-completion evolution step — is gated by it
(the bar, the size gate, the trust boundaries, commit-and-publish). Durable lessons from a run are
filtered through it via `/peerreview-evolve`, never written to a log (there is none).

## Step 0.0 — Identify HOST and PEER

The HOST running this skill reviews/orchestrates and owns git, verification, fact-checking, and
convergence; the PEER only co-edits. Resolve both mechanically with
`~/personal/peerreview-skills/scripts/select-peer.sh <repo_path>` and use its exact
`HOST/PEER/DRIVER/AUTH_SIDE/TIER` result. It detects the HOST from process markers (Claude Code,
Codex CLI, Pi, DeepSeek Harness), walks the ladder below in order, and preflights each candidate's
CLI **and** auth — so it is also the peer preflight Step 0 needs:

| Tier | PEER | Selected when |
|---|---|---|
| 1 | Claude Code, Claude subscription | HOST is not Claude Code |
| 1 | Codex CLI, OpenAI ChatGPT subscription | HOST is not the Codex CLI |
| 2 | DeepSeek Harness `dsh` (deepseek-v4-pro) | no tier-1 peer **and** a `cdd-*` profile |
| 2 | Pi, `deepseek` API-key provider (deepseek-v4-flash) | no tier-1 peer, every other repo |

**The PEER vendor is never the HOST vendor.** A same-vendor pass is not a peer review — this
methodology's own evidence is that degraded same-vendor passes miss whole defect families — so a
DeepSeek HOST (Pi or `dsh`) has the two tier-1 peers and no tier-2 fallback, and a Pi HOST must
still be on `PI_PROVIDER=deepseek` because that pins the vendor the ladder resolves against. Tier 2
is a **disclosed degradation, not an equal peer**: name the tier that actually ran in the report.
Unsupported HOST, or no cross-vendor peer reachable → stop (**Required-peer failure**). A same-HOST
review is never a substitute.

## Inputs

- `repo_path` — defaults to the current working directory.
- `--chat` — review a pre-repository idea/spec supplied in the conversation. The HOST captures it as
  `ARTIFACT.md` inside a private ephemeral Git workspace; the converged artifact is returned in
  chat, then the workspace is deleted.
- `--dry-run` — produce the plan and stop; do not invoke the PEER or edit files.

## Step 0 — Preconditions (fail closed)

1. Normally, `repo_path` is a git repository. If not, stop and tell the user (offer `git init` only
   if they ask). With explicit `--chat` intent, instead create `CHAT_WORKSPACE` using `bash
   ~/personal/peerreview-skills/scripts/chat-review-temp.sh new`, capture the supplied idea
   faithfully as `ARTIFACT.md`, and use that private Git repo for driver compatibility and
   attributable rounds. The user's current instruction is durable intent; if the material to review
   is absent or materially ambiguous, clean the workspace and stop rather than invent it.
2. Peer preflight is the Step 0.0 resolution itself — `select-peer.sh <repo>` validates each
   candidate's CLI presence and auth without printing credentials (`claude auth status` reporting a
   Claude subscription; `codex login status` reporting a ChatGPT subscription; `pi auth check
   --provider deepseek`; `dsh` with `DEEPSEEK_API_KEY` and a composing headless profile), and it
   exits 69 only when no cross-vendor peer survives. Raw-API-key auth on a subscription side is not
   this contract. A resolved tier-2 peer means every tier-1 peer was unreachable — disclose which,
   and why, in the report. Usage limits or a failed/empty round mid-run are terminal blockers:
   disclose the exact failure, clean `ACTIVE_CHARTER` if created, and stop; never re-ladder to a
   different peer mid-run, which would discard the anchored session and the round history. A
   transient network failure may be re-probed once and retried fresh only after resolution is green.
3. Working tree + delivery branch: note uncommitted changes. When durable intent names a GitHub
   issue/PR, read its live state before any commit: review an OPEN PR on its head branch; a MERGED
   PR/CLOSED issue needs a follow-up branch (or a stop), never review commits on the default branch
   where Step 6 would bypass the landing gate. Unless the **Path-scoped git policy** below applies,
   commit a clean baseline before the loop so every round's diff is attributable.
4. **Create a fresh active review charter; never add review scaffolding to the repo.** Use the
   schema in `~/personal/peerreview-skills/templates/PROBLEM.md`, but create `PROBLEM.md` in a
   private temp directory with `bash
   ~/personal/peerreview-skills/scripts/charter-temp.sh new`; retain the returned path as
   `ACTIVE_CHARTER`. Derive intent in this order: current explicit user instruction → declared
   upstream source → PRD/PLAN/spec → tests/docs. Implementation behavior is evidence, never intent
   by itself. A pre-existing repo-root `PROBLEM.md` is another durable input: do not edit or delete
   it. When sources are coherent, synthesize Scope, ACs, gate, and residuals and **continue without
   a confirmation stop**. Stop after cleaning via Step 6 and ask only when sources conflict or no
   durable source states the intended behavior; silently deriving ACs from the current
   implementation would make review circular. Regenerate against current durable intent every
   run—never cache a verdict/charter or commit `ACTIVE_CHARTER`; this prevents stale duplicate
   contracts without weakening charter-first review.
5. Fetch the checkpoint with `bash ~/personal/peerreview-skills/scripts/review-anchor.sh latest
   <repo> --fetch`. No/non-ancestor anchor, changed intent, or unbounded/cross-cutting impact
   selects **full**; otherwise select **incremental** anchor→HEAD + impact closure (consumers,
   contracts, tests, docs, migrations, generated artifacts). Incremental is never diff-only: run the
   full gate and escalate if impact cannot be bounded. Under `~/projects` (tags are forbidden git
   writes), always select full. In `--chat` mode, select full and skip checkpoint fetch because the
   wrapper has no remote or prior anchor.
6. **Self-test the active charter's Verification gate before the loop:** from repo root, fix blind
   spots and enumerate durable sources, never charter prose; on a PR, diff gates cover the selected
   review range (base/anchor→HEAD), never only `HEAD^` — and "base" is the merge base (`git
   merge-base <base-branch> HEAD`, the three-dot range), never the base branch's tip: once the base
   has moved since branching, a two-dot diff shows landed work as if the PR reverted it (idd-skills
   PR #21 2026-09-09: a P1 "reverses the excluded fix" that was only the stale two-dot range).

### Chat-artifact delivery policy (`--chat`)

This is a delivery exception, not a weaker review: resolve the peer through the same Step 0.0 ladder
(the ephemeral wrapper never carries CDD markers, so its tier-2 fallback is Pi), derive the same
fresh private charter, commit an ephemeral baseline and rounds, run the same gates, and require the
same neutral PEER verdict. The artifact defaults to the `prose-spec` profile unless its content
proves a more specific profile. Never add a remote, push, create an anchor tag, or treat the
temporary wrapper as product scope. Before cleanup, preserve the final artifact and per-AC report in
the response; then run `bash ~/personal/peerreview-skills/scripts/chat-review-temp.sh clean
"$CHAT_WORKSPACE"`. Clean `CHAT_WORKSPACE` on every terminal exit, including dry-run, auth failure,
ambiguity, non-progress, and verdict-pending. When an artifact's claims are **empirical** — about a
repository, dataset, or system existing outside it — mount that evidence for the PEER (a throwaway
copy via `PEERREVIEW_ADD_DIRS`, named in the brief as evidence, never the artifact) so it can
re-derive them; without it a round tests only internal consistency and a confidently-wrong empirical
claim converges. When those claims are about a *pinned external build* rather than the working tree,
the gate must also prove **which build it ran** — assert the imported module's path, neutralise cwd
injection (`python -P`), warn the PEER of the same trap. (vvah-v1.3.0 2026-09-07: the PEER running
git there drove every reversal; a gate run beside a same-named package imported the reviewer's
already-fixed fork, reporting the defect absent.)

## Required-peer failure (fail closed)

A cross-vendor PEER from the Step 0.0 ladder is mandatory. If `select-peer.sh` resolves none, or the
resolved PEER is quota-blocked or returns no non-empty report/verdict, state the blocker and stop
after charter cleanup. Never label a HOST-only pass converged, never fall back to a same-vendor
peer, and never push review edits made without the mandatory PEER round. Resume by re-running
`/peerreview` after the named blocker is resolved.

## Path-scoped git policy (repos under `~/projects`)

If the **resolved absolute** `repo_path` is under `~/projects`, peerreview performs **no git writes
at all** on the reviewed repo: no baseline commit, no per-round commit, no `git revert`, no push, no
branch or remote changes. The user verifies and commits manually on a Windows machine. Concretely,
in this mode:

- **Step 3 baseline:** skip the baseline commit. The baseline is the current `HEAD`; record any
  pre-existing working-tree changes in the report so the user can tell them apart from peerreview's
  edits. Attribute each round with `git diff` against `HEAD` (snapshot the per-round diff to a temp
  file if needed) — never with commits.
- **Step 4.5:** do **not** commit the round. To undo a bad round, restore from `HEAD` (`git checkout
  -- <files>` / `git stash`), not `git revert`.
- **Step 5:** the "working tree clean and every change committed" clause is replaced by: *all
  intended edits are present in the working tree; peerreview committed and pushed nothing.* New
  files are left untracked.
- **Step 6:** do **not** commit or push. Leave every edit uncommitted and new files untracked. The
  report states explicitly that the repo is left for manual Windows-side verification and commit,
  names the branch, and confirms nothing was committed or pushed. This is the *expected* terminal
  state here — not a failure, so do not "fail loud" about the absent push.

This exception governs only the **repo under review**. Self-evolving `peerreview-skills` (in
`~/personal`, outside `~/projects`) is unaffected: a kept change is still proposed unconditionally,
as a PR (`CONSTITUTION.md` Article 9).

## Step 1 — Read the charter adversarially

Parse `ACTIVE_CHARTER`: Problem, Scope, Non-goals, ACs, Verification, Residuals. Check every item
traces to a durable source; the temp charter cannot invent requirements.

Treat it as a **claim to be disproved**, not a description to trust — especially when the same
generator skill wrote both the repo and the charter (self-serving risk). Where acceptance criteria
are vague or builder-invented, prefer criteria that trace to the **Source of truth** and say so in
the plan.

## Step 1.5 — Detect repo profile and load approach module

Classify the repo by file markers and load the matching approach module(s) via Read. Approach
modules supply artifact-type-specific review lenses, dominant defect classes, and verification-gate
amendments — they shrink Step 2's generic prose and let the PEER be briefed against the right defect
classes.

Modules live at `~/personal/peerreview-skills/skills/peerreview-approach-<profile>/SKILL.md`:

- `cdd-prd` — top-level `PRD.md` + ≥1 `PLAN-*.md`.
- `idd-prd` — top-level `PRD.md` + `PROGRESS.md` and no `PLAN-*.md` (evaluate after `cdd-prd`).
- `cdd-conformance` — a `conformance/` dir with `test.json` leaves, or top-level golden-file
  categories.
- `cdd-implementation` — a language manifest (`package.json`, `pom.xml`, `pyproject.toml`, `go.mod`,
  `Cargo.toml`) + a sibling `*-conformance/` or top-level `conformance/`.
- `evidence-docs` — an evidence file (`SOURCES.md` or equivalent) whose `path:line` citations point
  outside the repo + a charter Source of truth naming external repo paths.
- `knowledge-artifacts` — `context/sources.md` + `context/sources_zh.md` and at least two of
  `concept_graph.md`, `critiques.md`, `deep_dive.md`, `summary_zh.md`.
- Inline in Step 2, no module: `prose-spec` (markdown-heavy, no code, declared-exhaustive tables);
  `derived-suite` (derived from a converged upstream spec: PLAN from PRD, design from requirements,
  a tutorial roadmap from a book TOC); `source-rendered` (diagram sources + committed renders) and
  `html`, both in `~/personal/peerreview-skills/templates/PROBLEM.md`; `code` (fallback, generic
  adversarial code review).

A repo can match **multiple profiles** (e.g., a CDD implementation repo that also ships rendered
architecture diagrams). Load all matching modules; their lenses compose. If no profile matches, fall
back to `code` (generic).

Generic `code` lenses that recur across profiles (cite the run when you brief them):

- **Rule engines and state machines:** cross-product every authored state with applicability and
  assert intermediate dispositions, not only final verdicts — prerequisite abstention masks an inner
  `UNKNOWN`→`SURVIVES` trace. Open-world inputs carry several records per scope: keep identities
  distinct, aggregate the full set, probe mixed records. A scoped transition keyed on a global
  identity needs cycles split across scopes. A new catalog rule must reconcile every
  total/distribution assertion, installed-wheel CI smoke included. (ArchSift PR #40, Docscan PR #10,
  2026-08-09.)
- **Dependency injection:** instantiate every affected conditional/profile graph in the real
  framework; constructor tests and source reading do not prove bean selection. When retiring a stub,
  flag, or profile, sweep code and docs for old status markers and qualify same-named components
  across layers.
- **YAML→schema, canonical JSON, regex:** probe raw unquoted scalars (YAML 1.1 `yes/no/on/off`,
  dates), since a safe loader coerces before the schema sees them; JSON Schema treats `1.0` as an
  integer, so normalize or go numeric-free, and probe booleans, non-finite numbers, and unpaired
  surrogates in values and `propertyNames`; a `$`-anchored pattern accepts a trailing newline in
  Python `re`, so use `(?![\s\S])` where dialect and runtime must agree; `format: date-time` is
  unproved until the optional checker is active (probe year `0000`, leap days, non-leap centuries);
  heterogeneous unknown keys need a total type+representation order and a validation error, and a
  Cc/Cf-bearing key needs central terminal escaping in diagnostics. (ArchSift PR #60, 2026-08-09.)
- **Windows and CLI plumbing:** run non-ASCII paths through narrow-encoding redirected
  stdout/stderr; bound pytest IDs for huge inputs, since `PYTEST_CURRENT_TEST` exports them and
  Windows caps environment values at 32,767 characters. (Docscan PR #4, 2026-08-08.)
- **Discover→validate→mutate automation:** a failed validation is not "clean" — require validation
  first; CLI mocks must keep stdout data separate from stderr diagnostics.
- **Content-addressed persistence:** byte equality plus one path check is a narrow oracle — swap
  same-byte files and outside symlinks between check and open, replace during a read and before
  failure cleanup; cleanup must prove the path still names this attempt's file; `(device,inode)`
  recycles on ext4 and path-`lstat` vs handle-`fstat` differ on Windows, so bind with `samestat` and
  require the live OS matrix; an owning descriptor blocks `os.replace` on Windows, so verify bytes
  and a generation token while pinned, close at that boundary, recheck, replace, read back. A new
  byte-exact golden extension needs `text eol=lf` in `.gitattributes`. (ArchSift PR #38, Docscan PR
  #14, 2026-08-08/09.)
- **Narrow self-authored oracles:** make the narrowness executable — for each rule the source
  states, mutate the solution to violate it and run the suite; a passing mutant is a fixture gap
  closed by a source-derived fixture (load-balancer 2026-09-08: 12 gaps, zero code changes). Three
  probes recur: a multi-unit continuation asserting progress and final state; a reset/reclaim op
  from a grown state (memory-allocator 2026-06-28: grow-then-free-all leaked a page); a
  payload-bearing input when inputs have distinct regions (web-server 2026-07-03: a GET-only suite
  missed `wsgi.input`).
- **OSC 52 clipboard:** prove a pane-originated write cannot poison or exfiltrate the host clipboard
  while user selection still works — tmux `set-clipboard external`, not `on` (agent-sandbox
  2026-07-24).
- **Hostname classifiers:** case-fold ASCII and strip one trailing root dot before tiering, then
  parity-test near misses across implementations (agent-sandbox PR #52, 2026-08-09).
- **Layered configuration defaults:** render with process variables cleared and an empty env file,
  then with the example and explicit opt-in; mutation-flip each fallback (agent-sandbox PR #54,
  2026-08-09).

State the detected profile(s) in the plan you present at Step 2 so the user can override if the
heuristic misfires.

## Step 2 — Work out a peer-review plan (forecast, not a cap)

From the charter + repo nature/size/complexity (file count, languages, security surface, blast
radius), produce:

- **Focus areas**, ranked by risk (correctness > security > robustness > docs).
- **Per-AC review strategy** — how each acceptance criterion will be checked.
- **Verification gate** — the exact commands from the charter's Verification block you will run
  every round, plus any obvious missing tests, linters, or validators. **Compiled-language repos
  with build artifacts (`build/`, `target/`, `obj/`) require a hermetic clean build; verify `clean`
  removes every generated source, object, and binary.** In-place gates can pass on stale/foreign
  objects (macOS arm64 artifacts later failed in Linux, including a whole reused binary; `make clean
  test` fixed it, once `clean` also removed `bminor`/`scanner.c`). **Process-level performance gates
  need their own deadline:** checking elapsed only after child exit hangs on regressions. Set the
  subprocess timeout to the budget, map timeout to budget failure, then validate
  exit/output/cardinality before accepting elapsed success; mutation-test timeout, non-zero,
  malformed output, and non-finite budgets. (ArchSift NFR-005, 2026-08-07.) **For
  multi-process/container smoke gates, a producer artifact or running status proves only producer
  readiness:** wait for the consumer's post-init control state, then repeat cold starts to expose
  races. (agent-sandbox PR #51: the shared CA predated agent `OUTPUT DROP`, causing 2/3 false
  failures.) Prose-spec repos (PRD/charter/design docs, no code): the dominant defect class is
  internal cross-reference inconsistency, not code correctness — gate on reference-closure (every
  flag/term/identifier referenced is defined in its declared "complete"/"exhaustive" contract table)
  and cross-section consistency (exit codes ↔ output ↔ business rules do not contradict); treat any
  "etc." inside a declared-exhaustive list as a defect. A spec that declares its own **acceptance
  gate** gets one more check: name the producer of the evidence that gate consumes. "Not yet
  collected" is the normal state of a greenfield PRD and is not a finding; **no producer that could
  ever collect it** is — such a gate can neither pass nor fail, so the release boundary it defines
  is unreachable while the artifact reads as complete. Before concluding none exists, look past the
  source the artifact assumed to the *consumers* of the same evidence. (waypoint-prd 2026-08-29:
  acceptance demanded a zero-tolerance per-bar comparison against action strings the upstream
  platform does not export at all, making the release gate unfalsifiable; the downstream consumer
  was already receiving those exact payloads, which also settled a chart-timeframe assumption the
  artifact carried as unverified.) When the artifact is *derived* from a converged upstream spec
  (PLAN from PRD, design from requirements, test-plan from spec), add **upstream→downstream coverage
  closure** as a first-class lens: enumerate every upstream behavior/flag and confirm each maps to
  exactly one downstream unit (or an explicit non-goal), and that no downstream unit lacks an
  upstream origin — an unmapped upstream behavior is the dominant defect class there, not internal
  inconsistency. For derived **golden-file / test suites** specifically: (a) reconstruct closure as
  an *executable* gate script (reuse the authoring validators) and run it at baseline — a
  self-authored coverage doc is not evidence until a script confirms disk ⇔ doc bijection; (b) if
  the suite ships its own coverage/trace artifact, gate that it enumerates every downstream unit
  **individually** — grouped/abbreviated IDs (`FOO-002,003,008`) silently defeat machine closure and
  are a defect; (c) recompute every pure/`function` expected value from the upstream algorithm
  rather than only checking it parses. (c-bis) a **tutorial-roadmap `PLAN.md`** (planning stage,
  derived from a book/web TOC, no code) gets the coverage-closure lens alone, but its gate has
  learned quirks: parse `- [ ] NNN — <title> (<branch>)` taking the LAST `()` group as the branch
  (titles carry their own `(...)`/`§` pointers) and tolerate a trailing `← current` marker; match
  concept sentinels the same way — bounded phrase predicates or a distinctive issue anchor, never
  one contiguous title string a harmless parenthetical would split. (c-ter) pin an executable
  closure gate's expected unit count to the source of truth, never to the artifact (`range(1,
  len(items)+1)` is blind to an appended `037` or a truncated tail — mutation-test both boundaries
  at baseline); but pin only a count the source genuinely enumerates (chapters, declared `001..N`),
  never a decomposition choice such as issues per chapter, which overfits and fails a legitimate
  re-split — there keep numbering to the pure invariant (unique, contiguous, N free) and put
  whole-unit coverage on concept/dependency closure (raytracing 2026-06-06 pinned `EXPECTED=36`;
  rasterization 2026-06-06 reverted `EXPECTED=16` for contiguity + closure). Concept sentinels: a
  token not contained in an umbrella term (`"encod"` is inside `"bEncoding"`; use `"encoder"`),
  matched as a whole word against the phase BODY, never its title, and never a domain-ubiquitous
  word (`"block"` matches everything; gate `"NewBlock"`); when the charter duplicates the gate's
  concept list, make the gate's table authoritative and parity-check the prose. Mutation-test EVERY
  section drop exhaustively, renumbering contiguously so AC2's gap check cannot mask AC1's closure;
  a round that adds forward-reference prose can newly mask other concepts (bittorrent 2026-06-06: 19
  drops found 5 blind spots a sampled self-test missed); when siblings share vocabulary, anchor the
  sentinel on the issue's canonical branch slug, and bound section-specific prose sentinels to their
  section. A phase-ordering check derives membership from the UNION of the `## Phase N` header and
  the closure predicates — each alone is evadable — and a predicate relaxed to feed the union keeps
  a context anchor (bittorrent 2026-06-06 R4; blockchain-in-go 2026-06-07: four maskings over 4
  rounds that two same-vendor passes missed). (c-quater) a roadmap with an AWS deploy phase must
  contain its deploy issues inside the Deploy block in dependency order (IaC → e2e suite → CI/CD
  workflow → capstone), the workflow issue authoring the full
  `apply→sync→invalidate→e2e→destroy(if:always)` lifecycle and the capstone executing it once;
  containment checks are a family — harden every phase kind in one sweep (3d-soft-engine
  2026-06-06). The branch `test/e2e` is valid: the no-numbers rule bans issue-number tokens, not
  digits inside a word; tokenize on `/_-` and flag only an all-digit token. (d) when the charter's
  **verification gate is itself the deliverable** (a self-authored ADR/boundary-rule or golden-file
  charter whose gate greps or parses the artifact), the gate is self-serving and the PEER will
  mutation-test it; on the FIRST false pass do one comprehensive hardening sweep — anchor every
  grep, match full-identifier boundaries, parse structured formats with a real parser, require
  paired/path-correct fields, never let a check repair what it asserts (regenerate out-of-tree and
  compare), and enumerate the transform's other consumers (cdd-skills 2026-09-07: CONVERGED on a
  state the unrun pre-push hook refused) — per-regex patching burns ~3 rounds
  (raytracer-architecture 2026-05-31). Two false NEGATIVES manufacture findings: `producer | grep
  -q` under `pipefail` returns 141 on a match (spool to a file), and an assertion carrying its own
  copy of a quotation leaves the artifact out of the loop — extract each claim FROM the artifact and
  verify THAT (idd-naming-standard 2026-09-02). Hardening also moves the accept boundary: execute
  each tightened check on a realistic positive case (system-skills 2026-09-07: three tightenings
  began rejecting valid work). When the deliverable is mechanically reconstructible from its source
  (a transcription under a fixed header, a doc2md table), the sweep is a whole-file byte-exact
  reconstruction diff, reached for on the first false pass (doc2md 2026-07-09: rounds 3–6 were pure
  gate-hole escalation). (e) **Math/renderer architecture repos** (ADRs pinning a rasterizer,
  raytracer, physics, codec): the dominant defect is convention-direction inconsistency, invisible
  in prose — re-derive every comparator direction, strictness, bound, and the metric/counting model
  against the citing golden AND the faithful reference (tinyrenderer 2026-06-05: a shadow-bias
  inequality literally backwards). Time/unit granularity is a distinct axis where the golden alone
  gives false confidence: a whole-second predicate over a millisecond store passes either formula,
  so settle by execution against the real clock at each layer's grain (x402 2026-07-12: `EXPIREAT
  validBefore+1`, refuted twice via the golden, proved by execution). After an ADR-wording fix,
  sweep the citing suite's descriptions for the old wording; after a promotion by an acceptance/demo
  artifact, sweep the repo's own conformance-only assumptions (lazy-promotion sentence, "Pinned by"
  column, charter "Current state", the ADR's own `## Related` tense) in ONE round (lrucache,
  semaphore 2026-06-16). A counting-term conflation is seeded upstream and inherited by ADR, PLAN,
  and diagram: fix every restatement and re-derive the definition across all ops in one round; a
  diagram's worked-example values are self-serving like any golden — recompute them (bloomfilter
  2026-06-16: fabricated FNV-1a bit positions). Missing-ADR discriminator: a PRD NFR with no citing
  golden and no real trade-off is review-only — tighten the wording "ADR" → "code review" at every
  restating site rather than add an uncitable ADR (semaphore 2026-06-16). An architecture repo ships
  deliverable infra (`rules/*-boundaries.yaml`), so run the leaked-`</content>`-tag sweep and parse
  every shipped YAML/JSON with a real loader (semaphore 2026-06-17: CONVERGED with a leaked tag in
  10 ADRs and an unloadable boundaries.yaml).
- **Round forecast** — an *estimate* (e.g. "small/internally-consistent → ~1; large multi-language
  with security surface → 3–5"). This is shown to the user for transparency. **It is never the
  termination condition.**

Present the plan. On `--dry-run`, clean `ACTIVE_CHARTER` with the Step 6 command and stop.

## Step 3 — Baseline

Unless the **Path-scoped git policy** applies, commit any pending state as a clear baseline
(`peerreview: baseline before round 1`) so each round's `git diff` is clean and attributable. You
own all git operations for the entire loop. The PEER never commits or pushes.

**Review on a branch; land one commit.** Round commits are review evidence, not product history.
Unless the **Path-scoped git policy** or `--chat` applies, or durable intent names an OPEN PR whose
head branch is already the review target, start the loop with `scripts/delivery-branch.sh start
<repo> <slug>` and land it as a PR in Step 6 (standing user preference, asked on three consecutive
runs 2026-08-18/19). Never switch a checkout that installed skills resolve into: `start` then opens
the review branch in a sibling worktree it prints, and an OPEN PR's head branch goes into one too.
Run the loop and land from there, so the install keeps serving its base (idd-skills 2026-09-11: an
in-place review served its round edits to every session on the machine for the whole review).

## Step 4 — The convergence loop

**Mandatory PEER round (user durable directive, 2026-05-18).** Every `/peerreview` run — first run
*or* re-run, regardless of whether the HOST's static pass found anything — MUST execute **at least
one** cross-vendor co-edit round. **Never converge at round 0.** The independent second-model pass
is a deliverable in itself (the whole point of the co-editor design), not "invented work": even with
no HOST-found defect, the PEER is briefed to do an independent adversarial review and may make
warranted minimal edits or confirm clean. The earliest a run may converge is **round 1**. The HOST
remains the orchestrator: owns git, verification, fact-checking, and the convergence decision; the
PEER co-edits only.

**Keep the PEER review independent — don't hand it your agenda (user directive, 2026-05-23).** Brief
the PEER to form its **own** findings adversarially from the charter; do not lead with your findings
list as the things to check (that turns the independent pass into a confirm-my-work pass). State the
self-serving risk explicitly when the same model produced both the artifact and any prior review,
and tell the PEER to treat the green suite / prior review as a claim to disprove. For the
independent pass on a self-serving or already-"converged" repo, prefer a **fresh PEER session**
(round `1`/`--fresh`) over resuming the anchored one — a resumed session carries its own prior
"looks good" context. orderflow-go (2026-05-23): resuming + leading produced a 1-round false
convergence; a fresh session + neutral brief found 6 real defects.

**Re-runs.** A convergence tag is a progress/history anchor, not a cached verdict. Incremental
briefs name anchor→HEAD paths and require independent impact closure without re-reading unrelated
stable subtrees. Full/no-change runs probe the whole/deeper tree. Mandatory round + full gate run in
either mode.

**Un-runnable gate.** When the charter's executable gate cannot run here (air-gapped registry,
missing infra), do **not** defer the whole gate to a residual and move on — reconstruct *each*
gate's verdict statically: a coverage gate → enumerate every measured (non-excluded) class and
confirm a test exercises its branches, and verify the exclusion *mechanism* (e.g. JaCoCo natively
skips a class carrying a RUNTIME-retained annotation simple-named `Generated`) rather than trusting
the charter's "legitimately excluded" wording; an SCA/dependency gate → reconcile the charter's
claimed CVEs/components/versions against the raw scanner output (counts and coordinates), then
reason the dependency-mediation precedence explicitly. Only the *executable confirmation* is the
residual; the verdict is still reviewed.

Repeat rounds until the **Convergence contract** (Step 5) holds. Each round:

1. **Review** against the charter in the selected mode: whole tree, or the anchor→HEAD delta plus
   impact closure. Walk affected ACs, hunt correctness and security first, and run the full gate.
2. **Write findings** to a temp prompt file: include the complete current `ACTIVE_CHARTER`, then
   concrete file-specific findings ranked and tied to an AC or defect class. Restate: minimal edits,
   no commit/push, run and report the gate. The PEER may challenge traceability; the HOST revises
   the temp charter, never the repo, unless the durable source itself is defective.
3. **PEER co-edits**: run the `DRIVER` Step 0.0 resolved —
   `~/personal/peerreview-skills/scripts/<DRIVER> <repo> <prompt> <out> <round>`. Every prompt
   restates no-commit/push. Pass `1` for a fresh first session and `2`+ to continue it. Reference
   the script by this absolute repo path—only `SKILL.md` is symlinked into the skill directory.
   `dsh-round.sh` has no session resume, so every `dsh` round is fresh: its prompt must stay
   self-contained. If the driver is unreachable or returns a failed/empty result, apply
   **Required-peer failure**; do not improvise an inline or different-CLI path.
4. **Re-verify independently**: read the real `git diff HEAD` AND `git status` (for new untracked
   files the PEER created — `git diff HEAD` only shows tracked changes; a new `Dockerfile` or
   generated file is invisible to it) — do not trust the PEER's self-report. **Read the diff only
   AFTER the round-driver process has exited** — never on the report appearing (the driver now
   withholds it until exit): Codex can finish a session, emit its report, then roll into a second
   session on the same prompt that keeps editing (build-redis 2026-09-08: a commit cut at the first
   report left four fixes to land during the verdict, misattributed to the read-only PEER). A
   mid-flight tree also shows try-then-revert experiments as phantom "regressions" (2026-06-06
   raycaster-cpp: a `wallSlice` `== 0`→`!= 0` experiment, reverted before its CONVERGED, cost an
   adjudication). Re-run the full gate. Check no regression and no new defect was introduced.
   **Fact-check claimed "corrections"**: the PEER may present a *regression* as a fix with confident
   wording (e.g. renaming a valid identifier/API/config element to a non-existent one and calling it
   a casing fix). Verify renamed names against authoritative knowledge, not just that the diff is
   minimal and in-scope. **A PEER factual claim about a gate-derived quantity (test count,
   pass/fail, coverage) is UNVERIFIED when the PEER could not run the gate** — its process/tool
   environment may lack daemon, socket, or network access, so a containerized/network-fetching gate
   can fall back to eyeballing (and miscounts). Settle any such number with the HOST's authoritative
   tooling (`cargo test -- --list`, the real gate), and resolve a NOT-CONVERGED verdict premised
   solely on such a miscount by re-dispatching the verdict with that enumeration as neutral evidence
   — never edit the artifact to match the PEER's wrong count, and never treat the wrong-premise
   NOT-CONVERGED as a real residual. **Version-currency disputes** (latest stable, GA vs EA, "X is
   deprecated") are settled against a LIVE registry, never either model's training belief: Adoptium,
   the live `repo1.maven.org/.../maven-metadata.xml` (not the stale `search.maven.org` index),
   `endoflife.date`, `npm view <pkg> dist-tags.latest` (not deps.dev/Snyk), the PyPI JSON API. A
   C-extension on a bleeding-edge interpreter needs a wheel for the exact (ABI, platform) or a
   compiler, and an `abi3` wheel covers every newer CPython — never flag a missing `cpNNN` it covers
   (3d-modeller, tutorial-augmented-reality 2026-06-06). Record the registry source in the artifact,
   not a bare "verified" (3d-soft-engine 2026-06-06: an uncited `vite 8.0.16` was flagged twice); a
   hermetic gate should require a registry citation in every externally-pinned tool row and never
   hardcode the version (cgfs 2026-06-06). Confirm the PEER stayed in scope. **Fidelity charters**
   (faithful reproduction / port / spec-match — e.g. a tutorial reproducing a book): the
   in/out-of-scope line is whether a finding affects a **valid** input. A silent
   miscompile/misbehaviour of a *valid* program is in-scope — keep the fix. A guard against
   pathological/malformed input the source *deliberately omits* (overflow on absurd operand counts,
   runaway recursion, corrupt bytecode) is out-of-scope — revert it and record as a residual, even
   when the bug is real; applying it makes the artifact diverge from the source it promises to
   reproduce. **State this scope rule in the PEER round brief** (not just apply it as reviewer
   afterward): briefed with it, the PEER self-classifies source-omitted hardening as a residual and
   leaves it un-edited, sparing the post-hoc revert. (2026-05-26 introduction-to-compilers KEPT 10
   valid-program miscompiles; 2026-05-27 writing-a-compiler-in-go REVERTED 3 malformed-input guards
   [brief lacked the rule]; 2026-05-28 writing-an-interpreter-in-go — briefed with the rule, Codex
   self-classified the lone residual [user-fn arity], zero reverts.) **Docs-honesty overclaim
   (highest-yield lens on a tutorial/generator-produced fidelity charter, where the same skill wrote
   the code AND the self-serving charter).** The code faithfully reproduces a deliberately-limited
   design, so the dominant defect is often a PROSE OVERCLAIM in the ACs/README, not a code bug — a
   capability-breadth claim ("any X", "and other Y"), an enforced-sounding behavior bound ("~2:1
   aspect"), or a scope claim ("the full pipeline"). The reproduced happy-path suite structurally
   cannot catch it; only the cross-vendor pass can. Enumerate every such claim and prove the
   faithful code+tests actually back it, else reword to the exact reproduced behavior + a residual.
   Corollary: when the PEER proposes an edit that TIGHTENS the faithful code toward the overclaim
   (adds an aspect band, flips strict→inclusive bounds to match a docstring), that is a divergence
   to REVERT — fix the charter prose, keep the faithful code. (2026-07-02 template-engine "any
   expression"/"other keywords" reworded; 2026-07-03 license-plate-recognition — Codex added an
   aspect band + inclusive char bounds to match AC prose, both reverted as divergences and AC6
   "~2:1"/AC13 "full pipeline" scoped honestly instead.) **Third case — a valid-input misbehaviour
   that VERBATIM-reproduces a source which itself leaves the feature incomplete/abandoned is a
   residual, not a fix.** "Valid-input misbehaviour = keep" assumes a *correct* version exists in
   the source to converge on; when it does not, decide by three checks: (a) does the repo's code
   match the source's published listing verbatim (not a reproduction divergence)? (b) does the
   source explicitly leave this feature unfinished / declare itself abandoned? (c) would the fix be
   substantial *original engineering* rather than a surgical correction? All three yes → record a
   residual and scope the charter's AC honestly (Lens-8 docs-honesty); do NOT diverge by
   re-implementing the source's unfinished feature. The decisive question is always "does the repo
   diverge from the source?" — a verbatim match of an incomplete source IS faithful, and the
   incompleteness is the residual. Contrast a *surgical* correction, or a fix that restores the
   source's own established intent, which is KEPT. (2026-06-06 lets-build-a-simple-database: a
   neutral Codex verdict gave a real 249-key wrong-`select`-order counterexample, but
   `internal_node_split_and_insert` matched the abandoned cstack tutorial's Part-14 listing verbatim
   ["no longer under active development"] → headline residual, AC scoped to the tested 7-leaf case;
   the SAME run KEPT a surgical 3-line duplicate-key fix that restored the tutorial's own
   cursor-based read direction.) **When the source ships a companion reference repo** (increasingly
   common — `/tutorial` now `curl`s reference `.py`/`.go`/… files for byte-exact code), make "does
   the repo diverge from the source?" an *executable* lens instead of reading every file:
   AST-compare each copied top-level symbol against the upstream module (`ast.dump(node)`
   structure-only — ignores formatting/comments/docstrings; identical dump ⇒ faithful, any
   divergence ⇒ inspect, with intentionally-modified symbols excluded from the set). One pass
   exhausts the extraction-fidelity lens and catches the silent line-drops that line-range (`sed
   -n`) extraction is prone to — far more reliable than spot-reading. (2026-06-06
   build-a-large-language-model-from- scratch: an AST sweep of all ~30 copied symbols across 8
   modules returned ALL FAITHFUL in one command, proving no slip beyond the two caught during the
   build; the lone Codex fix was an AC6-justified `check_if_running` robustness edit, KEPT.) **When
   the fidelity charter names TWO sources of truth that DISAGREE** (a primary tutorial/blog + a
   secondary companion repo whose code drifted from the prose), the repo may have faithfully
   reproduced the WRONG one — re-derive every disputed constant/operation against the charter's
   *named-primary* source, not whichever the impl happened to follow. A value matching the secondary
   while contradicting the primary is an in-scope fix toward the primary, NOT a faithful residual.
   (2026-06-28 tutorial-game-defender-rust: the impl took `score += 20` / `health -= 1` from the
   companion repo `v0.1.0`, but the charter's primary source — the blog — uses `score += 10` /
   `health = 0`; Codex's round-1 fix aligned to the blog and the `= 0` form also removed a real
   `u32` underflow panic on two-bullets-one-enemy. Settle the value against the raw primary source,
   e.g. de-tag its HTML, not either model's recollection.)
5. **Commit the round**: `peerreview: round <N> — <one-line summary>`; but when the reviewed repo
   declares a commit-subject convention (`CLAUDE.md`/`AGENTS.md` types, commitlint) it binds every
   branch commit and the PEER's verdict reads them, so compose in that convention keeping `round
   <N>` (`chore(peerreview): <summary> in round N`); reword only unpushed commits, a pushed one is a
   residual (idd-skills 2026-09-09: an 87-char `peerreview:` subject cost a NOT CONVERGED round).
   Co-author HOST reviewer + PEER co-editor, naming the actual two models and tools. If a round
   makes things worse, `git revert`/reset to the prior round commit and re-issue tighter findings.
   *(Under the Path-scoped git policy: do not commit; undo a bad round via `git checkout`/`stash`
   from `HEAD` instead.)*

**Bound a round that cannot finish inside the driver deadline.** The driver writes `<out>` only when
the round *ends*, so a killed round is total loss — and a mid-flight tree cannot be trusted (Step
4.4). Three briefs prevent most kills: **no network** (no `pip`/`uv`/build; a claim only settleable
by building is itself a finding — record it and move on); **where the source of truth is** — an
unmounted source is "not on this machine, do not search outside the repo", or the PEER hunts the
host for it (build-redis 2026-09-08: round 1 spent its 30 min `rg`-ing `~/personal` and
`/private/tmp` for the course; round 2, so briefed plus a report-by-minute-N budget, finished in
11); and **append each verified finding to a `FINDINGS.md` the moment it is verified**, never
batched, so a kill still yields a report. If it still overruns, split by explicit file scope and
feed each later half the prior half's accepted findings. (vvah-memo 2026-09-08: two 25-min rounds
died unreported; the third, briefed, returned 22 findings. doc-portal 2026-08-19: two bounded halves
finished where one was killed.) **A killed round's edits are disposed of, never adopted** — snapshot
the diff outside the repo, reset to baseline, say so in the report. Expect the tree to look
*finished*: a killed round can leave the whole gate green (jwt-library 2026-09-06: monthly cap
mid-round, 13 files edited, gate green including its own probes, no report).

**Non-progress abort:** if a round produces no substantive improvement against open findings (or
oscillates), stop the loop and report — do not keep spending. This is the safety valve in place of a
hard round cap.

## Step 5 — Convergence contract (the only stop condition)

The loop ends when **all** hold (and never before **round 1** — the mandatory PEER round in Step 4
must have run and been independently re-verified):

- Every acceptance criterion in `ACTIVE_CHARTER` is met and you can point to durable-source and repo
  evidence.
- The full verification gate exits clean.
- You (reviewer) have **no remaining substantive findings** (correctness or security), AND each
  review lens you opened in Steps 1–2 has been *exhausted*, not just sampled. "Opened a lens, found
  one defect, fixed it, moved on" is the failure mode user pushback corrects — convergence requires
  sweeping each lens systematically. For non-trivial codebases the deeper sweep typically includes:
  enumerate every placeholder / wildcard zone (not just the first one that paid off); `go test -race
  -shuffle=on -count=N` (or stack-equivalent) for flake / order dependence; *execute* residual ACs
  (e.g. container builds) instead of only reading their contract; scan for structurally-duplicate
  codepaths one tested at the function boundary while the other actually runs in production; probe
  undocumented env-var / global coupling. Cosmetic-only nits do not block.
- The working tree is clean and every change is committed. *(Path-scoped git policy: instead — all
  intended edits are present in the working tree and peerreview committed/pushed nothing.
  Chat-artifact mode: commits are ephemeral evidence only and are removed with `CHAT_WORKSPACE`
  after delivery.)*
- **The PEER has explicitly returned CONVERGED** in a final verdict prompt (user durable directive,
  2026-05-21). After the last edit-round, send the PEER a verdict-only prompt (no edits permitted)
  asking for either `CONVERGED — no substantive defects remain` or `NOT CONVERGED — round N+1
  needed, [defects listed]`. Run the resolved PEER's read-only verdict with `<DRIVER> <repo>
  <verdict> <out> --verdict` (Step 0.0). Verify the diff stays empty; `dsh-round.sh` asserts that
  itself — because the harness has no tool allowlist — and fails the round if the tree moved,
  leaving the mutation in place for you to adjudicate rather than reverting the review out from
  under you. The HOST no longer declares convergence unilaterally — even a clean gate +
  reviewer-judged exhausted lenses is insufficient if the PEER still sees residuals. If the PEER
  returns NOT CONVERGED, dispatch round N+1 against its named defects and repeat the verdict prompt
  after. Continue until the PEER says CONVERGED on the committed state. This codifies the
  "second-model agreement" the mandatory PEER round was supposed to provide but did not — running
  one edit-round once and not asking for an explicit verdict is the failure mode this rule corrects.
- **The verdict prompt MUST be neutral — no anchoring (user directive, 2026-05-23).** Present only
  raw, neutral facts (the gate's actual command output) and explicitly invite the PEER to find more;
  do NOT pre-load your own conclusions ("all green, lenses swept clean, README honest, no
  findings"). A leading verdict biases the PEER toward agreement and manufactures false-fast
  convergence (orderflow-go, in full under "Keep the PEER review independent"; the neutral re-review
  also refuted 1 PEER-proposed regression). One round on a self-serving repo is a yellow flag —
  re-prove neutrally, do not rubber-stamp.
  - **A peer usage-limit error during the verdict prompt is a "verdict-pending" residual, not a
    silent CONVERGED** (student-mgmt-conformance 2026-05-29): a transient external failure, not a
    NOT-CONVERGED outcome. Do not fabricate a verdict, treat reviewer-side green as one, or loop
    while waiting (hours, or weeks on a monthly cap). Commit reviewer-applied edits, push per Step
    6, record verdict-pending with the reset time the CLI returned, and tell the user to re-run
    `/peerreview` after it; never re-ladder to another peer while the resolved side is blocked.
  - **The verdict prompt must make READING explicit, in its first paragraph, every time** — a
    read-only sandbox still permits reading every file and running read-only commands; "do not run
    commands" means no mutating commands, not "cannot read". A NOT CONVERGED premised on "review is
    impossible because I may not run commands" is a wrong-premise verdict (same class as the
    gate-count miscount above): re-dispatch once with the permission restated, never treat it as a
    residual, never edit the artifact to satisfy it. It recurs when the line is shortened
    (CC-Sandbox 2026-08-09; vvah-memo 2026-09-08 verdicts 8 and 10, cleared by the same preamble).

Anything not fixable without changing host state / running real infrastructure / external review is
**not** a blocker — it is recorded as a residual, not papered over.

**A residual's blast-radius claim is itself a defect surface — sweep the whole residual set when a
verdict flags one, and settle behavioral disputes by execution, not argument.** Two recurring
failure modes here: (1) *overclaim cascade* — when a verdict round flags one mis-scoped claim (a
residual's "it's display-only / can't affect balances / isn't reachable", an AC's "X validates and
applies", a goal's "pins every behavior"), scope the fix to the WHOLE paragraph / named section /
residual list and re-audit every parallel claim in the same pass; a verdict catching one is evidence
the surrounding prose makes the same mistake at another surface, and fixing only the cited one burns
the next verdict round (recurred across cdd-prd, cdd-conformance, and fidelity-impl profiles). Each
blast-radius claim must be re-derived against the actual call path, not asserted. (2) *execution
tiebreaker* — when HOST and PEER disagree on what code does at runtime (e.g. "the reversed decode is
display-only" vs "it changes settlement", "a negative amount steals" vs "it aborts at the encode
assert"), **run it** in the gate environment and quote the output; both models' confident reasoning
can be wrong at once, and only execution is authoritative. A behaviour-PRESERVATION claim ("this fix
is a no-op except where it aborted") is the same surface with a mechanical check: extract the
artifact at the pre-review commit and run BOTH versions over one input matrix. Reasoning about the
diff misses the boundary a tightening moved silently — the inputs the language coerced rather than
rejected. (2026-09-07 tutorial-build-a-jwt-library: a NOT CONVERGED verdict said the claim died on a
restored default; differential execution showed that default WAS a no-op versus what shipped, and
the claim died instead on JSON booleans, which Python's bool-is-int had let the original silently do
arithmetic on. Both sides were partly wrong; only running both versions said which part.) (3)
*residual laundering* — rewording an artifact to admit a defect is not fixing it. When a verdict
says a gate cannot detect X, "the gate now says it cannot detect X" is documentation, and the next
verdict repeats the finding. Ask whether X's CAUSE is removable inside the charter's scope before
reaching for the honest-scoping rule; that rule is for causes you do not own, which is why a
source-fidelity residual is right — its cause lives in the reproduced source. (2026-08-19
doc-permit: a fidelity gate could not see visual drift between the committed PPTX and PDF because
renders looked nondeterministic, and two rounds went into loosening the tolerance and then
disclosing the gap. The cause was two labels styled italic in a face with no italic, so LibreOffice
synthesised an oblique differently per run; dropping that one style made 6 renders 210/210
pixel-identical and an exact oracle valid. The PEER refused "we disclose it" twice before the cause
was looked for.) (4) *the source is more than its prose* — "the statement doesn't say" is only
irreducible after checking the source's NON-prose surfaces (starter code, skeletons, TODOs,
fixtures), which often carry the intent the prose omits — but they lose wherever the prose speaks.
(2026-09-06 build-an-oauth-2.0-server: a residual said the exercise never states what STATUS reports
after revoking a never-issued token; its starter's `mark this token inactive (if known)` made it a
real defect, while that starter's own UNKNOWN print lost to the statement.)

## Step 6 — Report & push (always)

Produce an honest report:

- Per-AC status (met / met-with-caveat / not met + why).
- **HOST/PEER and the peer tier that actually ran.** On tier 2, name every tier-1 peer that was
  unreachable and why — an undisclosed degradation reads as a full-strength review.
- Rounds actually run vs forecast, and why it converged or aborted.
- Verification gate output.
- Residuals (explicitly out of scope; not "perfect", and say so).

When Step 1.5 detected a `cdd-*` profile, **finish every terminal report by rendering the canonical
CDD progress map** from `~/personal/cdd-skills/skills/cdd/SKILL.md` § Progress map. `/peerreview`
owns this update because only it knows the terminal review outcome: explicit cross-vendor
`CONVERGED` → `✓ reviewed` (tier 2 still counts, with the tier named); required-peer failure,
verdict-pending, or non-progress abort → `☐ review owed`. Never advance the project's `PLAN.md`
lifecycle status merely because its repo review finished.

Before the terminal report, always clean review-owned charter state with `bash
~/personal/peerreview-skills/scripts/charter-temp.sh clean "$ACTIVE_CHARTER"` (on convergence,
required-pair failure, non-progress abort, dry-run, or error). A pre-existing repo-root `PROBLEM.md`
is not review-owned and is never removed.

On convergence, land a branch-mode review with `scripts/delivery-branch.sh land <repo> <slug>
<msgfile>` — one squashed commit on delivery branch `evolve/<slug>` whose first non-blank line
`land` preflights as the N-4 subject; `land` pushes that branch, opens (or reuses) its PR against
the base branch (title = subject, body = message body), prints the PR URL, and never writes the base
branch — then create/push the anchor tag. Only `bash ~/personal/idd-skills/scripts/land-evolution.sh
<PR>` on the maintainer's explicit instruction merges it, never this run. The review branch is kept
locally; its round commits remain the detailed record.

Then **always commit and push the reviewed repo** — every run, on convergence *or* non-progress
abort, without asking. Push the working branch to its tracking remote and state the branch/remote in
the report. Fail loud: if there is no remote, the push is rejected, or auth fails, report it
explicitly — never silently skip the push. (This is unconditional because the user durably asked for
it; do not re-prompt.) **Exception:** under the **Path-scoped git policy** (`~/projects`), do the
opposite — do not commit or push; leave edits uncommitted/untracked and say so plainly. The absent
push there is the expected outcome, not a failure to flag. **Chat-artifact exception:** no remote,
push, or anchor is created. Return the reviewed artifact and report, clean both `ACTIVE_CHARTER` and
`CHAT_WORKSPACE`, and state that the review was ephemeral.

After true cross-vendor convergence (not abort and not `--chat`), run `bash
~/personal/peerreview-skills/scripts/review-anchor.sh create <repo> <full|incremental>`; push the
returned tag exactly. It marks the reviewed commit; round commits retain detail. Under `~/projects`,
create no tag.

Never claim "perfect" — claim "converged against the charter, gates green, residuals listed."

## After completion: evolve the methodology (no logs)

peerreview evolution is a **filter, not a per-run log** (`CONSTITUTION.md` Article 1): a lesson
either passes the constitution and is edited into a skill file, or it fails and nothing happens.
There is no `evolution/` log to append to, and no every-run self-evolve+push (which is why the old
cross-environment / concurrent-sibling race apparatus is gone).

If this run surfaced a **durable, generalizable** lesson — a review lens that paid off, a recurring
defect class the gate structurally missed, a skill bug or stale path — invoke
**`/peerreview-evolve`** (post-review mode). It filters the candidate through `CONSTITUTION.md`
(proof matched to the claim's scope), edits the matching `peerreview-approach-*` lens or main Step,
validates the size gate, and proposes a PR. A one-off `CONVERGED, no durable lesson` run evolves
**nothing** — the trigger is pull-based, so a non-actionable run simply leaves no trace. The git
history of the skills is the record; never re-create a patterns/index log.

## Hard rules

- The HOST owns git. The PEER co-editor never commits, pushes, or touches remotes.
- The PEER is whatever `select-peer.sh` resolves: tier-1 Claude Code ↔ Codex CLI, falling to tier-2
  `dsh` (CDD-harnessed repos) or Pi (all others) only when no tier-1 peer is reachable, and never to
  the HOST's own vendor. Any missing/auth/quota blocker fails closed; no same-HOST substitute (Step
  0.0).
- Every round: review the real diff + re-run the gate. Never trust self-reports — including
  fact-checking any identifier/API the PEER claims it "corrected".
- **Any live finding you DISMISS must be verified against the cited line — the PEER's, *and one you
  raised yourself*.** Never wave it off as "a misread" or "out of (edit) scope." A finding pointing
  at a *sibling* repo outside your edit scope still has to be confirmed/refuted by reading the exact
  file:line, then recorded as a flagged cross-repo defect if real — not silently dropped; a wrong
  dismissal persists the defect until the sibling is reviewed directly. (2026-06-18 mvcc-prd: a
  Codex finding that `mvcc-conformance/gc/README.md` claimed "tombstone collapses chain /
  reclaimed=2" was refuted as a misread + out-of-scope; the direct review a day later confirmed both
  stale claims — the dismissal was the error.) **A finding YOU surfaced and then resolved in your
  own favour goes into the verdict prompt as an open question, never omitted as settled**: give both
  readings and say plainly the PEER is not asked to agree. One contested item with an explicit
  invitation to disagree is not an agenda handoff (ArchSift 2026-08-15: a self-dismissed redaction
  gap, surfaced as an open question, returned NOT CONVERGED and landed NFR-009).
- Fail loud and closed: auto-create a fresh active charter; absent or conflicting durable intent →
  stop, never infer it from implementation. Missing peer/auth, quota, or empty output → disclose the
  blocker and stop after charter cleanup.
- Rounds are forecast for transparency; **convergence**, not a count, ends it — but with a hard
  **floor of 1** peer round (Step 4 mandatory round; never converge at round 0).
- "Ready" = charter satisfied + gates green + no substantive findings. Not "perfect".
- **Methodology evolution is a filter, not a log** (`CONSTITUTION.md` Article 1): no `evolution/`
  log, no every-run self-evolve+push. A durable lesson is routed through `/peerreview-evolve`, which
  gates it against the constitution and proposes a PR; a non-actionable run leaves no trace.
- Every repository run ends by pushing the reviewed repo (fail loud if a push cannot complete).
  **Exceptions:** under the **Path-scoped git policy** the *reviewed repo* is never committed or
  pushed (left for manual Windows-side commit). **Chat-artifact mode is also non-publishing by
  design:** its private wrapper is deleted after the converged artifact is returned. Evolving
  `peerreview-skills` is separate and pull-based, not part of every run — see § After completion.

$ARGUMENTS: optional `repo_path` (default: cwd), `--chat`, and `--dry-run`.
