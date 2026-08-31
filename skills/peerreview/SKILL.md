---
name: peerreview
description: "Cross-model co-editing peer-review gate. A HOST harness and an independent cross-vendor PEER co-edit until a fresh active charter is satisfied and verification is green. Tier-1 peers are Claude Code and the Codex CLI; Pi/DeepSeek-Harness are the tier-2 fallback. The charter is ephemeral, convergence has a hard floor of 1 peer round and no upper cap. User-initiated, directly or through explicit /cdd-auto delegation."
disable-model-invocation: true
allowed-tools: Read Write Edit Grep Glob Task Bash(git *) Bash(claude *) Bash(codex *) Bash(pi *) Bash(dsh *) Bash(ls *) Bash(test *) Bash(mkdir *) Bash(bash *) Bash(python3 *) Bash(ruby *) Bash(npm *) Bash(npx *) Bash(sed *) Bash(grep *) Bash(awk *) Bash(cat *)
argument-hint: "[repo_path] [--chat] [--dry-run]"
---

# /peerreview — cross-model co-editing peer-review gate

You are the **reviewer and manager**. The independent **PEER model** is the
**co-editor**. You run a bounded-by-convergence loop that ends only when the
repo objectively solves the problem it claims to — not after a fixed number of
rounds.

This skill is **user-initiated only**. Producers may suggest it but must not invoke it. The sole exception is `/cdd-auto`: the user's explicit auto invocation authorizes its mandatory per-wave calls to this canonical skill. Treat each as a normal `/peerreview` run—never let cdd-auto imitate or bypass this workflow.

## First: read the constitution

The methodology is governed by [`~/personal/peerreview-skills/CONSTITUTION.md`](../../CONSTITUTION.md).
You do not need it to *run* a review, but any change to this skill — and the
after-completion evolution step — is gated by it (the bar, the size gate, the
trust boundaries, commit-and-publish). Durable lessons from a run are filtered
through it via `/peerreview-evolve`, never written to a log (there is none).

## Step 0.0 — Identify HOST and PEER

The HOST running this skill reviews/orchestrates and owns git, verification,
fact-checking, and convergence; the PEER only co-edits. Resolve both mechanically
with `~/personal/peerreview-skills/scripts/select-peer.sh <repo_path>` and use its
exact `HOST/PEER/DRIVER/AUTH_SIDE/TIER` result. It detects the HOST from process
markers (Claude Code, Codex CLI, Pi, DeepSeek Harness), walks the ladder below in
order, and preflights each candidate's CLI **and** auth — so it is also the peer
preflight Step 0 needs:

| Tier | PEER | Selected when |
|---|---|---|
| 1 | Claude Code, Claude subscription | HOST is not Claude Code |
| 1 | Codex CLI, OpenAI ChatGPT subscription | HOST is not the Codex CLI |
| 2 | DeepSeek Harness `dsh` (deepseek-v4-pro) | no tier-1 peer reachable **and** the repo carries CDD markers (`cdd-prd` / `cdd-conformance` / `cdd-implementation`) |
| 2 | Pi, `deepseek` API-key provider (deepseek-v4-flash) | no tier-1 peer reachable, every other repo |

**The PEER vendor is never the HOST vendor.** A same-vendor pass is not a peer
review — this methodology's own evidence is that degraded same-vendor passes miss
whole defect families — so a DeepSeek HOST (Pi or `dsh`) has the two tier-1 peers
and no tier-2 fallback, and a Pi HOST must still be on `PI_PROVIDER=deepseek`
because that pins the vendor the ladder resolves against. Tier 2 is a **disclosed
degradation, not an equal peer**: name the tier that actually ran in the report.
Unsupported HOST, or no cross-vendor peer reachable → stop (**Required-peer
failure**). A same-HOST review is never a substitute.

## Inputs

- `repo_path` — defaults to the current working directory.
- `--chat` — review a pre-repository idea/spec supplied in the conversation. The
  HOST captures it as `ARTIFACT.md` inside a private ephemeral Git workspace;
  the converged artifact is returned in chat, then the workspace is deleted.
- `--dry-run` — produce the plan and stop; do not invoke the PEER or edit files.

## Step 0 — Preconditions (fail closed)

1. Normally, `repo_path` is a git repository. If not, stop and tell the user
   (offer `git init` only if they ask). With explicit `--chat` intent, instead
   create `CHAT_WORKSPACE` using
   `bash ~/personal/peerreview-skills/scripts/chat-review-temp.sh new`, capture
   the supplied idea faithfully as `ARTIFACT.md`, and use that private Git repo
   for driver compatibility and attributable rounds. The user's current
   instruction is durable intent; if the material to review is absent or
   materially ambiguous, clean the workspace and stop rather than invent it.
2. Peer preflight is the Step 0.0 resolution itself — `select-peer.sh <repo>`
   validates each candidate's CLI presence and auth without printing credentials
   (`claude auth status` reporting a Claude subscription; `codex login status`
   reporting a ChatGPT subscription; `pi auth check --provider deepseek`; `dsh`
   with `DEEPSEEK_API_KEY` and a composing headless profile), and it exits 69
   only when no cross-vendor peer survives. Raw-API-key auth on a subscription
   side is not this contract. A resolved tier-2 peer means every tier-1 peer was
   unreachable — disclose which, and why, in the report. Usage limits or a
   failed/empty round mid-run are terminal blockers: disclose the exact failure,
   clean `ACTIVE_CHARTER` if created, and stop; never re-ladder to a different
   peer mid-run, which would discard the anchored session and the round history.
   A transient network failure may be re-probed once and retried fresh only
   after resolution is green.
3. Working tree + delivery branch: note uncommitted changes. When durable intent names a
   GitHub issue/PR, read its live state before any commit: review an OPEN PR on its head branch;
   a MERGED PR/CLOSED issue needs a follow-up branch (or a stop), never review commits on the
   default branch where Step 6 would bypass the landing gate. Unless the **Path-scoped git policy**
   below applies, commit a clean baseline before the loop so every round's diff is attributable.
4. **Create a fresh active review charter; never add review scaffolding to the
   repo.** Use the schema in `templates/PROBLEM.md`, but create `PROBLEM.md` in a
   private temp directory with `bash ~/personal/peerreview-skills/scripts/charter-temp.sh new`;
   retain the returned path as `ACTIVE_CHARTER`. Derive intent in this order:
   current explicit user instruction → declared upstream source → PRD/PLAN/spec
   → tests/docs. Implementation behavior is evidence, never intent by itself.
   A pre-existing repo-root `PROBLEM.md` is another durable input: do not edit or
   delete it. When sources are coherent, synthesize Scope, ACs, gate, and
   residuals and **continue without a confirmation stop**. Stop after cleaning
   via Step 6 and ask only when sources conflict or no durable source states
   the intended behavior; silently deriving ACs from the current implementation
   would make review circular. Regenerate against current durable intent every
   run—never cache a verdict/charter or commit `ACTIVE_CHARTER`; this prevents
   stale duplicate contracts without weakening charter-first review.
5. Fetch the checkpoint with `bash ~/personal/peerreview-skills/scripts/review-anchor.sh latest <repo> --fetch`.
   No/non-ancestor anchor, changed intent, or unbounded/cross-cutting impact selects **full**; otherwise select **incremental** anchor→HEAD + impact closure (consumers, contracts, tests, docs, migrations, generated artifacts).
   Incremental is never diff-only: run the full gate and escalate if impact cannot be bounded. Under `~/projects` (tags are forbidden git writes), always select full. In `--chat` mode, select full and skip checkpoint fetch because the wrapper has no remote or prior anchor.
6. **Self-test the active charter's Verification gate before the loop:** from
   repo root, fix blind spots and enumerate durable sources, never charter prose; on a PR, diff gates cover the selected review range (base/anchor→HEAD), never only `HEAD^`.

### Chat-artifact delivery policy (`--chat`)

This is a delivery exception, not a weaker review: resolve the peer through the
same Step 0.0 ladder (the ephemeral wrapper never carries CDD markers, so its
tier-2 fallback is Pi), derive the same fresh private charter, commit an ephemeral
baseline and rounds, run the same gates, and require the same neutral PEER verdict.
The artifact defaults to the `prose-spec` profile unless its content proves a
more specific profile. Never add a remote, push, create an anchor tag, or treat
the temporary wrapper as product scope. Before cleanup, preserve the final
artifact and per-AC report in the response; then run
`bash ~/personal/peerreview-skills/scripts/chat-review-temp.sh clean "$CHAT_WORKSPACE"`.
Clean `CHAT_WORKSPACE` on every terminal exit, including dry-run, auth failure,
ambiguity, non-progress, and verdict-pending.

## Required-peer failure (fail closed)

A cross-vendor PEER from the Step 0.0 ladder is mandatory. If `select-peer.sh`
resolves none, or the resolved PEER is quota-blocked or returns no non-empty
report/verdict, state the blocker and stop after charter cleanup. Never label a
HOST-only pass converged, never fall back to a same-vendor peer, and never push
review edits made without the mandatory PEER round. Resume by re-running
`/peerreview` after the named blocker is resolved.

## Path-scoped git policy (repos under `~/projects`)

If the **resolved absolute** `repo_path` is under `~/projects`,
peerreview performs **no git writes at all** on the reviewed repo: no
baseline commit, no per-round commit, no `git revert`, no push, no branch
or remote changes. The user verifies and commits manually on a Windows
machine. Concretely, in this mode:

- **Step 3 baseline:** skip the baseline commit. The baseline is the current
  `HEAD`; record any pre-existing working-tree changes in the report so the
  user can tell them apart from peerreview's edits. Attribute each round with
  `git diff` against `HEAD` (snapshot the per-round diff to a temp file if
  needed) — never with commits.
- **Step 4.5:** do **not** commit the round. To undo a bad round, restore
  from `HEAD` (`git checkout -- <files>` / `git stash`), not `git revert`.
- **Step 5:** the "working tree clean and every change committed" clause is
  replaced by: *all intended edits are present in the working tree;
  peerreview committed and pushed nothing.* New files are left untracked.
- **Step 6:** do **not** commit or push. Leave every edit uncommitted and
  new files untracked. The report states explicitly that the repo is left
  for manual Windows-side verification and commit, names the branch, and
  confirms nothing was committed or pushed. This is the *expected*
  terminal state here — not a failure, so do not "fail loud" about the
  absent push.

This exception governs only the **repo under review**. Self-evolving and
pushing `peerreview-skills` (in `~/personal`, outside `~/projects`) is unaffected
and still unconditional.

## Step 1 — Read the charter adversarially

Parse `ACTIVE_CHARTER`: Problem, Scope, Non-goals, ACs, Verification, Residuals.
Check every item traces to a durable source; the temp charter cannot invent requirements.

Treat it as a **claim to be disproved**, not a description to trust —
especially when the same generator skill wrote both the repo and the charter
(self-serving risk). Where acceptance criteria are vague or builder-invented,
prefer criteria that trace to the **Source of truth** and say so in the plan.

## Step 1.5 — Detect repo profile and load approach module

Classify the repo by file markers and load the matching approach module(s) via
Read. Approach modules supply artifact-type-specific review lenses, dominant
defect classes, and verification-gate amendments — they shrink Step 2's
generic prose and let the PEER be briefed against the right defect classes.

| Profile | Detection markers | Approach module |
|---|---|---|
| `cdd-prd` | top-level `PRD.md` + ≥1 `PLAN-*.md` | `~/personal/peerreview-skills/skills/peerreview-approach-cdd-prd/SKILL.md` |
| `idd-prd` | top-level `PRD.md` + top-level `PROGRESS.md` AND no `PLAN-*.md` (evaluate after the `cdd-prd` row) | `~/personal/peerreview-skills/skills/peerreview-approach-idd-prd/SKILL.md` |
| `cdd-conformance` | `conformance/` dir with `test.json` leaves, OR top-level golden-file categories | `~/personal/peerreview-skills/skills/peerreview-approach-cdd-conformance/SKILL.md` |
| `cdd-implementation` | language manifest (`package.json` / `pom.xml` / `pyproject.toml` / `go.mod` / `Cargo.toml`) + sibling `*-conformance/` OR top-level `conformance/` | `~/personal/peerreview-skills/skills/peerreview-approach-cdd-implementation/SKILL.md` |
| `evidence-docs` | evidence file (`SOURCES.md` or equivalent) whose `path:line` citations point OUTSIDE the repo + charter Source-of-truth naming external repo paths | `~/personal/peerreview-skills/skills/peerreview-approach-evidence-docs/SKILL.md` |
| `knowledge-artifacts` | `context/sources.md` + `context/sources_zh.md` and at least 2 of `concept_graph.md`, `critiques.md`, `deep_dive.md`, `summary_zh.md` | `~/personal/peerreview-skills/skills/peerreview-approach-knowledge-artifacts/SKILL.md` |
| `prose-spec` (inline) | markdown-heavy, no code, declared-exhaustive tables | inline in Step 2 below |
| `derived-suite` (inline) | derived from a converged upstream spec (PLAN from PRD, design from requirements, tutorial roadmap/`PLAN.md` from a book TOC) | inline in Step 2 below |
| `source-rendered` (inline) | Mermaid/PlantUML/Graphviz sources + committed rendered images | inline in Step 2 (`templates/PROBLEM.md`) |
| `html` (inline) | HTML repos | inline in Step 2 (`templates/PROBLEM.md`) |
| `code` (fallback) | source code, no special markers | no module — apply generic adversarial code review |

A repo can match **multiple profiles** (e.g., a CDD implementation repo that
also ships rendered architecture diagrams). Load all matching modules; their
lenses compose. If no profile matches, fall back to `code` (generic).

For versioned rule engines, cross-product every authored state with applicability/overlap and assert intermediate dispositions as well as final verdicts: prerequisite abstention can mask an inner `UNKNOWN`→`SURVIVES` trace when `UNKNOWN` is collapsed with inactive/non-overlap. For open-world inputs, do not assume one prerequisite/coverage record per scope: preserve distinct identities, aggregate the full set, and probe mixed adequate/inadequate/unreviewed records so contradictions stay inspectable. When scoped transitions reference globally stable identities, test cycles split across scopes plus multi-edge acyclic branching—the invariant key may be global even when reducer state is local. When adding a catalog rule, reconcile every total/effect-distribution assertion—including installed-wheel CI smoke—and pin the same distribution locally; a green source suite cannot prove stale CI arithmetic. (ArchSift PR #40 and Docscan PR #10, 2026-08-09.)
For dependency-injection changes, instantiate every affected conditional/profile graph in the real framework context;
direct constructor tests and source inspection do not prove bean selection. When retiring a stub, flag, or profile restriction,
sweep source and maintained docs for old status markers; qualify same-named components across languages or layers. For YAML→typed-schema pipelines, probe raw unquoted scalars—not only serializer-produced fixtures—especially YAML 1.1 `yes/no/on/off` and dates: a safe loader may coerce them before JSON Schema sees the value and silently satisfy the wrong type, so constrain resolvers or contract the coercion. For canonical-JSON schema/runtime parity, remember JSON Schema treats mathematically integral floats (`1.0`) as integers: normalize them to one canonical integer form or make the contract numeric-free, and probe booleans, fractional/non-finite numbers, plus unpaired surrogates in both values and `propertyNames` before UTF-8 encoding. Treat exact string patterns ending in `$` as unproved: Python `re` accepts the position before a final newline, so execute newline-suffixed valid-looking values in both the declared ECMA-262 dialect and runtime, using a portable absolute-end assertion such as `(?![\s\S])` rather than Python-only `\Z` when both must agree. (ArchSift PR #60, 2026-08-09.) Treat `format: date-time` as unproved until the validator's optional checker is demonstrably active; execute schema and runtime against year `0000`, ordinary/leap days, and non-leap centuries after every regex change—never accept a hand-traced pattern. Also probe heterogeneous unknown mapping keys: sorting raw keys can crash on mixed types, while `key=str` ties `1` with `"1"`; require a total type+representation order and assert a validation error rather than an internal error. Push a Cc/Cf-bearing unknown key through human diagnostics too: `repr`-escaped message values do not protect a raw field path, so require central terminal escaping while canonical JSON remains unchanged. For Python CLIs promising Windows support, execute non-ASCII user paths through narrow-encoding redirected stdout/stderr: diagnostics must remain decodable and completed operations must not become internal failures. When parametrizing huge parser/stress inputs in pytest, assign bounded explicit IDs—pytest exports node IDs through `PYTEST_CURRENT_TEST`, and Windows rejects environment values over 32,767 characters. (Docscan PR #4, 2026-08-08: default IDs broke all Windows jobs; the ordinary UTF-8 matrix also missed raw `UnicodeEncodeError`/false-SL070 output paths.)
For discover→validate→mutate automation, test validation/status failure separately: treating command failure as
empty/clean can mutate corrupt targets, so require validation first; CLI mocks must preserve stdout data vs stderr diagnostics—merged non-empty output is not inventory.
For immutable/content-addressed filesystem persistence, byte equality and a one-time path check are a narrow oracle: execute same-byte file and outside-symlink swaps between check→open, a replacement during reading, and a replacement before failure cleanup. Cleanup must prove the path still names the file this attempt created—never unlink merely because that path was once ours. Do not overfit identity to one OS: `(device,inode)` can be immediately recycled on ext4, while full path-`lstat` vs handle-`fstat` tokens differ on modern Windows; bind path↔handle with `samestat`, compare generation-sensitive metadata only on the same stat surface, and require the live OS matrix. A descriptor retained to prove ownership can itself block `os.replace` on Windows: when replace requires closing the source, verify its bytes and capture a same-surface generation token while pinned, close only at that boundary, recheck the token, replace, then read back the destination; gate unlink-of-open-file injections to OSes that permit them, never the production flow. (ArchSift PR #38 and Docscan PR #14, 2026-08-08–09: macOS-only green hid CRLF goldens, replacement deletion/reuse, ext4 inode recycling, Windows stat-surface drift, and open-source replace failure.) For any new byte-exact golden extension, extend `.gitattributes` with `text eol=lf`; an LF local checkout does not prove a Windows checkout.
For generic `code` repos whose verification is a worked example, fake peer,
fake service, or local smoke, treat the oracle as narrow until disproved. If
the production flow is stateful over repeated units (blocks, chunks, messages,
pages, records, peers), probe at least one multi-unit continuation case and
assert both progress to the next unit and final completion state. A single-unit
smoke can pass while the pipeline stalls after the first unit. And when such a
structure has a **reset/reclaim** op meant to restore its initial state
(free-all / clear / shrink / release), probe that reset from a *grown* state
(past initial capacity), not just from within it — grow-then-reset is distinct
code from reset-within-initial and is where round-trip-to-pristine bugs hide.
(2026-06-28 tutorial-memory-allocator-c: the green suite asserted free-all →
single pristine block only in the never-grew case; the grow-then-free-all path
leaked a whole page — a shrink-threshold off-by-one plus a `grow_heap`
page over-count — both caught only by the cross-vendor pass.) A related
narrow-oracle axis: when the artifact **parses or serves a structured input
with distinct regions** (an HTTP request's request-line / headers / body; a
framed protocol's header / payload; a file format's magic / metadata / data),
the happy-path oracle usually exercises only ONE region — a GET-only suite
never reads the request **body**, so a from-scratch server that mis-slices its
input stream (`wsgi.input` = the whole raw request vs. only the bytes after the
blank line) passes every test yet corrupts any body reader. Probe at least one
**body/payload-bearing** input (a POST with a `Content-Length` body) explicitly.
(2026-07-03 tutorial-web-server-python: a green GET-only suite missed
`wsgi.input` carrying the entire raw request instead of just the body; the
cross-vendor pass caught it, plus a second-order bug in the fix's `exc_info`
replace-before-send guard.) For terminal/web-terminal changes that enable **OSC 52 clipboard output**, the user-selection happy path is a narrow security oracle: execute a pane/application-originated OSC 52 write (and read-back query when supported) and prove it cannot mutate or exfiltrate the host clipboard while the user's explicit selection still can. A green copy test under tmux `set-clipboard on` misses clipboard poisoning; `external` preserves tmux-owned selections while rejecting pane-app access. (2026-07-24 agent-sandbox: bidirectional copy passed, but this adversarial probe forced `on` → `external`.)
For hostname/domain security classifiers, normalize DNS-equivalent inputs before tiering: case-fold
ASCII names and strip a single trailing root dot, then parity-test mixed case, trailing-dot, and
suffix-boundary near misses across implementations. Otherwise one blocked destination can fall from
a human-review tier into an unattended fallback. (agent-sandbox PR #52, 2026-08-09.)
For layered configuration defaults (example/template → orchestrator interpolation → runtime parser),
test each layer independently: a render populated by the example can mask an unsafe orchestrator
fallback. Render once with the relevant process variables cleared and an empty env file, then with
the example and explicit opt-in; mutation-flip each fallback. (agent-sandbox PR #54, 2026-08-09.)

State the detected profile(s) in the plan you present at Step 2 so the user
can override if the heuristic misfires.

## Step 2 — Work out a peer-review plan (forecast, not a cap)

From the charter + repo nature/size/complexity (file count, languages,
security surface, blast radius), produce:

- **Focus areas**, ranked by risk (correctness > security > robustness > docs).
- **Per-AC review strategy** — how each acceptance criterion will be checked.
- **Verification gate** — the exact commands from the charter's Verification
  block you will run every round, plus any obvious missing tests, linters, or
  validators. **Compiled-language repos with build artifacts (`build/`, `target/`,
  `obj/`) require a hermetic clean build; verify `clean` removes every generated
  source, object, and binary.** In-place gates can pass on stale/foreign objects
  (macOS arm64 artifacts later failed in Linux, including a whole reused binary;
  `make clean test` fixed it, once `clean` also removed `bminor`/`scanner.c`).
  **Process-level performance gates need their own deadline:** checking elapsed
  only after child exit hangs on regressions. Set the subprocess timeout to the
  budget, map timeout to budget failure, then validate exit/output/cardinality
  before accepting elapsed success; mutation-test timeout, non-zero, malformed
  output, and non-finite budgets. (ArchSift NFR-005, 2026-08-07.) **For
  multi-process/container smoke gates, a producer artifact or running status
  proves only producer readiness:** wait for the consumer's post-init control
  state, then repeat cold starts to expose races. (agent-sandbox PR #51:
  the shared CA predated agent `OUTPUT DROP`, causing 2/3 false failures.)
  Prose-spec repos
  (PRD/charter/design docs, no code): the dominant defect class is internal
  cross-reference inconsistency, not code correctness — gate on
  reference-closure (every flag/term/identifier referenced is defined in its
  declared "complete"/"exhaustive" contract table) and cross-section
  consistency (exit codes ↔ output ↔ business rules do not contradict);
  treat any "etc." inside a declared-exhaustive list as a defect. A spec that
  declares its own **acceptance gate** gets one more check: name the producer of
  the evidence that gate consumes. "Not yet collected" is the normal state of a
  greenfield PRD and is not a finding; **no producer that could ever collect it**
  is — such a gate can neither pass nor fail, so the release boundary it defines
  is unreachable while the artifact reads as complete. Before concluding none
  exists, look past the source the artifact assumed to the *consumers* of the
  same evidence. (waypoint-prd 2026-08-29: acceptance demanded a zero-tolerance
  per-bar comparison against action strings the upstream platform does not export
  at all, making the release gate unfalsifiable; the downstream consumer was
  already receiving those exact payloads, which also settled a chart-timeframe
  assumption the artifact carried as unverified.) When the
  artifact is *derived* from a converged upstream spec (PLAN from PRD, design
  from requirements, test-plan from spec), add **upstream→downstream coverage
  closure** as a first-class lens: enumerate every upstream behavior/flag and
  confirm each maps to exactly one downstream unit (or an explicit
  non-goal), and that no downstream unit lacks an upstream origin — an
  unmapped upstream behavior is the dominant defect class there, not internal
  inconsistency. For derived **golden-file / test suites** specifically:
  (a) reconstruct closure as an *executable* gate script (reuse the authoring
  validators) and run it at baseline — a self-authored coverage doc is not
  evidence until a script confirms disk ⇔ doc bijection; (b) if the suite
  ships its own coverage/trace artifact, gate that it enumerates every
  downstream unit **individually** — grouped/abbreviated IDs
  (`FOO-002,003,008`) silently defeat machine closure and are a defect;
  (c) recompute every pure/`function` expected value from the upstream
  algorithm rather than only checking it parses.
  (c-bis) for a **tutorial-roadmap `PLAN.md`** (planning-stage, derived from a
  book/web TOC, no code yet) the coverage-closure lens is the right and
  sufficient frame, but a gate parsing `- [ ] NNN — <title> (<branch>)` lines
  must (1) capture the **LAST** `()` group as the branch — titles legitimately
  carry their own `(...)`/`§` source pointers — and (2) tolerate a trailing
  `← current` marker (`(?:\s*←.*)?$`); both are quirks of every `/tutorial`
  PLAN.md and were independently re-derived across three runs (now codified).
  The same title-parenthetical tolerance applies to concept-closure sentinels:
  don't key on one exact contiguous title string when a harmless parenthetical
  annotation would split it; use bounded/non-greedy phrase predicates or a
  distinctive issue anchor, and mutation-test at least one internal-title
  parenthetical.
  (c-ter) an executable closure gate must **pin its expected unit cardinality to
  the source-of-truth** (the charter's declared count/range, e.g. `001..036`),
  never derive it from the artifact under test — a check like
  `expected = range(1, len(items)+1)` is self-consistent under whole-unit
  add/drop at the contiguous boundary, so it silently passes a roadmap with an
  appended `037` or a truncated tail (missing `036`). Mutation-test the boundary
  (drop the last unit; append one past the end) at baseline. (raytracing-in-one-
  weekend 2026-06-06: Codex R1 caught exactly this — gate derived the range from
  `len(nums)`, blind to append/truncate; fixed by pinning `EXPECTED=36`.)
  **Pin only a count that is genuinely enumerable from the source-of-truth**
  (chapters, spec sections, declared `001..N`). When the unit count is instead a
  *decomposition choice* the source does NOT dictate — e.g. how many issues a
  tutorial chapter splits into — pinning it is itself artifact-derived and
  OVERFITS: it wrongly fails a legitimate future re-split (one issue → two). There,
  keep the numbering check to the pure invariant (unique, contiguous `001..N`, N
  free) and put whole-unit coverage on the **concept/dependency closure** (every
  source chapter's concepts present + correctly ordered), which catches dropping a
  *meaningful* unit regardless of count. (rasterization-a-practical-implementation
  2026-06-06: pinning `EXPECTED=16` on a tutorial roadmap was the right reflex but
  wrong target — Codex's verdict flagged the overfit; reverted to contiguity-only +
  AC1 concept-closure, which already fails a dropped capstone.)
  **A substring concept-sentinel must be a token NOT contained in an umbrella
  term present elsewhere** — e.g. `"encod"` is a substring of `"bEncoding"`, so a
  `bencode-encode` sentinel of `"encod"` matches every issue merely mentioning
  BEncoding and silently passes when the encoder section is dropped; use the
  distinctive agent-noun (`"encoder"`/`"decoder"`) instead. Operationally:
  **match sentinels as whole words (`\bX\b`) against the phase BODY only, never
  its title** — substring matching lets `"Transaction"` pass on `"transactions"`
  and `"send"` on `"sending"`, and a concept word in the phase *title* (`"CLI"`
  in "Persistence and CLI", `"Merkle"` in "UTXO Set & Merkle Tree") masks a
  dropped body. Even whole-word, a **domain-ubiquitous word is a non-sentinel**
  (`"block"` matches "genesis block"/"AddBlock" regardless — gate the distinctive
  `"NewBlock"`, which `\b` keeps off "NewBlockchain"). And when the charter prose
  **duplicates** the gate's machine-checked concept list, name the gate's table
  the single authoritative source + have the prose mirror it (parity-check both),
  or they drift — the charter listing a concept the gate never enforces.
  (building-blockchain-in-go 2026-06-07: Codex drove all four over 4 rounds —
  header-masking, substring-masking, the `block` non-sentinel, charter/script
  drift.) And **mutation-test
  each concept by dropping its section AND renumbering contiguously** — a bare
  drop leaves a numbering gap that AC2 catches first, masking whether AC1 concept-
  closure would have caught it on its own. (bittorrent-client 2026-06-06: Step 0.5
  self-test caught both — the umbrella-substring false-negative and the AC2-masks-
  AC1 blind spot — before baseline.)
  A second masking class is **forward-reference cross-prose**: a sibling issue's
  annotation echoes a concept's loose-substring trigger (e.g. a `verify` issue
  whose body cites "ReadPiece/WriteBlock/+constructor", or a Program issue saying
  "create…a torrent"), so dropping the *real* section passes on the sibling's
  reference. When **no clean distinctive noun exists** (read/write/verify share
  vocabulary across siblings by design), anchor the sentinel on the issue's
  **canonical branch slug** — AC3 guarantees it unique and it is removed when the
  issue is dropped, immune to prose echoes. Critically, **mutation-test EVERY
  section-drop exhaustively, never a sample** — a round that *adds* forward-ref
  documentation can mask OTHER concepts, so a self-test that checked only the one
  concept it was hardening (round 1: bencode) misses the regression it just
  introduced. (bittorrent-client 2026-06-06 re-run: the owed-Codex degraded pass
  swept all 19 drops and found 5 torrent-phase blind spots
  [pieces-blocks/torrent-setup/torrent-io/torrent-verify/torrent-create] that
  round 1's forward-ref annotations had created and its sampled self-test missed;
  branch-slug anchoring fixed all five.) The same masking applies to **section-
  specific prose sentinels** (Migration Notes, Residuals, Versions `Why` cells):
  bound the search to the intended section, never the whole artifact, or later
  issue lines can satisfy a prose requirement by forward reference.
  **A phase/section-ordering check** (e.g. "all Peer-phase issues before all
  Client-phase issues") must derive phase membership from a **non-evadable UNION
  of independent signals** — the declared structure header (`## Phase N: <name>`)
  AND the closure predicates — never a single proxy. Each single proxy is
  evadable: a branch-prefix (`feat/peer-`) by a renamed kebab slug (AC3 permits
  any); the `## Phase` header alone by a malformed/missing header that silently
  empties the set and skips the guarded check. The union is robust because
  closure already requires every concept present, so an issue cannot be hidden
  from its phase set without independently failing closure. Caveat: a closure
  predicate **relaxed to feed the union** (made branch-independent so renamed
  branches still match) must keep a **context anchor**, or it reintroduces
  masking — e.g. a bare `client-downloads = "download" in title` is satisfied by
  a Program entry-point issue's "create/seed/download a torrent" CLI verb;
  exclude the program/entry-point title. (bittorrent-client 2026-06-06
  cross-vendor: the owed Codex pass drove this over 4 rounds — branch-only →
  `(title∧branch)` → `feat/peer-` prefix → `## Phase` header → union; R4 fixed
  the relaxed-predicate masking regression. Two prior degraded same-vendor passes
  missed the whole family.)
  (c-quater) when a tutorial roadmap **includes the AWS deploy phase** (a
  deployable artifact), the gate must verify the deploy issues are **contained
  within the Deploy phase block** (between its header and the next header / EOF)
  and in dependency order (IaC → e2e-suite → CI/CD-workflow → capstone), not
  merely present *somewhere* in PLAN.md; and the CI/CD-workflow issue must
  **author** the full `apply→sync→invalidate→e2e→destroy(if:always)` lifecycle
  while the capstone issue **executes** it once (apply→e2e→destroy) — the two
  distinct, never an apply-less or duplicated overlap. More generally,
  **containment checks are a family**: when you harden "phase contains its
  required issues" for one phase kind, apply it to EVERY phase kind in the same
  sweep — adding it for article phases but not the deploy phase costs a verdict
  round each. (3d-soft-engine 2026-06-06: e2e-before-cicd ordering, deploy-issue
  containment, and the author-vs-execute split were the round 2–4 findings.)
  The deploy e2e issue's conventional branch is `test/e2e` and is **valid** — the
  IDD "no numbers in branch names" rule bans *issue-number* tokens
  (`feat/scanner-002`), not idiomatic digits embedded in a word (`e2e`, `s3`,
  `oauth2`). A branch-hygiene gate must tokenize on `/_-` and flag only an
  all-digit token, never the `2` inside `e2e`; do not "fix" `test/e2e` by
  renaming it. (Re-derived two ways same day: 3d-soft-engine renamed it to
  `test/end-to-end`, cgfs narrowed the gate — settle as: keep `test/e2e`,
  narrow the gate.)
  (d) when the charter's **verification gate is itself the deliverable infra**
  (a self-authored ADR/boundary-rule or golden-file charter whose gate greps/
  parses the artifact), the gate is a self-serving artifact too — Codex will
  adversarially mutation-test it (flip an enum, add an ignored field, feed a
  substring/word-boundary/trailing-char near-miss, an unanchored-heading look-
  alike). The moment the FIRST gate-robustness false-pass surfaces, do a
  **comprehensive hardening sweep in one round** — anchor every grep (`^…$`),
  use full-identifier-boundary token matches (not substring/`\b`-on-digits),
  parse structured formats with a real parser (PyYAML/JSON, not regex), and
  require paired/path-correct fields — instead of patching one regex per round.
  Reactive per-regex patching invites the next paranoia level each verdict and
  burns ~3 extra rounds (raytracer-architecture 2026-05-31: rounds 4–6 each
  fixed one regex before a round-6 full sweep converged immediately).
  **When the deliverable is mechanically reconstructible from its source** (a
  transcription/port/faithful-copy whose body is the source content verbatim
  under a fixed authored header — e.g. a doc2md xlsx→md whose every table line is
  an extraction row), that one-round sweep is a **whole-file byte-exact
  reconstruction diff**: rebuild `(fixed header + source-derived rows)` and `diff`
  the ENTIRE deliverable against it. It pins every byte to either the source or
  the fixed header, so no structural near-miss (extra heading, smuggled
  blockquote, a blank line splitting the table, reordered prose) survives — reach
  for it on the FIRST gate-robustness false-pass instead of iterating prefix/
  structural checks. A gameable gate on a mechanical deliverable is the whole
  cause of the escalation, not the reviewer's thoroughness. (2026-07-09 doc2md
  BuyEdayTC: a single-table, no-image xlsx converged in 6 rounds — round 1 a real
  confidentiality overclaim, round 2 real, but rounds 3–6 were pure gate-hole
  escalation [headings → smuggled blockquote → editorial-exception → blank-in-
  table] that a whole-file reconstruction diff would have pre-empted at round 3.)
  (e) **Math/renderer architecture repos** (ADRs/boundary-rules pinning a
  rasterizer, raytracer, physics, codec — decisions that are comparators,
  inequalities, or directions): the dominant defect is **convention-direction
  inconsistency**, and it is INVISIBLE in the ADR prose — a backwards inequality
  reads fine and passes every structural gate. Re-derive every
  comparator/inequality DIRECTION (depth sign, bias sign, comparator strictness
  `<` vs `≤`, order-independence scope, inclusive/exclusive bounds, **the
  metric/counting model — which steps a cost counter counts**) against the
  citing conformance oracle/goldens AND the faithful reference, never trust the
  ADR wording (tinyrenderer-architecture 2026-06-05: ADR-0006's shadow-bias
  inequality was literally backwards — `frag > stored + bias` vs the faithful
  `frag < stored - bias` — caught only by re-deriving against the `shadow/002`
  golden; the light-buffer convention contradicted the same ADR's z-buffer
  convention). A distinct axis is **time/unit granularity — and here re-deriving
  against the golden ALONE gives false confidence**: when a discrete-time predicate
  (`at ≤ validBefore` in whole seconds) is realized over a finer-clock store (a
  Redis ms-wall-clock TTL), the golden runs at the COARSE grain and passes with
  *either* formula, so it is blind to the sub-unit gap. `EXPIREAT validBefore`
  expires at the START of the boundary second → an in-window replay at
  `validBefore.5 s` is wrongly re-accepted (a sub-unit replay hole); the faithful
  impl needs `+1` (absolute `EXPIREAT validBefore+1`) to cover the fractional final
  unit. Settle by EXECUTION against the real clock and check EACH layer's grain —
  distinct from the `<`-vs-`≤` strictness axis above. (x402-architecture 2026-07-12:
  the nonce-TTL `+1` was wrongly refuted by the degraded pass AND cross-vendor
  round 1 — both "settled it via the golden" — then reversed over 3 rounds once the
  seconds→ms gap was derived by execution against `nonce-store.ts` + `middleware`'s
  verify→window→replay order.) And when an ADR-WORDING fix lands, **sweep the citing conformance
  suite's DESCRIPTIONS/metadata for prose echoing the OLD wording** — the
  faithful numeric goldens stay correct while their descriptions go stale, a
  cross-repo contradiction the next verdict catches. A STATUS promotion is the
  same hazard from a different angle: when an ADR is promoted `Proposed→Accepted`
  by an **acceptance/demo artifact** rather than a conformance golden (the
  minority path), sweep the repo's OWN prose for the baked-in conformance-only
  assumption — the lazy-promotion rule sentence ("once a `*-conformance` golden
  cites it"), a "Pinned by (**conformance**)" index-column header, and the
  charter's AC "Current state" snapshot all silently misclassify the
  acceptance-pinned ADR. The promoting skill typically de-stales the ADR body +
  its one index row and misses these; check them in ONE round. (2026-06-16
  lrucache-architecture: `/cdd-acceptance` promoted ADR-0008 via the demo but
  left the README lazy-promotion prose + column qualifier conformance-only and
  the charter "Current state" claiming it still `Proposed`.) The **metric/counting
  model** is the highest-yield re-derive target and a conflation in it drains one
  instance per round if patched piecemeal: when a counting term is ambiguous (a
  "probe" defined as "compute + access" = 2/position vs the goldens'/impl's
  one-probe-per-position), the same wording is usually seeded UPSTREAM (PRD) and
  inherited by the ADR + PLAN + diagram, so fix EVERY repo's statement of it in ONE
  round AND re-derive the term's DEFINITION so it covers all ops — a definition that
  fits `add`/`mightContain` (one access/position) can still be wrong for `remove`
  (read + write/position, yet still one probe). And a **diagram's worked-example
  COMPUTED values** (hash positions, set bits, indices) are a self-serving artifact
  like any golden — re-derive them against the pinned algorithm + the citing golden,
  never trust the drawn numbers. (2026-06-16 bloomfilter-architecture: the structure
  diagram had FABRICATED, degenerate bit positions for `add("apple"/"banana")` — the
  author never computed FNV-1a — replaced with the conformance OPS-004 fixture; and
  the probe-counting model was "compute + touch"=2k across PRD/PLAN/ADR/diagram,
  drained over 3 verdict rounds before a family-wide one-round sweep converged it.)
  The promotion-staleness sweep also covers the **ADR's OWN `## Related`/body prose**:
  a `Proposed` ADR whose body asserts it in the past tense ("**Promoted to `Accepted`
  by …**") self-contradicts its Status line — re-tense to "to be promoted" (2026-06-16
  semaphore-architecture: ADR-0009 `Proposed` but its `## Related` said "Promoted to
  Accepted by /cdd-acceptance"). **Missing-ADR discriminator (qualifies the "real PRD
  decision with NO ADR is a gap" lens):** a PRD NFR routed to "ADR + review" / "ADR" is
  NOT a missing-ADR gap when it has (a) no citing conformance golden AND (b) no real
  trade-off (e.g. `O(1)` for a counter + FIFO queue — inherent, not surprising). Such an
  NFR is **review-only**; an ADR for it would be a perpetually-uncited non-decision (it
  could never lazily promote). The fix is to tighten the PRD/PLAN/coverage wording "ADR"
  → "code review" across every restating site (reconcile-ALL), NOT to add the ADR.
  Contrast a complexity NFR the suite DOES test via a metric/visit-count golden
  (bptree/merge-iterator): there the ADR is real and cited. (2026-06-16
  semaphore-architecture: Codex flagged "PRD routes complexity/space to ADR but none
  exists" — resolved by the wording sweep, not a new ADR.) **An architecture repo ships
  DELIVERABLE infra — the `rules/{impl}-boundaries.yaml` an impl's lint runner loads — so
  the architecture review MUST run the leaked-`</content>`-wrapper-tag sweep AND parse
  every shipped YAML/JSON with a REAL loader (`yaml.safe_load`/`json.load`), not an
  ADR-section-lint or a text-compare. A `Write`-leaked tag passes the section-lint and a
  text-compare yet breaks `yaml.safe_load`, shipping a boundaries.yaml the lint runner
  can't load. (2026-06-17 semaphore-architecture CONVERGED with a leaked tag in all 10
  ADRs + the boundaries.yaml — `yaml.safe_load` failed — because its lint never parsed the
  YAML; only the downstream `semaphore-conformance` Lens-7 upstream-parse caught it ~90 min
  later. The same leaked-tag + parse gate the cdd-conformance amendments already run
  belongs in the architecture review too.)
- **Round forecast** — an *estimate* (e.g. "small/internally-consistent → ~1;
  large multi-language with security surface → 3–5"). This is shown to the
  user for transparency. **It is never the termination condition.**

Present the plan. On `--dry-run`, clean `ACTIVE_CHARTER` with the Step 6 command and stop.

## Step 3 — Baseline

Unless the **Path-scoped git policy** applies, commit any pending state as a
clear baseline (`peerreview: baseline before round 1`) so each round's
`git diff` is clean and attributable. You own all git operations for the
entire loop. The PEER never commits or pushes.

**Review on a branch; land one commit.** Round commits are review evidence, not
product history. Unless the **Path-scoped git policy** or `--chat` applies, or
durable intent names an OPEN PR whose head branch is already the review target,
start the loop with `scripts/delivery-branch.sh start <repo> <slug>` and land it
in Step 6 (standing user preference, asked on three consecutive runs 2026-08-18/19).

## Step 4 — The convergence loop

**Mandatory PEER round (user durable directive, 2026-05-18).** Every
`/peerreview` run — first run *or* re-run, regardless of whether the HOST's
static pass found anything — MUST execute **at least one** cross-vendor co-edit
round. **Never converge at round 0.** The independent second-model pass is a
deliverable in itself (the whole point of the co-editor design), not
"invented work": even with no HOST-found defect, the PEER is briefed to do
an independent adversarial review and may make warranted minimal edits or
confirm clean. The earliest a run may converge is **round 1**. The HOST
remains the orchestrator: owns git, verification, fact-checking, and the
convergence decision; the PEER co-edits only.

**Keep the PEER review independent — don't hand it your agenda (user directive,
2026-05-23).** Brief the PEER to form its **own** findings adversarially from the
charter; do not lead with your findings list as the things to check (that turns
the independent pass into a confirm-my-work pass). State the self-serving risk
explicitly when the same model produced both the artifact and any prior review,
and tell the PEER to treat the green suite / prior review as a claim to disprove.
For the independent pass on a self-serving or already-"converged" repo, prefer a
**fresh PEER session** (round `1`/`--fresh`) over resuming the anchored one — a
resumed session carries its own prior "looks good" context. orderflow-go
(2026-05-23): resuming + leading produced a 1-round false convergence; a fresh
session + neutral brief found 6 real defects.

**Re-runs.** A convergence tag is a progress/history anchor, not a cached
verdict. Incremental briefs name anchor→HEAD paths and require independent
impact closure without re-reading unrelated stable subtrees. Full/no-change
runs probe the whole/deeper tree. Mandatory round + full gate run in either mode.

**Un-runnable gate.** When the charter's executable gate cannot run here
(air-gapped registry, missing infra), do **not** defer the whole gate to a
residual and move on — reconstruct *each* gate's verdict statically: a
coverage gate → enumerate every measured (non-excluded) class and confirm a
test exercises its branches, and verify the exclusion *mechanism* (e.g.
JaCoCo natively skips a class carrying a RUNTIME-retained annotation
simple-named `Generated`) rather than trusting the charter's "legitimately
excluded" wording; an SCA/dependency gate → reconcile the charter's claimed
CVEs/components/versions against the raw scanner output (counts and
coordinates), then reason the dependency-mediation precedence explicitly.
Only the *executable confirmation* is the residual; the verdict is still
reviewed.

Repeat rounds until the **Convergence contract** (Step 5) holds. Each round:

1. **Review** against the charter in the selected mode: whole tree, or the
   anchor→HEAD delta plus impact closure. Walk affected ACs, hunt correctness
   and security first, and run the full gate.
2. **Write findings** to a temp prompt file: include the complete current
   `ACTIVE_CHARTER`, then concrete file-specific findings ranked and tied to an
   AC or defect class. Restate: minimal edits, no commit/push, run and report the
   gate. The PEER may challenge traceability; the HOST revises the temp charter,
   never the repo, unless the durable source itself is defective.
3. **PEER co-edits**: run the `DRIVER` Step 0.0 resolved —
   `~/personal/peerreview-skills/scripts/<DRIVER> <repo> <prompt> <out> <round>`.
   Every prompt restates no-commit/push. Pass `1` for a fresh first session and
   `2`+ to continue it. Reference the script by this absolute repo path—only
   `SKILL.md` is symlinked into the skill directory. `dsh-round.sh` has no session
   resume, so every `dsh` round is fresh: its prompt must stay self-contained. If
   the driver is unreachable or returns a failed/empty result, apply
   **Required-peer failure**; do not improvise an inline or different-CLI path.
4. **Re-verify independently**: read the real `git diff HEAD` AND `git status`
   (for new untracked files the PEER created — `git diff HEAD` only shows tracked
   changes; a new `Dockerfile` or generated file is invisible to it) — do not trust
   the PEER's self-report. **Read the diff only AFTER the round has fully
   completed** (the round-driver exited / its last message is written) — never
   from a mid-flight working tree. A co-editor commonly
   tries-then-reverts experimental edits *within* a round, so an in-progress
   tree can show a transient "regression" the round itself discards before
   finishing; re-verifying mid-flight manufactures phantom findings and wastes
   an adjudication. (2026-06-06 raycaster-cpp: a mid-round read caught a
   `wallSlice` `== 0`→`!= 0` experiment that the gate rejected and Codex
   reverted before its CONVERGED — the final diff was clean.) Re-run the full
   gate. Check no regression and no new defect was introduced. **Fact-check
   claimed "corrections"**: the PEER may
   present a *regression* as a fix with confident wording (e.g. renaming a
   valid identifier/API/config element to a non-existent one and calling it
   a casing fix). Verify renamed names against authoritative knowledge, not
   just that the diff is minimal and in-scope. **A PEER factual claim about a
   gate-derived quantity (test count, pass/fail, coverage) is UNVERIFIED when
   the PEER could not run the gate** — its process/tool environment may lack
   daemon, socket, or network access, so a containerized/network-fetching gate
   can fall back to eyeballing (and miscounts).
   Settle any such number with the HOST's authoritative tooling (`cargo test --
   --list`, the real gate), and resolve a NOT-CONVERGED verdict premised solely
   on such a miscount by re-dispatching the verdict with that enumeration as
   neutral evidence — never edit the artifact to match the PEER's wrong count,
   and never treat the wrong-premise NOT-CONVERGED as a real residual. **Version-currency disputes
   (latest-stable / GA-vs-EA / "X is deprecated") must be settled against a
   LIVE registry, never either model's training belief** — when the session
   date is past a model's knowledge cutoff, both models may hold stale
   version facts, so a confident "that's only early-access" can be wrong in
   either direction. Use the authoritative live source (Adoptium API, the
   `repo1.maven.org/.../maven-metadata.xml` *live* metadata — NOT the
   `search.maven.org` solr index, which is itself often months stale —,
   `endoflife.date`, official version-history; for npm, the registry dist-tag via
   `npm view <pkg> dist-tags.latest` or `registry.npmjs.org/<pkg>/latest` — NOT
   deps.dev/Snyk, which lag the registry by patch releases; for Python, the PyPI
   JSON API (`pypi.org/pypi/<pkg>/json` — `info.version` + the per-release wheel
   list)) and keep/revert per that. For a **C-extension dep on a bleeding-edge
   interpreter**, "latest version exists" is NOT enough — verify a binary wheel
   for the EXACT `(interpreter-ABI, platform)` the artifact targets actually
   ships (e.g. a `cpNNN-…-macosx_*_arm64` wheel), or the user silently needs a
   compiler; the wheel's existence/absence is the real claim, not the version
   number (3d-modeller 2026-06-06: pinning Python 3.14 was only sound once a
   `pyopengl_accelerate-3.1.10-cp314-…-macosx_11_0_arm64.whl` was confirmed on
   PyPI). **An `abi3` (stable-ABI) wheel for the platform satisfies this for
   EVERY newer CPython** — a `cp37-abi3-macosx_*_arm64` wheel installs fine on
   3.14 with no `cpNNN` wheel and no compiler; do NOT flag "no cp314 wheel" when
   an abi3 wheel covers it (tutorial-augmented-reality 2026-06-06: opencv-python
   4.13 ships only `cp37-abi3` macOS-arm64 wheels, sound on Python 3.14). **Record that primary-registry source in the artifact itself, not a bare
   "verified"** — an uncited version re-triggers the same flag every verdict when
   the co-editor's mirrors disagree (3d-soft-engine 2026-06-06: an uncited
   `vite 8.0.16` was flagged twice before the row cited the npm dist-tag). When
   the artifact ships a **hermetic gate** (a derived-suite/tutorial roadmap gate
   that can't hit the network), make the gate *enforce that attribution*: require
   any externally-pinned tool row's `Why` cell to carry a registry citation
   (e.g. `registry.terraform.io`/`registry.npmjs.org`) — never hardcode the
   version number itself (it ages and overfits). A citation-presence check is
   deterministic and fails a stale *uncited* pin forever after; mutation-test it
   (strip the citation → expect FAIL). (cgfs 2026-06-06: AWS provider 5.x→6.x
   uncited was the verdict-1 finding; the gate now fails any uncited provider
   row.) Confirm the PEER stayed in scope.
   **Fidelity charters** (faithful reproduction / port / spec-match — e.g. a
   tutorial reproducing a book): the in/out-of-scope line is whether a finding
   affects a **valid** input. A silent miscompile/misbehaviour of a *valid*
   program is in-scope — keep the fix. A guard against pathological/malformed
   input the source *deliberately omits* (overflow on absurd operand counts,
   runaway recursion, corrupt bytecode) is out-of-scope — revert it and record
   as a residual, even when the bug is real; applying it makes the artifact
   diverge from the source it promises to reproduce. **State this scope rule in
   the PEER round brief** (not just apply it as reviewer afterward): briefed
   with it, the PEER self-classifies source-omitted hardening as a residual and
   leaves it un-edited, sparing the post-hoc revert. (2026-05-26
   introduction-to-compilers KEPT 10 valid-program miscompiles; 2026-05-27
   writing-a-compiler-in-go REVERTED 3 malformed-input guards [brief lacked the
   rule]; 2026-05-28 writing-an-interpreter-in-go — briefed with the rule, Codex
   self-classified the lone residual [user-fn arity], zero reverts.)
   **Docs-honesty overclaim (highest-yield lens on a tutorial/generator-produced
   fidelity charter, where the same skill wrote the code AND the self-serving
   charter).** The code faithfully reproduces a deliberately-limited design, so
   the dominant defect is often a PROSE OVERCLAIM in the ACs/README, not a code
   bug — a capability-breadth claim ("any X", "and other Y"), an enforced-sounding
   behavior bound ("~2:1 aspect"), or a scope claim ("the full pipeline"). The
   reproduced happy-path suite structurally cannot catch it; only the cross-vendor
   pass can. Enumerate every such claim and prove the faithful code+tests actually
   back it, else reword to the exact reproduced behavior + a residual. Corollary:
   when the PEER proposes an edit that TIGHTENS the faithful code toward the
   overclaim (adds an aspect band, flips strict→inclusive bounds to match a
   docstring), that is a divergence to REVERT — fix the charter prose, keep the
   faithful code. (2026-07-02 template-engine "any expression"/"other keywords"
   reworded; 2026-07-03 license-plate-recognition — Codex added an aspect band +
   inclusive char bounds to match AC prose, both reverted as divergences and AC6
   "~2:1"/AC13 "full pipeline" scoped honestly instead.)
   **Third case — a valid-input misbehaviour that VERBATIM-reproduces a source
   which itself leaves the feature incomplete/abandoned is a residual, not a
   fix.** "Valid-input misbehaviour = keep" assumes a *correct* version exists in
   the source to converge on; when it does not, decide by three checks: (a) does
   the repo's code match the source's published listing verbatim (not a
   reproduction divergence)? (b) does the source explicitly leave this feature
   unfinished / declare itself abandoned? (c) would the fix be substantial
   *original engineering* rather than a surgical correction? All three yes →
   record a residual and scope the charter's AC honestly (Lens-8 docs-honesty);
   do NOT diverge by re-implementing the source's unfinished feature. The
   decisive question is always "does the repo diverge from the source?" — a
   verbatim match of an incomplete source IS faithful, and the incompleteness is
   the residual. Contrast a *surgical* correction, or a fix that restores the
   source's own established intent, which is KEPT. (2026-06-06
   lets-build-a-simple-database: a neutral Codex verdict gave a real 249-key
   wrong-`select`-order counterexample, but `internal_node_split_and_insert`
   matched the abandoned cstack tutorial's Part-14 listing verbatim ["no longer
   under active development"] → headline residual, AC scoped to the tested
   7-leaf case; the SAME run KEPT a surgical 3-line duplicate-key fix that
   restored the tutorial's own cursor-based read direction.)
   **When the source ships a companion reference repo** (increasingly common —
   `/tutorial` now `curl`s reference `.py`/`.go`/… files for byte-exact code), make
   "does the repo diverge from the source?" an *executable* lens instead of reading
   every file: AST-compare each copied top-level symbol against the upstream module
   (`ast.dump(node)` structure-only — ignores formatting/comments/docstrings;
   identical dump ⇒ faithful, any divergence ⇒ inspect, with intentionally-modified
   symbols excluded from the set). One pass exhausts the extraction-fidelity lens and
   catches the silent line-drops that line-range (`sed -n`) extraction is prone to —
   far more reliable than spot-reading. (2026-06-06 build-a-large-language-model-from-
   scratch: an AST sweep of all ~30 copied symbols across 8 modules returned ALL
   FAITHFUL in one command, proving no slip beyond the two caught during the build;
   the lone Codex fix was an AC6-justified `check_if_running` robustness edit, KEPT.)
   **When the fidelity charter names TWO sources of truth that DISAGREE** (a
   primary tutorial/blog + a secondary companion repo whose code drifted from
   the prose), the repo may have faithfully reproduced the WRONG one — re-derive
   every disputed constant/operation against the charter's *named-primary*
   source, not whichever the impl happened to follow. A value matching the
   secondary while contradicting the primary is an in-scope fix toward the
   primary, NOT a faithful residual. (2026-06-28 tutorial-game-defender-rust: the
   impl took `score += 20` / `health -= 1` from the companion repo `v0.1.0`, but
   the charter's primary source — the blog — uses `score += 10` / `health = 0`;
   Codex's round-1 fix aligned to the blog and the `= 0` form also removed a real
   `u32` underflow panic on two-bullets-one-enemy. Settle the value against the
   raw primary source, e.g. de-tag its HTML, not either model's recollection.)
5. **Commit the round**: `peerreview: round <N> — <one-line summary>`
   (co-authored: HOST reviewer + PEER co-editor — name the actual two models
   and tools, e.g. Claude Code reviewer + Codex CLI co-editor, or reversed). If a round makes things
   worse, `git revert`/reset to the prior round commit and re-issue tighter
   findings. *(Under the Path-scoped git policy: do not commit; undo a bad
   round via `git checkout`/`stash` from `HEAD` instead.)*

**Bound a round that cannot finish inside the driver deadline.** The driver
writes `<out>` only when the round *ends*, so a killed round is total loss, not
partial progress — and a mid-flight tree cannot be trusted (Step 4.4). When a
first attempt overruns, or the artifact is plainly too large for one budget,
split the round by explicit file scope, name that scope in the brief, and tell
the PEER to report even if it has not exhausted it. Feed each later half the
prior half's own accepted findings so the budget goes to unexplored ground.
(2026-08-19 doc-portal-ai-platform: a 16-minute round over 13 diagrams was
killed with 22 files edited and no report; two bounded halves each finished
inside 15 minutes and independently rediscovered its findings.)

**Non-progress abort:** if a round produces no substantive improvement against
open findings (or oscillates), stop the loop and report — do not keep spending.
This is the safety valve in place of a hard round cap.

## Step 5 — Convergence contract (the only stop condition)

The loop ends when **all** hold (and never before **round 1** — the
mandatory PEER round in Step 4 must have run and been independently
re-verified):

- Every acceptance criterion in `ACTIVE_CHARTER` is met and you can point to
  durable-source and repo evidence.
- The full verification gate exits clean.
- You (reviewer) have **no remaining substantive findings** (correctness or
  security), AND each review lens you opened in Steps 1–2 has been
  *exhausted*, not just sampled. "Opened a lens, found one defect, fixed
  it, moved on" is the failure mode user pushback corrects — convergence
  requires sweeping each lens systematically. For non-trivial codebases
  the deeper sweep typically includes: enumerate every placeholder /
  wildcard zone (not just the first one that paid off); `go test -race
  -shuffle=on -count=N` (or stack-equivalent) for flake / order
  dependence; *execute* residual ACs (e.g. container builds) instead of
  only reading their contract; scan for structurally-duplicate codepaths
  one tested at the function boundary while the other actually runs in
  production; probe undocumented env-var / global coupling. Cosmetic-only
  nits do not block.
- The working tree is clean and every change is committed. *(Path-scoped
  git policy: instead — all intended edits are present in the working tree
  and peerreview committed/pushed nothing. Chat-artifact mode: commits are
  ephemeral evidence only and are removed with `CHAT_WORKSPACE` after delivery.)*
- **The PEER has explicitly returned CONVERGED** in a final verdict prompt
  (user durable directive, 2026-05-21). After the last edit-round, send
  the PEER a verdict-only prompt (no edits permitted) asking for either
  `CONVERGED — no substantive defects remain` or `NOT CONVERGED — round
  N+1 needed, [defects listed]`. Run the resolved PEER's read-only verdict with
  `<DRIVER> <repo> <verdict> <out> --verdict` (Step 0.0). Verify the diff stays
  empty; `dsh-round.sh` asserts that itself — because the harness has no tool
  allowlist — and fails the round if the tree moved, leaving the mutation in
  place for you to adjudicate rather than reverting the review out from under you.
  The HOST no longer declares convergence
  unilaterally — even a clean gate + reviewer-judged exhausted lenses is
  insufficient if the PEER still sees residuals. If the PEER returns NOT
  CONVERGED, dispatch round N+1 against its named defects and repeat
  the verdict prompt after. Continue until the PEER says CONVERGED on the
  committed state. This codifies the "second-model agreement" the
  mandatory PEER round was supposed to provide but did not — running
  one edit-round once and not asking for an explicit verdict is the
  failure mode this rule corrects.
  - **The verdict prompt MUST be neutral — no anchoring (user directive,
    2026-05-23).** Present only raw, neutral facts (the gate's actual command
    output) and explicitly invite the PEER to find more; do NOT pre-load your own
    conclusions ("all green, lenses swept clean, README honest, no findings").
    A leading verdict biases Codex toward agreement and manufactures false-fast
    convergence. orderflow-go (2026-05-23): the first review converged at
    **round 1** under an anchored verdict (Codex was also handed the reviewer's
    findings as its agenda); a user-prompted re-review with a **neutral verdict
    + a fresh independent Codex session** found **6 real defects over 5 rounds**
    (cross-form submission id, no-sid skip-ahead, zero-step panic, unknown
    branch operator, branched-over step access, 422-Back + single-value
    over-persistence) and refuted 1 Codex-proposed regression. One round on a
    same-session / self-serving repo (same model wrote the code AND its prior
    review) is a yellow flag — re-prove convergence neutrally, do not rubber-stamp.
  - **A peer usage-limit error during the verdict prompt is a "verdict-pending"
    residual, NOT a silent CONVERGED (student-mgmt-conformance 2026-05-29).**
    Any peer CLI can return a usage-limit error instead of rendering
    the verdict; treat them identically. This is a transient
    external-system failure, not a NOT-CONVERGED outcome. **The convergence
    contract is NOT satisfied** (no explicit CONVERGED line). Do NOT fabricate
    a verdict, do NOT silently treat reviewer-side green as the verdict, and do
    NOT loop while waiting for the reset (the rate-limit window is hours, not
    seconds). Resolve by: (a) committing any reviewer-applied edits made before
    the verdict was dispatched, (b) pushing the working tree per Step 6, (c)
    recording the verdict-pending state explicitly in the report (cite the reset
    time the CLI returned), and (d) telling the user to re-run
    `/peerreview` against the same repo after the reset — the loop will resume
    from the current committed state and complete the verdict. The
    Step 6 push is unconditional regardless; the absent CONVERGED line is the
    residual the user accepts when re-invoking, not silently inherited as
    "converged". Never re-ladder to another peer while the resolved side is blocked.
  - **The verdict prompt must make READING explicit — a read-only sandbox still
    permits reading every file with the PEER's Read tool; "do not run commands"
    means no mutating commands, not "cannot read" (Reporting-Platform-CC-Sandbox
    architecture 2026-08-09). A verdict returned as NOT CONVERGED premised on
    "review is impossible because I may not run commands" is a wrong-premise
    verdict, the same class as the gate-count miscount rule above: re-dispatch
    the verdict once with the corrected instruction (state plainly that reading
    is allowed and expected; only edits/commits/pushes/remotes are forbidden),
    never treat it as a real residual and never edit the artifact to satisfy it.

Anything not fixable without changing host state / running real
infrastructure / external review is **not** a blocker — it is recorded as a
residual, not papered over.

**A residual's blast-radius claim is itself a defect surface — sweep the whole
residual set when a verdict flags one, and settle behavioral disputes by
execution, not argument.** Two recurring failure modes here: (1) *overclaim
cascade* — when a verdict round flags one mis-scoped claim (a residual's "it's
display-only / can't affect balances / isn't reachable", an AC's "X validates
and applies", a goal's "pins every behavior"), scope the fix to the WHOLE
paragraph / named section / residual list and re-audit every parallel claim in
the same pass; a verdict catching one is evidence the surrounding prose makes
the same mistake at another surface, and fixing only the cited one burns the
next verdict round (recurred across cdd-prd, cdd-conformance, and fidelity-impl
profiles). Each blast-radius claim must be re-derived against the actual call
path, not asserted. (2) *execution tiebreaker* — when HOST and PEER disagree on
what code does at runtime (e.g. "the reversed decode is display-only" vs "it
changes settlement", "a negative amount steals" vs "it aborts at the encode
assert"), **run it** in the gate environment and quote the output; both models'
confident reasoning can be wrong at once, and only execution is authoritative.
(3) *residual laundering* — rewording an artifact to admit a defect is not
fixing it. When a verdict says a gate cannot detect X, "the gate now says it
cannot detect X" is documentation, and the next verdict repeats the finding.
Ask whether X's CAUSE is removable inside the charter's scope before reaching
for the honest-scoping rule; that rule is for causes you do not own, which is
why a source-fidelity residual is right — its cause lives in the reproduced
source. (2026-08-19 doc-permit: a fidelity gate could not see visual drift
between the committed PPTX and PDF because renders looked nondeterministic, and
two rounds went into loosening the tolerance and then disclosing the gap. The
cause was two labels styled italic in a face with no italic, so LibreOffice
synthesised an oblique differently per run; dropping that one style made 6
renders 210/210 pixel-identical and an exact oracle valid. The PEER refused
"we disclose it" twice before the cause was looked for.)

## Step 6 — Report & push (always)

Produce an honest report:

- Per-AC status (met / met-with-caveat / not met + why).
- **HOST/PEER and the peer tier that actually ran.** On tier 2, name every
  tier-1 peer that was unreachable and why — an undisclosed degradation reads
  as a full-strength review.
- Rounds actually run vs forecast, and why it converged or aborted.
- Verification gate output.
- Residuals (explicitly out of scope; not "perfect", and say so).

When Step 1.5 detected a `cdd-*` profile, **finish every terminal report by
rendering the canonical CDD progress map** from
`~/personal/cdd-skills/skills/cdd/SKILL.md` § Progress map. `/peerreview` owns
this update because only it knows the terminal review outcome: explicit
cross-vendor `CONVERGED` → `✓ reviewed` (tier 2 still counts, with the tier
named); required-peer failure, verdict-pending,
or non-progress abort → `☐ review owed`. Never advance the
project's `PLAN.md` lifecycle status merely because its repo review finished.

Before the terminal report, always clean review-owned charter state with
`bash ~/personal/peerreview-skills/scripts/charter-temp.sh clean "$ACTIVE_CHARTER"`
(on convergence, required-pair failure, non-progress abort, dry-run, or error).
A pre-existing repo-root `PROBLEM.md` is not review-owned and is never removed.

On convergence, land a branch-mode review with
`scripts/delivery-branch.sh land <repo> <slug> <msgfile>` — one squashed commit
on the delivery branch — then push that branch and create/push the anchor tag.
The review branch is kept locally; its round commits remain the detailed record.

Then **always commit and push the reviewed repo** — every run, on
convergence *or* non-progress abort, without asking. Push the working
branch to its tracking remote and state the branch/remote in the report.
Fail loud: if there is no remote, the push is rejected, or auth fails,
report it explicitly — never silently skip the push. (This is unconditional
because the user durably asked for it; do not re-prompt.) **Exception:**
under the **Path-scoped git policy** (`~/projects`), do the opposite — do
not commit or push; leave edits uncommitted/untracked and say so plainly.
The absent push there is the expected outcome, not a failure to flag.
**Chat-artifact exception:** no remote, push, or anchor is created. Return the
reviewed artifact and report, clean both `ACTIVE_CHARTER` and `CHAT_WORKSPACE`,
and state that the review was ephemeral.

After true cross-vendor convergence (not abort and not `--chat`), run
`bash ~/personal/peerreview-skills/scripts/review-anchor.sh create <repo> <full|incremental>`;
push the returned tag exactly. It marks the reviewed commit; round commits retain
detail. Under `~/projects`, create no tag.

Never claim "perfect" — claim "converged against the charter, gates green,
residuals listed."

## After completion: evolve the methodology (no logs)

peerreview evolution is a **filter, not a per-run log** (`CONSTITUTION.md`
Article 1): a lesson either passes the constitution and is edited into a skill
file, or it fails and nothing happens. There is no `evolution/` log to append
to, and no every-run self-evolve+push (which is why the old cross-environment /
concurrent-sibling race apparatus is gone).

If this run surfaced a **durable, generalizable** lesson — a review lens that
paid off, a recurring defect class the gate structurally missed, a skill bug or
stale path — invoke **`/peerreview-evolve`** (post-review mode). It filters the
candidate through `CONSTITUTION.md` (proof matched to the claim's scope), edits the
matching `peerreview-approach-*` lens or main Step, validates the size gate, and
commits. A one-off `CONVERGED, no durable lesson` run evolves **nothing** — the
trigger is pull-based, so a non-actionable run simply leaves no trace. The
git history of the skills is the record; never re-create a patterns/index log.

## Hard rules

- The HOST owns git. The PEER co-editor never commits, pushes, or touches remotes.
- The PEER is whatever `select-peer.sh` resolves: tier-1 Claude Code ↔ Codex CLI,
  falling to tier-2 `dsh` (CDD-harnessed repos) or Pi (all others) only when no
  tier-1 peer is reachable, and never to the HOST's own vendor. Any
  missing/auth/quota blocker fails closed; no same-HOST substitute (Step 0.0).
- Every round: review the real diff + re-run the gate. Never trust self-reports
  — including fact-checking any identifier/API the PEER claims it "corrected".
- **Any live finding you DISMISS must be verified against the cited line — the
  PEER's, *and one you raised yourself*.** Never wave it off as "a misread" or
  "out of (edit) scope." A finding pointing at a *sibling* repo outside your edit
  scope still has to be confirmed/refuted by reading the exact file:line, then
  recorded as a flagged cross-repo defect if real — not silently dropped; a wrong
  dismissal persists the defect until the sibling is reviewed directly.
  (2026-06-18 mvcc-prd: a Codex finding that `mvcc-conformance/gc/README.md`
  claimed "tombstone collapses chain / reclaimed=2" was refuted as a misread +
  out-of-scope; the direct review a day later confirmed both stale claims — the
  dismissal was the error.) **A finding YOU surfaced and then resolved in your own
  favour goes into the verdict prompt as an open question, never omitted as
  settled**: give both readings and say plainly the PEER is not asked to agree.
  That does not re-create the orderflow-go anchoring failure — one contested item
  with an explicit invitation to disagree is not an agenda handoff. (ArchSift contract
  2026-08-15: the host's own completeness sweep found the reference tool's write-boundary
  redaction had no ArchSift counterpart, then argued it away as already covered by
  the public-repo sanitised-derivative ban; surfaced as an open question, Codex
  returned NOT CONVERGED — that ban governs publication, not the record FR-011
  emits for circulation to review boards — and the next round landed NFR-009.
  Self-dismissal, not peer dismissal, was the near-miss.)
- Fail loud and closed: auto-create a fresh active charter; absent or conflicting
  durable intent → stop, never infer it from implementation. Missing peer/auth,
  quota, or empty output → disclose the blocker and stop after charter cleanup.
- Rounds are forecast for transparency; **convergence**, not a count, ends
  it — but with a hard **floor of 1** peer round (Step 4 mandatory round;
  never converge at round 0).
- "Ready" = charter satisfied + gates green + no substantive findings. Not "perfect".
- **Methodology evolution is a filter, not a log** (`CONSTITUTION.md` Article 1):
  no `evolution/` log, no every-run self-evolve+push. A durable lesson is routed
  through `/peerreview-evolve`, which gates it against the constitution and
  commits; a non-actionable run leaves no trace.
- Every repository run ends by pushing the reviewed repo (fail loud if a push cannot
  complete). **Exceptions:** under the **Path-scoped git policy** the
  *reviewed repo* is never committed or pushed (left for manual Windows-side
  commit). **Chat-artifact mode is also non-publishing by design:** its private
  wrapper is deleted after the converged artifact is returned. Evolving
  `peerreview-skills` is separate and pull-based, not part of every run — see
  § After completion.

$ARGUMENTS: optional `repo_path` (default: cwd), `--chat`, and `--dry-run`.
