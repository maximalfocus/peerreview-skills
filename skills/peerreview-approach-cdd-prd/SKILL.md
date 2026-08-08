---
name: peerreview-approach-cdd-prd
description: "Peer-review lenses for CDD `{project}-prd/` repos — PRD↔PLAN traceability, tech-stack data integrity, requirements coverage, approach rationale presence"
disable-model-invocation: true
---

# Peer-review approach: CDD PRD repo

Reference loaded by `/peerreview` when Step 1.5 detects a `{project}-prd/`-style repo:
markers are a top-level `PRD.md` plus one or more `PLAN-{NNN}-{slug}.md` files
(typically with a `PLAN.md` index). This is the artifact `/cdd-plan` produces.

The dominant defect class for these repos is **requirements↔plan drift**: a PRD
requirement that does not map to any PLAN category, OR a PLAN category that has
no PRD anchor (scope drift). Internal consistency of PRD prose comes second.

## Brief the PEER with these lenses

When you reach Step 2 of `/peerreview` (working out the per-AC review strategy)
and Step 4 (briefing the PEER), use these lenses as the focus areas:

### Lens 1 — Requirements ↔ Plan coverage closure (dominant defect class)

Enumerate every PRD requirement and every PLAN category, then prove a bijection
modulo declared non-goals:

- Every `## Feature:` / `## User model` / `## API surface` / `## Business rules` /
  `## Non-functional requirements` row in `PRD.md` MUST map to **at least one**
  PLAN category row (or appear in PLAN's `## Out of scope / Non-goals` table).
- Every PLAN `## Categories` / `## Stack categories` row MUST trace to a PRD
  requirement or section (no plan rows invented by the planner without a PRD
  anchor — that is scope drift).
- Decision boundaries declared in PLAN MUST be consistent with PRD non-goals
  (a PLAN that says "implementation may decide caching strategy autonomously"
  cannot coexist with a PRD that lists caching as an NFR target).
- When the PRD/PLAN declares an **enumerated set of implementation-defined
  mechanisms** ("the impl may use a count field / the waste-one-slot trick /
  monotonic sequence numbers"), validate **each listed member individually**
  against the *conjunction* of every pinned invariant — not just "is the choice
  free?". A member that no implementation can satisfy while honoring all pinned
  invariants is a contradiction masquerading as a free choice, and the
  coverage/closure pass (which only checks *that* the mechanism is impl-defined)
  will not see it. ringbuffer-prd 2026-06-13: "waste-one-slot is impl-defined"
  collided with BR-4 (usable capacity == N) **and** the Allocation NFR
  (pre-allocate exactly N slots) — a waste-one-slot impl needs N+1 physical slots
  for N usable, so it violated one or the other; surfaced only at neutral verdict
  round 2. Fix is usually to relax the over-specified invariant (here: permit N or
  N+1 slots), not to drop the mechanism.

Treat this as a reference-closure problem (the same lens applied to derived
golden-file suites in `/peerreview` Step 2): the PRD is the *upstream* and the
PLAN is the *derived* artifact. An unmapped upstream requirement is the dominant
defect, not internal PRD prose inconsistency.

**Coverage-adding-round prose-staleness sweep (post-round).** When *this run's*
edits ADD coverage for a previously-unmapped requirement (a new category
behavior, or a new `## Non-functional requirements`→category mapping), re-read
that requirement's PRD prose for a now-stale description that says it is NOT
asserted — e.g. an NFR row reading "implementation-defined", "operational only",
"race-checked operationally", "not asserted by conformance". Closing the
coverage gap and leaving the upstream prose saying "not covered" creates a fresh
self-contradiction the closure pass (which only checks *that* a mapping exists)
will not re-flag. Tighten the prose to match the new coverage (invariant
asserted vs mechanism implementation-defined vs race-freedom operational are
distinct claims that can coexist precisely). simplekafka-prd 2026-05-29: the
round-1 `Concurrent clients` NFR coverage addition left the PRD row still
declaring concurrency correctness "implementation-defined, race-checked
operationally" — reviewer-caught after the edit round.

This sweep fires equally when a round *scopes or corrects an invariant* (not only
when it adds coverage): a determinism/invariant claim is typically restated in BOTH
a prose invariant section AND an NFR **table row — once in PRD.md and once in the
PLAN**, so a fix to the prose leaves the NFR-row twin(s) stale, the canonical
round-2 survivor. Grep the NFR tables specifically after any invariant edit, not
just the prose. bloomfilter-prd 2026-06-15: round 1 corrected the counting-filter
determinism *invariant* prose but left both the PRD and PLAN Determinism **NFR
rows** still claiming `(m,k)+item-set` determinism over the counter array (true
only for the plain bit array; the counter array is operation-sequence-determined);
the neutral verdict caught both at once.

**When a round PINS a value/policy that was previously loose or
authoring-decidable, the sweep extends past NFR tables to four more site
classes — and the verdict drains them one per round if you don't sweep them
together:** (a) **worked-example arithmetic** that silently depended on the old
looseness (an example "demonstrating" X that the now-pinned rule makes
impossible — e.g. a too-small key set that cannot actually show
history-dependence once the split policy is pinned); (b) **`## Decision
boundaries` "authoring may decide X" lists AND the charter `## Non-goals`** — if
the PRD now pins X, leaving it as authoring-decidable is a *determinism
contradiction* (a golden-author could pick a different valid X and break the
pinned canonical artifact), not mere stale prose; (c) **risk-row
rejected-alternative example labels** — pinning a policy that is itself, say,
"right-heavy" makes "right-biased split" a wrong label for the *rejected*
alternative it now describes; (d) any prose that called the pinned thing the
"policy direction" while implying the exact value stays free. bptree-prd
2026-06-16: round 1 pinned the leaf-split distribution (`⌊(B+1)/2⌋`) + legal even
`B`; that single pin then exposed a stale site per verdict round — the
history-dependence example (R2), the "authoring may decide split-index"
deferral across PLAN + charter (R3), and the "right-biased split" risk label
(R4) — 3 verdict rounds that one combined post-pin sweep would have collapsed.

**When a coverage-adding round ADDS a whole new category** (not just an
NFR→category mapping), two further prose sites go stale that the closure pass
(which only checks *that* a mapping exists) cannot see: (1) the PLAN
`## Implementation order` rationale that quantifies over the category set — a
"X first because **every** other behavior depends on X" line is falsified the
moment you add a category that does NOT depend on X (a `health`/liveness probe,
a static-config endpoint); and (2) the **source BR's sibling guarantees** that
the new category still doesn't cover — e.g. adding a `health` category for the
endpoint while BR-2's *production unguessability* guarantee remains mapped to
nothing and unmarked as a non-goal. Sweep both after any category-add.
urlshortener-demo-prd 2026-06-07: both were verdict-1 findings — the impl-order
"every behavior depends on a link" went false after round 1 added a
link-independent `health` category, and BR-2's "unguessable" production property
(correctly **unmappable** — not deterministically golden-able) needed an explicit
"not golden-tested by design" NFR row.

**AC1 coverage closure is 3-state, and the neutral verdict re-flags the third.**
A requirement is closed by exactly one of: (a) it maps to ≥1 PLAN category;
(b) it appears in `## Out of scope`; OR (c) — for an NFR inherently **not
deterministically golden-able** (a best-effort perf target, a production-only
property like code unguessability) — it carries an explicit *"not golden-tested
by design" + stated reason* row. State (c) is real closure, but the common binary
AC1 wording ("maps to a category OR in Out of scope") under-enumerates it, so the
neutral verdict reads it strictly and re-flags any such NFR as an apparent gap.
Resolution: enumerate state (c) in AC1 **and** make the NFR's by-design
declaration explicit (a *silent* "not asserted" with no reason is still a gap;
don't "fix" it by dumping a real perf target into `## Out of scope` — that is a
category error, an NFR target is not an excluded feature). urlshortener-demo-prd
hit this class **twice, one per run** — unguessability (2026-06-07) and redirect
latency (2026-06-08 re-run); the second only surfaced because AC1 still listed
two states and latency's row said a bare "not golden-tested" without "by design".

**Phrase the coverage-map intro as "maps to exactly one coverage STATE", not
"exactly one category" — and not "at least one category".** A requirement that
legitimately maps to *multiple* categories (e.g. `heapify`/`clear` → both an
operations and a structure category) makes a literal "exactly one category"
false; the reflexive fix to "at least one category" then silently contradicts
the charter's 3-state AC1 ("closed by exactly one of (a/b/c)"). The phrasing that
satisfies both is **"maps to exactly one coverage state: one-or-more categories,
Out-of-scope, or untested-by-design"** — the *state* is unique even when the
category count isn't. (minheap-prd 2026-06-13: round 1 changed "exactly one
category"→"at least one"; the round-2 deeper re-run reconciled it to "exactly one
coverage state".)

**Category-precondition closure.** For each PLAN category, verify its *setup
preconditions* are established by the spec, not silently assumed. The dominant
instance in multi-process / distributed-system PRDs: a category that drives
**node B** after an action on **node A** (produce-to-leader-then-read-follower,
"member C sees the write", "replica knows it's a replica") requires the spec to
define how the needed state reaches B — topic/membership/assignment
**propagation**. A category whose assertions depend on B knowing what was sent
to A is *ill-founded* until that propagation path is a stated rule. This is a
deeper class than coverage closure (the category exists and maps to a
requirement — but its precondition is unspecified). simplekafka-prd 2026-05-29
(re-run, HIGH): the `replication` category created a topic on a 2-broker cluster
and expected the follower to accept `REPLICATE`, but no `CREATE_TOPIC`
cross-broker propagation was specified (the reference's `TOPIC_NOTIFICATION` was
dropped in adaptation) — the whole category was unauthorable until a propagation
rule was added.

### Lens 2 — Tech stack data integrity

`/cdd-plan` Step 4 requires the `## Technology choices` table to have every row
filled before the plan can be approved (no TBD/TODO/blank). Verify in the gate:

- Every row in the Technology choices table has a concrete value (not `TBD`,
  not `TODO`, not blank, not `?`).
- The declared Database / Runtime / Framework / Deployment target / Testing
  framework / Auth provider / Cache-queue choices are **internally consistent**
  with the PRD's NFR section (e.g., a PRD that requires <50ms p99 latency vs.
  a Database choice of "SQLite on a single host" is a contradiction the gate
  should flag).
- Stack-category boundary types in PLAN match the declared Framework (e.g., a
  `spring-boot` stack row should not declare an Angular-component boundary).

### Lens 3 — Approach rationale presence **and soundness**

Per the 2026-05-20 single-gate refactor, `/cdd-plan` no longer pauses at an
"Approach approved" gate; alternatives considered MUST be recorded in PLAN.md's
`## Approach` section. **Presence** — verify:

- `## Approach` exists in the active PLAN file.
- It enumerates ≥2 considered alternatives with explicit tradeoffs.
- It names the chosen approach and gives a why-this-over-alternatives sentence.
- If recommendation was close among options, surfaced uncertainty is present
  (per `/cdd-plan` Step 2: "If the recommendation is genuinely close among
  options, surface that uncertainty in `## Approach`").

A `## Approach` section with one option and no alternatives is a defect — the
planner silently picked instead of recording the comparison.

**Soundness** — presence is necessary, not sufficient: a well-formed `## Approach`
can still rest on an assumption the PRD's *own pinned requirements* falsify.
Test the recorded approach adversarially **against the charter** — this is
charter-conformance, NOT the open "is there a *better* design?" critique (that is
`/ultrareview` / human-review scope, per **What NOT to flag** — do not invent a
superior approach or expand scope). Three checks, each firing ONLY on a *pinned*
BR/NFR or a *recorded* dismissal:

- **Load-bearing assumption vs a pinned BR/NFR.** Name the assumption the chosen
  approach depends on (a consistency/ordering guarantee, a scale ceiling, a
  single-writer premise, an at-most-once/at-least-once delivery model) and confirm
  no BR/NFR contradicts it. An approach whose key assumption a pinned NFR falsifies
  is invisible to both the presence check and coverage-closure (both only confirm
  the section *exists* / requirements *map* — neither reads the assumption).
- **Dismissal by a false reason.** For each rejected alternative, verify its stated
  rejection reason isn't itself contradicted by the PRD — a "too slow" dismissal
  with no latency NFR, a "won't scale" dismissal at a scale `## Out of scope`
  already excludes. A wrong dismissal reason makes the comparison that justifies
  the whole plan unsound, even though every alternative was dutifully listed.
- **Unaddressed real-world failure inside a pinned NFR** — concurrency, partial
  failure, restart/crash-recovery, or operational reality that a pinned NFR
  demands but the approach prose silently assumes away (a pinned "concurrent
  clients" NFR against an approach whose narrative presumes a single writer). This
  is the same "where does it fail under real conditions" axis Lens 7 drives for
  math PRDs, applied to the approach narrative rather than the formulas.

The tell that separates this from scope-creep: every flag names the specific
pinned requirement (or recorded dismissal) the approach collides with. No such
anchor ⇒ it is a design opinion, not a charter defect — do not raise it.

### Lens 4 — PRD structural completeness

The PRD MUST contain (or explicitly mark N/A) each of: Overview, User model,
Data model, API / CLI surface, Business rules, UI/screens (full-stack only),
Non-functional requirements, Out of scope. Missing sections without an N/A
marker are a structural defect.

For brownfield extensions, `## Feature: {name}` sections MUST include a
`> *Added {YYYY-MM-DD} — {context}*` line (per `/cdd-plan` PRD organization
strategy). Missing the dated context line is a defect.

For desktop / GUI / CLI / editor apps where state lives in both **persisted
files** and **ephemeral runtime memory**, the `## Data model` section MUST
distinguish persisted fields (saved with the file format) from ephemeral
application state (cursor, selection, undo stack, dirty flag, tool state,
active-frame/layer/color indices, viewport pan/zoom). A `Document` bullet
that quietly lists both classes side by side is a defect — round-trip
behavior, file-format schema, and conformance categories all key off the
persisted/ephemeral split. The reviewer should flag any state listed under
the Document/persisted root that is not actually serialized by the file
format's golden-file round-trip tests in PLAN.

### Lens 5 — Diagram-to-text reconciliation

If PRD.md embeds Mermaid blocks or references diagrams in `diagrams/`:

- Every named resource/role/entity/subnet/port shown in a diagram MUST exist
  in the corresponding PRD text section (data model, user model, etc.).
- Every PRD-declared entity that warrants a diagram (per the diagram-of-record
  list in PLAN) MUST have one. Missing diagrams are a defect when the PRD
  itself cites them.
- Mermaid blocks parse cleanly (no syntax errors — the gate runs
  `mermaid-cli`/`mmdc` to validate if available).
- **Link-integrity gates must also flag `[[wikilink]]`-style refs, not just
  `](path)` markdown links.** Scaffolded sibling `{project}-architecture/` ADR
  repos (cdd-plan / architecture-approach output) routinely carry Obsidian-style
  `[[0002-name]]` cross-refs in their `## Related` sections — these are NOT
  clickable/resolvable on GitHub, but a gate that only validates `](…)` targets
  passes them green. Add a `grep -E '\[\[[^]]+\]\]'` check (must be empty) wherever
  link integrity is gated. (trie-architecture 2026-06-15: a converged-at-scaffold
  AC5 gate was blind to 5 `[[…]]` ADR refs; the re-review caught + converted them.)

### Lens 6 — PLAN ↔ sibling-architecture ADR consistency

`/cdd-plan` now scaffolds a sibling `{project}-architecture/` repo (Proposed
ADR stubs) for almost every project, so a `{project}-prd` PLAN/PRD routinely
*references* decisions that are authoritatively pinned in those ADRs (fill
rules, comparators, encoding strategy, interface shapes). The ADRs' internal
correctness is a **non-goal** of the PRD review — but the PLAN/PRD must not
**contradict** them. Read the sibling repo's ADRs (when checked out at
`../{project}-architecture/adr/`) and verify every PLAN/PRD claim that restates
an ADR decision agrees with it. This is a cross-repo lens the gate's
single-repo greps cannot see, and it is a live co-editor-edit failure mode: a
co-editor "tightening" a PLAN risk-mitigation can silently invert an ADR
decision (tinyrenderer-prd 2026-06-05: a Codex round changed the PNG-encoder
mitigation to pin encoder *byte-equality*, contradicting ADR-0007's
decoded-pixel comparison + the Golden-portability NFR — reviewer-reverted at
Step 4.4 because they had read the sibling ADR). When the sibling repo is not
checked out, record the cross-repo check as a residual rather than skipping it
silently.

**Reconcile-ALL blast radius (whole-family, token-context-aware).** When an edit
*changes a contract element* — tightens a domain, REMOVES/renames an error kind,
changes a count — reconcile EVERY surface that restates it **in one pass**, across
**all** sibling repos on disk: the PRD prose AND its tables, the PLAN
(Categories/Risks/NFR-trace/impl-order), every `{project}-architecture` ADR
`## Decision` + `## Consequences`, and (for a conformance review) the suite's
README/coverage-tracking/ambiguity-report/charter + count totals. A partial
reconcile (the one obvious surface fixed, siblings left stale) is the canonical
verdict-round-N finding, and the neutral verdict drains **one surface per round** —
budget extra verdict rounds for a contract *removal*, the worst case. Two operational
rules: (1) grep every repo for the changed concept, not just the most-related file;
(2) be **token-context-aware** — the same token can be legit in one role and stale in
another (a blanket replace breaks the legit use). (tagged-union 2026-06-16, seen from
BOTH sides: the PRD review's round 1 reconciled ADR-0002/0003 but left ADR-0005/0006
stale → verdict 2, then a 2⁵³ off-by-one → verdict 3. The conformance review then
REMOVED a dead error kind (`non_finite_result`, unreachable) and the cascade drained
one surface per verdict — counts [v2], README+PLAN [v3] — across conformance+PRD+PLAN+
2 ADRs; `non-finite` was legit for `number()` [non_finite_number, kept] but stale for
`eval` [non_finite_result, removed], so each fix was surgical, not a global replace.)

**Lens 6 generalizes to EVERY built sibling, not just architecture ADRs — and
RUN it, don't defer it, when the siblings are on disk.** Once a `{project}-prd`
has progressed through the pipeline, its siblings (`-conformance`,
`-frontend-conformance`, the impl repos, `-infra`, `-infra-conformance`) hold the
*authoritative built reality* the PLAN/PRD merely forecast. Reconcile against all
of them: **(a) tech-stack pins** in `## Technology choices` vs the impl manifests
(`pyproject.toml`/`uv.lock`, `package.json`/lockfile, `docker-compose` image tags,
`src/styles.css` tokens) — a claimed component the impl does NOT use (e.g. Alembic
listed but no migrations) or a version mismatch is a defect; **(b) authored
category/count drift** — a conformance category the suites actually contain but the
plan never forecast (a mandatory `architecture/dependencies` fitness category is
the recurring one — it traces to the layering ADR and is *added during authoring*,
so a pre-authoring PLAN never lists it), plus stated totals that no longer match
(`Est.`-column forecast vs the suites' coverage-doc counts); **(c) ADR
cross-references** point at the *correct local* ADR (a PLAN citing "ADR-0004" for a
deploy decision when ADR-0004 is the frontend-layering ADR and ADR-0005 is the
deploy ADR is a real mis-pointer); **(d) deploy topology terms** vs the actual IaC
+ infra-conformance (`network.tf` had only public/private tiers and the
`aws_db_subnet_group` over `aws_subnet.private[*]`, so a PLAN saying RDS sits in
"isolated subnets" contradicts both the Terraform and the deploy ADR). The
decisive failure mode to avoid: **a PLAN's own "to be scaffolded post-approval"
wording (and a charter residual copied from it) LAGS reality** — do not trust it;
`ls ~/personal/{project}-*` (the siblings live as sibling dirs, not always `../`) and
reconcile against what actually exists. For **forecast-vs-authored count drift**,
prefer an **additive "As-authored sibling reconciliation" section** that records
the real category set + totals while leaving the pre-authoring `Est.` arithmetic
intact for the single-repo gate — rewriting the estimate numbers silently breaks
the gate's `core+stack+frontend=total` check. (urlshortener-demo-prd 2026-06-10
cross-repo re-run: the 2026-06-08 pass DEFERRED Lens 6 as a residual trusting the
PLAN's "not yet scaffolded" wording — but all 7 siblings already existed and the
deploy had run; the owed cross-repo pass then found 4 real divergences in one
Codex round + 1 neutral-verdict round — unused-Alembic, the unforecast
`architecture/dependencies` category [5 backend + 3 frontend goldens, 33+19=52
as-authored vs the `≈38` estimate], the ADR-0004→0005 mis-pointer, and
isolated→private subnets.)

### Lens 7 — Numeric / geometry well-definedness & totality (math/renderer/simulation PRDs)

When the PRD is a **math contract** — a renderer, rasterizer, raytracer, physics/
simulation, codec, or any spec whose business rules are formulas — the dominant
defect class is not coverage but **partial functions**: a BR that divides,
normalizes, inverts, indexes, or square-roots an input that can legitimately be
zero/degenerate/out-of-range for an input the spec *accepts*. Sweep it exhaustively:

- **Every division / normalization / inverse / sqrt** must have its denominator/
  argument proven non-zero — *either* enforced by a CLI/scene validation rule (a
  well-definedness invariant: unit vectors, non-parallel/non-zero bases,
  non-degenerate cameras) *or* defined by the BR for the degenerate value. List
  them and check each. Common hits: distance/`perpWallDist == 0`, depth/`transformY
  == 0`, an inverse matrix determinant from degenerate basis vectors, a size that
  truncates to `0` **at the small dimensions golden suites deliberately use**.
- **Boundary/extremal inputs** must be total: smallest golden dimensions, largest
  time-step / parameter, on-grid-line / on-edge positions, out-of-bounds indices,
  empty/opposing input sets. "Accepted by the CLI ⇒ must produce a defined output."
- **Invariant-preservation across transforms (the subtle one):** if you add a
  precondition that one transform's input must satisfy (e.g. render requires
  strictly-interior position), verify **every other transform that produces that
  type preserves it** — a movement/step that can output a state its own render
  rejects is a self-contradiction. Prefer making the consumer *total* over adding a
  producer-side invariant the producer can violate.

- **Concurrency/transactional contracts — "invariant preserved" attached to a
  serializable/SSI abort is a category error.** When a spec's worked example claims an
  application invariant *holds* because the engine aborted a transaction (write-skew /
  SSI / serializability), re-derive the example under **EVERY valid victim/commit
  ordering**, not just the one drawn: serializability guarantees only that the committed
  history equals *some* serial order, NOT that any application constraint is preserved.
  A second-committer-aborts rule that leaves the *first* committer's lopsided write can
  still violate the app constraint under the reverse order. (mvcc-prd 2026-06-18: S6
  pinned `A=50,B=50, A+B≥0`, T1 writes `A=-10`, T2 writes `B=-60`; "SSI ⇒ constraint
  holds" is true only T1-first — T2-first aborts T1 → `A+B=-10`. Surfaced only at the
  neutral verdict by re-deriving both orderings; on a **frozen** contract it is a
  flagged CONTRACT_ISSUE, not a fix.)

This family peels **one layer per verdict round** — each fix exposes the next
degenerate case (raycaster-prd 2026-06-05: 7 rounds, every verdict a real defect;
raytracer-prd 2026-05-31 re-run: 13 defects). Do not read a NOT-CONVERGED streak
here as oscillation; it is the family draining. Watch specifically for a *fix that
introduces the next contradiction* (raycaster R3's position invariant was violated
by R4's own movement output) — re-run the totality sweep against each fix.

## Verification gate amendments

Append to the charter's `## Verification` block (run every round):

- `grep -nE '^\|.*(TBD|TODO|FIXME)' PLAN-*.md` → must be empty (TBD/TODO inside a
  table row). **Anchor to `^\|`.** An earlier version of this line —
  `'^\| .*TBD|TODO|^\| .*\|\s*\|$'` — has an alternation-precedence bug: the
  bare `TODO` branch matches *any* prose line containing "TODO" and
  false-positives on the PLAN's own `**…no TBD, no TODO, no blank.**`
  assertion (this firing wastes round budget — exactly what Step 0.5's gate
  self-test is for). Empty-cell check is a **separate** command. The naïve form
  `grep -nE '\|[[:space:]]*\|' PLAN-*.md | grep -vE '\|[-:]+\|'` **false-positives
  on the headerless key/value-table idiom** `| | |` (an all-empty header row) that
  cdd-plan *deploy* plans (`PLAN-NNN-deploy.md`) use for the target/region/lifecycle
  metadata block — Step 0.5 catches it the moment a deploy plan is in scope. The
  genuine defect class is a *partially*-blank DATA row (a label with a blank value,
  `| Account |  |`), not an all-empty header; flag only a row that **mixes empty and
  non-empty cells**, tolerating separator rows and all-empty headerless rows
  (per-cell split in python/awk, not a bare grep). Mutation-test it both ways
  (inject `| label | |` → must FAIL; `| | |` → must PASS). urlshortener-demo-prd
  2026-06-08 (PLAN-002 stale-charter extension): the bare-grep gate failed at
  baseline on PLAN-002's `| | |` target table.
- A short script that diffs PRD section count vs PLAN row count and reports
  unmapped requirements. (Build it inline if the repo does not ship one.)
- If the PLAN states a golden-file/test **count**, reconcile it across **every
  file that restates it**, not just the detail file. The count typically lives
  in ≥2 places — the `PLAN.md` index row ("~N golden files") AND the
  `PLAN-NNN` detail (per-category `Est. tests` column + a stated subtotal/total)
  — so a count-arithmetic script must sum the per-category column AND assert the
  index row equals that sum. Fixing only the detail leaves the index stale
  (urlshortener-prd 2026-05-23: round 1 fixed PLAN-001's `~164→~174` but the
  PLAN.md index stayed `~164`, a fresh cross-file contradiction the
  detail-only gate missed). **Anchor the sum to the `Est. tests` column
  specifically** — a categories table usually has a *second* numeric column
  (`Deps`), so a naïve "sum every integer in the table" miscounts
  (orderflow-prd 2026-05-23: a Deps-summing regex reported `22` vs the true
  `35` — a self-inflicted gate false-positive, exactly the Step 0.5
  self-test's purpose). **When extracting the *stated* total, anchor on the
  keyword + integer (`Total ... [0-9]+`), never on the approx glyph** — cdd-plan
  writes totals as "`≈ N`"/"`~ N`" and `≈` is multibyte, so a regex like
  `.[~≈] *[0-9]+` silently extracts nothing (a false-negative "MISSING" that
  reads as a pass-by-absence). raytracer-prd 2026-05-31: the Step 0.5 self-test
  caught both a real `124≠123` arithmetic defect AND this glyph-anchored
  extraction bug in the same run.
- Mermaid syntax: `mmdc -i <each .md with mermaid> -o /tmp/out.svg` → exit 0
  when `mmdc` is on PATH. If `mmdc` is absent but the Mermaid-Chart MCP
  validator (`mcp__claude_ai_Mermaid_Chart__validate_and_render_mermaid_diagram`)
  is available, validate each block through it and assert `valid:true` — the
  result is large (embedded SVG/PNG), so `jq '{valid,diagramType,error}'` the
  saved tool-result file rather than reading it whole. This turns the
  "no mmdc" residual into a real gate; record a residual only if neither is
  available.
- `find . -name '*.md' | xargs -I{} grep -l '\[.*\](.*\.md)' {}` then check each
  internal link target exists (markdown link integrity).
- **Leaked agent-wrapper tags.** A `Write` tool call routinely leaks its closing
  `</content>`/`</invoke>`/`</parameter>` into scaffolded PRD/PLAN/ADR markdown (merkle-prd's
  4 docs, 2026-06-16). Grep for a line that is ONLY the tag (anchored, so it doesn't match
  this gate's own prose) across the PRD repo AND any scaffolded sibling
  `{project}-architecture/`: `grep -rnE '^[[:space:]]*</(content|invoke|parameter)>[[:space:]]*$'`
  must be empty. (Full rationale in `peerreview-approach-cdd-conformance` § Verification gate
  amendments.)

## What NOT to flag

- Prose style, sentence length, "could be clearer" suggestions — out of scope
  for charter convergence; route to `/ultrareview` or human review.
- Missing implementation detail — PRD is the *what*, not the *how*. PLAN's
  `## Implementation order` is allowed to be high-level.
- "Should add X" suggestions where X is not in the PRD itself — the PRD defines
  scope; the reviewer cannot expand it.

## Forecast hint

PRD repos are usually small (≤10 markdown files). Forecast: 1–2 rounds — but
do not treat that as a cap. Round 1's coverage-closure pass surfaces the
arithmetic / data-model / unmapped-requirement class; the **explicit-CONVERGED
verdict round(s)** reliably surface a *distinct* class the closure pass misses —
intra-PRD **cross-reference** errors (a "see rule N" / "see § X" pointing at the
wrong target) and **semantic self-contradictions** across multi-branch rules
(e.g. a state machine + a business rule that OR a condition the same rule later
says is *overridden*). When the verdict gate is honored these commonly drive
3–4 rounds even on a small, internally-tidy-looking PRD (urlshortener-prd
2026-05-23: forecast 1–2, actual 4 edit + 3 verdict rounds, the verdict sweeps
finding 7 of the defects). Expect it; do not short-circuit the verdict gate
because the gate is green and round 1 looked clean.

**Math / geometry / renderer PRDs run much longer — forecast 5–8 rounds, not
1–2.** When the BRs are formulas (Lens 7), the verdict loop drains a
degenerate-input *totality* family one layer per round (each fix exposes the
next div-by-zero / degenerate / out-of-range case), so a long NOT-CONVERGED
streak is convergence-in-progress, not oscillation (raycaster-prd 2026-06-05: 7
edit + 7 verdict rounds, every verdict a real defect; raytracer-prd 2026-05-31
re-run: 13 defects). **A round-1 CONVERGED on a math/renderer PRD is a yellow
flag, not a result — it almost certainly means the totality family was never
swept.** Re-prove it neutrally with Lens 7 driven explicitly before trusting the
verdict (tinyrenderer-prd 2026-06-05: a prior same-day run converged "round 1,
verdict 1 clean"; the re-run with Lens 7 driven hard drained an 11-rule totality
family — zero-area triangle, zero-length normalize/light, degenerate lookat,
zero projection divisor, non-positive dims, raster/AO/texture bounds, degenerate
UV basis, malformed TGA — over 4 edit rounds + a Lens-6 ADR-0004 contradiction,
before a true CONVERGED). Also budget wall-clock: a large math-PRD PEER round can
exceed the drivers' 1800s default and return empty — kill stragglers and retry
with `PI_ROUND_TIMEOUT` or `CLAUDE_ROUND_TIMEOUT` raised (raycaster-prd round 1).

**Re-runs after a topology-changing follow-up commit** (a new sibling repo,
an artifact moved between repos, a stub/scaffold promoted) need an explicit
**post-topology stale-claim sweep**: every present-tense statement in
PROBLEM.md residuals, PRD § Non-functional/Concurrency rules, and PLAN-001 §
Repo family + Implementation verification steps + cross-document
prose-references re-verified against the post-commit topology. Charter ACs
and verification-gate regexes written before the commit must also be
re-derived against the new link/path/file surface — a regex that filtered on
`.md` suffix may silently skip directory-target links, a regex on in-repo
paths may silently skip new sibling-repo paths. cgrep-prd 2026-05-29 (re-run
after a 1-commit cgrep-architecture introduction): 5 verdict rounds, all
five defects post-topology stale-claim variants (gate-coverage hole,
present-tense false claim about a not-yet-existent repo, directory-target
link not gated, prior-commit "to be authored" tense no longer accurate),
plus one pre-existing exit-code semantic contradiction the prior 4 converged
rounds had missed (the re-run rule pays off in both directions).

**HTTP-service PRDs (endpoint contracts, not data-structure libraries) — a
pinned status code is NOT a pinned response.** The downstream conformance suite
authors `http`-boundary goldens that assert exact **status + headers + body**,
so the dominant completeness defect is a status whose BODY and HEADER contract
is left implicit — and coverage-closure never catches it (closure only checks
that a status/behavior is *mapped* to a category, not that its response is fully
specified). Sweep every declared status across the PRD and require each to name
(a) its body shape (or the shared error shape + a specific `error.code`) and (b)
its exact header set — including the **negative and conditional** responses that
are easy to under-specify: an error status (`404`/`405`/`413`) with no code/body,
a `304` with no statement of which validators/headers it echoes and its empty
body, a `200` on a *secondary* endpoint (a result-resource / sub-collection GET)
that pins fewer headers than its primary. Also re-derive every field the filter
DSL / operators act on against the operator's **type contract**: an ordered
operator (`gt`/`between`) on a field the data-model types as a bare string is an
internal contradiction — declare the field's comparison type (numeric / temporal
/ string) so the type-mismatch rule and the headline operator behavior agree.
query-search-prd 2026-07-01 (first HTTP-service cdd-prd review; forecast 2–3,
actual 4 verdict rounds): 3 of 4 verdict findings were response-contract
completeness (missing `404`/`405` bodies+codes, the `304` header/empty-body set,
the result-resource `200` header set) and one was a `timestamp`-typed-as-string
vs ordered-operator contradiction — none visible to the green coverage gate.
