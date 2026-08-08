---
name: peerreview-approach-cdd-conformance
description: "Peer-review lenses for CDD `{project}-conformance/` repos — golden file traceability, structural validation, seed coherence, suite invariants, mutation analysis, ACL completeness"
disable-model-invocation: true
---

# Peer-review approach: CDD conformance repo

Reference loaded by `/peerreview` when Step 1.5 detects a `{project}-conformance/`-style
repo: markers are a `conformance/` directory (or top-level test category dirs
like `goldens/`, `categories/`, `architecture/`, `boundaries/`, `properties/`,
`http/`, `function/`, etc.) with `test.json` + `expected.json` (or
`expected-exit.txt`) leaves. This is the artifact `/cdd-author` produces.

The dominant defect class for these repos is **derived-suite coverage closure**:
golden files that exist on disk but are missing from the suite's own
coverage-tracking document, OR coverage doc rows with no corresponding files
on disk. `/peerreview` Step 2 already calls this out as the "derived
golden-file / test suites" sub-case — this approach module operationalizes it
with CDD-specific structure.

## Brief the PEER with these lenses

### Lens 1 — Disk ⇔ coverage doc bijection (executable closure gate)

Per `/peerreview` Step 2's derived-suite rule: reconstruct closure as an
*executable* gate script and run it at baseline. A self-authored coverage doc
is not evidence until a script confirms disk ⇔ doc bijection. For CDD repos:

- `find conformance -name test.json` enumerates every golden file.
- Parse each `test.json`'s `spec_id` field.
- Compare against the suite's `coverage-tracking.md` or `PLAN.md` traceability
  table.
- **Both directions must hold:** every disk `spec_id` appears in the doc; every
  doc row matches a disk `spec_id`. Mismatches are defects.
- If the doc enumerates IDs in grouped/abbreviated form (`FOO-002,003,008`),
  the gate fails — grouped IDs silently defeat machine closure
  (`/peerreview` Step 2 explicit rule). **Sweep EVERY table in the coverage doc,
  not just the primary BR→category trace.** Grouped/abbreviated shorthand
  (`OVWR-001…008`, `WRAP-001…008`) hides in the SECONDARY tables (outcome-tag
  rows, edge/boundary rows) even when the main trace is individually enumerated —
  and the closure gate, keyed on the main trace, doesn't look there. Expand them
  to per-id lists and re-verify each expanded row against disk (no fabricated/
  missing IDs). (ringbuffer-conformance 2026-06-15: the main BR trace was clean
  post-minheap, but the `accepted` outcome row + wrap/edge rows still used
  `…`-ranges.)
- **Coverage-COUNT arithmetic (distinct from disk⇔doc bijection — bijection can
  hold while the count lies).** If the coverage doc carries its own summary
  (`N / M in-scope features covered`, `K/K (100%)`), gate that summary against the
  *actual* number of `COVERED` rows: `N == M`, and `N ==` the COVERED-row count.
  Forbid an OUT-OF-SCOPE row (R7, a justified-empty subcategory) from feeding the
  in-scope numerator. A self-authored summary routinely miscounts or double-counts
  an OOS item as in-scope, and every closure/bijection check passes green while the
  headline total is wrong. (minheap-conformance 2026-06-13: bijection held, gate
  green, yet the verdict round caught `24/24` when there were 25 COVERED rows with
  R7 double-counted as an in-scope rule.)

### Lens 1b — Consumer-driven cross-repo mirror fidelity

When a category declares itself a **consumer-driven mirror** of a *sibling*
suite's goldens (a frontend `api-contract`/Pact category mirroring a backend
`{project}-conformance` suite; any "these files double as the contract the
provider verifies" claim), within-repo closure (Lens 1) is not enough — the
mirror must actually match the upstream it cites. Build an **explicit fe→be
mapping** (read the cited backend dir from each `test.json`'s `source` /
`providers`) and byte-compare each pair modulo key order
(`diff <(jq -S . fe) <(jq -S . be)`). A drift in status / headers / body shape /
error code is a defect — the contract is then a fiction and the consumer would
be built against it. A **multi-step upstream test maps to its relevant step**
(a 4-step rate-limit test → the FE single-step mirror compares to the backend's
final 429 `expected-N.json`); scope the mirror to the **response** and do *not*
force the FE *request* to byte-match an incidental upstream artifact (the create
URL of an IP-rate-limited request is immaterial). Skip cleanly when the sibling
repo is not checked out; run it whenever it is. (urlshortener-frontend-
conformance 2026-05-24: all 8 `api-contract` goldens verified byte-identical to
`urlshortener-conformance` links-api/custom-codes/errors-and-headers — the gate
proves the drift-guard the suite's whole purpose rests on.)

### Lens 1c — Suite-shipped reference generators: `--check` is self-consistency, not fidelity

Greenfield CDD suites increasingly ship their OWN reference generator(s) — a
spec-built codec / on-disk-format model / broker model that *emits* the goldens
and exposes a `--check` mode (`python3 protocol/wire_vectors.py --check`,
`tools/gen_*_fixtures.py --check`) which the charter gate runs and which
re-passes green. **`--check PASS` proves only `disk == generator-output`
(self-consistency); it does NOT prove the generator computes the right bytes /
offsets / responses.** A self-consistently-wrong generator ships wrong goldens
that pass their own check forever. Treat the generator as part of the
self-serving artifact, not as an oracle:

- Re-derive a **sample** by hand from the spec/PRD (`protocol/wire-format.md`,
  the business rules) **bypassing the generator** — encode a few wire frames
  from scratch, recompute a few offsets/positions/segment-bases/assignments,
  byte-build a truncation fixture. A from-scratch re-derivation that matches is
  the only thing that turns `--check` green into fidelity evidence.
- Brief the PEER to do the same independently; agreement across two independent
  hand-derivations + the generator is the fidelity bar.
- Audit the **generator logic** itself against the spec for the riskiest math
  (big-endian widths, length-prefix framing, `maxBytes` accounting, relative
  vs absolute offset, round-robin `(i+k) mod N`), not just that it runs.

(simplekafka-conformance 2026-05-29: 117-golden suite with 4 reference
generators; hand re-derivation of WIRE hex / METADATA_RESPONSE nesting /
assignment / maxBytes / recovery-truncation bypassing the generators confirmed
fidelity that `--check` alone could not.)

**Data-model-shape fidelity (not just numeric values).** A self-authored suite can faithfully
encode a WRONG reading of the PRD's DATA MODEL — and the generator AND the gate are both blind
to it, because they are *consistent with the wrong model*. So re-derive the entity field
**representations** against the PRD, not only the computed values: is a field the PRD calls an
`(index)` stored as an embedded object (or vice-versa)? Does a fixture carry an **array the PRD
never defines** (an invented parallel pool/registry)? Does a "(reference)" actually resolve
against the structure the PRD names? These shape divergences pass every structural gate and
re-derive "correctly" through the self-authored oracle, yet the contract is unfaithful.
(raycaster-conformance 2026-06-05: `floorTex`/`ceilTex` embedded as texture OBJECTS + an invented
`spriteTextures[]` array, vs the PRD's single texture pool with `floorTex`/`ceilTex`/`sprite.texture`
all as 0-based indices into it — found only by an independent read of the PRD data model.)

**Adversarially read the suite's OWN `ambiguity-report.md`.** An AMB entry that "resolves" a PRD
silence by **adding structure the source does not have** (a new array, a new field, a new
sub-format) is an over-invention flag — it frequently masks a simpler faithful reading and is the
root of a data-model-shape defect. Check each AMB: did the PRD actually require inventing this, or
is there a literal reading that needs no new structure? (raycaster-conformance 2026-06-05: AMB-SPR-001
invented a separate sprite-texture array to "resolve" the sprite-texture-id question; the faithful
reading was the single shared pool the PRD already implied — the over-invention WAS the defect.)

**Input self-containedness (the generator can hide state in the golden's INPUT, not just its
output).** A suite-shipped generator emits both the `input.json` and the `expected.json`, so it can
leave the INPUT *incomplete* — referencing geometry/textures/fixtures by a generator-only MARKER
(`_diffuse:"red2x2"`, a `synthetic` block holding only a `_note`) whose real data lives in the
gitignored generator, never in the committed golden. The oracle re-derives "correctly" (it has the
hidden state) and `audit` is green (the marker is valid JSON), yet **an implementation cannot run
the golden** — the input doesn't carry the data needed to produce the output, so a wrong impl can't
be falsified except by reverse-engineering the generator. Gate it: parse every `input.json` and
confirm it is **self-contained** — all geometry/texel/fixture data inline (or a real `input/`
fixture file), no marker referencing generator-only state. AND confirm every golden **maps to a
documented boundary/subcommand** in the cited architecture/ADRs — a render input no `render`/stage
subcommand can consume is unrunnable-by-contract (the fix may require an upstream ADR extension, a
cross-repo edit). (tinyrenderer-conformance 2026-06-05: ~25 render goldens fed pre-projected
geometry no ADR-0005 subcommand could run, AND 12 shading inputs carried only texture markers /
`_note` — non-reproducible; resolved by an ADR-0005 `raster`/`shade` stage-introspection extension +
inlining every input; 2 ad-hoc `_note`-only renders were removed as non-discriminating.)

### Lens 1d — Multi-implementation WORKITEM ownership closure

When the PRD has an implementation registry, one shared WI status cannot mean “done” for independent repos. Join every golden's `consumers`/`providers` to `WORKITEMS.md`: each implementation gets its own lane and each applicable golden exactly once there; provider-only tests never leak to the sibling; integration/infra/CI lanes name a concrete owning repo and depend on prerequisite implementation lanes. Parse the anchored `Target:` declaration itself—a repo token repeated in a Scope line must not mask a missing owner—and mutation-test missing/wrong-lane assignments. (stateless-mcp-incident-lab: 63/65 original WIs shared one status; the first lane repair still left family integration ownerless and hardcoded filename exceptions that contradicted consumer metadata.)

### Lens 2 — Structural validation (machine-checkable)

For every directory containing a `test.json`:

- `test.json` parses as valid JSON and contains `spec_id`, `boundary`,
  `source` keys.
- Sibling `expected.json` exists AND parses (OR `expected-exit.txt` for CLI
  boundaries).
- For `http` boundary: sibling `request.json` exists with `method` + `path`.
- For boundaries that need fixtures: sibling `seed.json` exists if referenced.
- Every JSON file parses cleanly with `jq empty <file>`.
- **Replayability, not prose-shaped placeholders.** Reject `input.json` files that contain only a scenario label/requirement sentence and HTTP fixtures that inject a runner-only `params.scenario` pseudo-field. Reject `expected.json` assertions such as `{type:"contract", must:"<prose>"}`: they force the runner to hardcode the expected behavior outside the golden and can pass without calling the SUT. Inputs must target a real public boundary; expected values must be complete observable output or use a closed executable assertion vocabulary. Also reject `request.json`/`seed.json` beside a boundary that executes only `input.json`: dead fixtures drift into contradictory second contracts while validators inspect data no runner issues. A standalone helper contract must prove the real consumer calls that helper; exporting an unwired identity function is not integration evidence. (stateless-mcp-incident-lab-conformance 2026-08-02/04: descriptive pseudo-RPCs first passed, then 17 dead fixture pairs and an unwired MRTR echo helper survived green validators.)

**Shape-augmentation evolve → gate BOTH sides (presence + no-leak).** When an
evolve adds a field to ONE endpoint's response shape while a SIBLING endpoint
that serializes the SAME underlying model must keep the base shape, a one-sided
"the field is present" check is not enough — the dominant defect is the field
*leaking* into the sibling. Gate both directions: (a) the field is present and
correctly valued where the new contract requires it (across every variant —
e.g. per-role), and (b) the field is ABSENT from the sibling endpoint's goldens
(no leak). (student-mgmt-conformance 2026-05-30: the GAP-3 evolve added
`student_id`/`instructor_id` to the `/auth/login`+`/me` identity payload while
`/users` — same `User` model — had to stay base; gate 13 asserted presence per
role, gate 14 asserted no leak into `USR-*`. A struct-field add instead of a
scoped DTO would have passed (a) and failed (b).)

### Lens 3 — Seed coherence

For every test with a `seed.json`:

- Seed entity IDs referenced in `request.json` exist in `seed.json`.
- The auth user (if any) referenced in `request.json` exists in `seed.json`.
- `expected.json` references valid seed entities only.
- No unused seed fields (defensive — flag, do not fail-close).

**Mirrored wire metadata must be checked mechanically across every request, not spot-read.** Parse body metadata and HTTP headers; require protocol version, method, name, and annotated parameter mirrors to agree after normative sentinel decoding. An intentional missing/mismatch case must declare that purpose and pin the exact error. Mutation-test at least one ordinary mismatch. This catches shared-fixture contamination that can make dozens of requests internally contradictory while JSON/shape lint stays green (stateless-mcp-incident-lab: one reused metadata object put the old protocol version into 79 current requests).

### Lens 4 — Cross-file consistency audit

Per `/cdd-author` Step 8 and the deprecated `/cdd-review` self-consistency
scope. Spot-check ≥3 random goldens from each category:

- Error response envelope format is identical across files
  (`{"error": {"code": "...", "message": "..."}}` vs. `{"detail": "..."}`
  divergence is a defect).
- Auth patterns are identical (cookie vs bearer vs query-param mixing is a
  defect — pick one).
- Seed data field naming is consistent (camelCase vs snake_case mixing is a
  defect).
- One sentinel per placeholder concept (`<uuid>` vs `<id>` vs `<uuid>` mixing
  is a defect — pick one).
- Null vs absent treatment is consistent across `expected.json` files.

### Lens 5 — Negative coverage

For every category with happy-path tests, verify error-path tests exist:

- 400 (invalid input) — at least one **per endpoint** that validates input.
- 404 (not found) — at least one **per endpoint** that addresses a resource.
- 406 (unsupported Accept) — at least one **per endpoint** that
  content-negotiates.
- 429 (quota / rate-limit exceeded) — at least one **per endpoint** that is
  gated.
- 401 (unauthorized) / 403 (forbidden) — **middleware-level**, not
  per-endpoint. When the suite has a dedicated `auth/` (or equivalent)
  category that exercises BOTH a non-admin route and an admin route, all
  other auth-protected routes inherit that coverage. Per-route 401/403
  duplication is brittle (one middleware change breaks N tests) and adds
  no actual coverage. Only flag missing 401/403 if the suite has no unified
  auth-middleware category, or if the auth-category fails to exercise both
  authorized-tier classes (non-admin AND admin). (Run 2026-05-21
  crudapi-conformance: AC9 in my initial charter was over-strict "401 per
  route" — every authoritative auth lens was already covered once in
  AUTH-001..010 over `/movies` and `/admin/keys`; per-route duplication
  would have added 13 zero-value fixtures.)
- Business rule violations — at least one per endpoint with documented rules.
- Feature-disabled scenarios — if any feature flags are referenced.

Categories with happy-path-only coverage are a defect (missed-failure-mode
risk).

### Lens 5b — Boundary-undertest: declared invalid case ≠ exercised invalid case

A test fixture's `description` / `description_bdd` / `normalisation`
prose often names a CLASS of invalid inputs (e.g. "non-positive",
"case-mismatched", "wrong type", "out of range"). The input fixture
then exercises only ONE representative of the class. An implementation
that handles the exercised representative but accepts another member of
the class passes the test while violating the contract.

This is a sibling of Lens 5 (negative coverage) but distinct: Lens 5
asks "is there a negative test at all?", Lens 5b asks "does the
existing negative test exercise every NAMED invalid sub-case?"

**Executable check (graduated from 5 real occurrences in gopx-conformance
2026-05-21 across rounds 2/3/4 — APP transition, modifier keys, selection
tool, FRM-005 delay_ms=0, FMT-003 wrong type, LAY-007 case mismatch):**

For every `test.json` whose `description` / `normalisation` declares
an invalid CLASS — recognised by patterns like:
- "non-positive", "negative or zero" → must test both negative AND zero
- "case-sensitive" / "lowercase only" → must test capital-letter variant
- "non-integer" / "wrong type" → must test each declared wrong type
- "out of range [a, b]" → must test below-a AND above-b
- "any other value" with a declared enum → must test boundary cases
  (mixed case, extra whitespace, near-miss spelling)

…verify the corresponding `input.json` / `input/*.json` actually
exercises each named sub-case. List undertests with file path + named
class + exercised case + missing case.

**Sibling enum-completeness check** (same defect class viewed from the
other direction): for every enum declared in `convention-reference.json`
or `suite-invariants.json` (transitions, modes, event types, error
kinds, app states, tools, modifier keys, blend modes, exit codes), walk
every test fixture and verify ≥1 fixture exercises every declared
value (excluding values that are explicitly declared "reserved/unused"
in convention-reference.json). Unexercised declared values are
undertests. (gopx-conformance 2026-05-21 round 2: surfaced 3 such gaps —
`selection` tool, `meta`/`alt`/`space` modifiers, `new`
guard_pending_action.)

**Two sharp sub-cases of "unexercised declared value"** (urlshortener-frontend-
conformance 2026-05-24): **(a) rendered display-field set incl. documented
null/empty renderings.** When a spec enumerates a *set of display fields*, each
with a per-field testid in `convention-reference.json`, require ≥1 assertion
**per field** — including any documented null/empty rendering. Beware the
*sibling-field trap*: there `last_accessed_at`→'Never' was asserted while the
co-equal `expires_at`→'Never' (a PRD-listed stats field) had zero assertions.
**(b) declared element whose own description claims a usage.** A placeholder or
DSL type whose description names where it is used (`{{SPA_ORIGIN}}` — "CORS
preflight assertion in api-contract"; "used by …") must have that claim verified
against disk; a usage claim with no on-disk occurrence is a dangling reference.
Resolve by exercising it or by explicitly marking it reserved/forward-looking —
never leave a false in-use claim.

**Enum-completeness PER CONSUMING CODE PATH** (refinement, urlshortener-
conformance 2026-05-23): a declared-exhaustive set is often consulted by
MORE THAN ONE code path, and each path must exercise every member —
not just one path. The reserved-code set there was tested exhaustively on
the custom-code REJECT path (CUST-005/006 → 400) but the GENERATION-SKIP
path tested only one member (`api`); an impl that skipped only `api` on
mint would have passed while minting `preview`/`static`/… So: when a set
governs N behaviours (reject vs skip vs route vs …), require ≥1 fixture per
member PER governing path, not ≥1 fixture per member overall. (Exclude
members structurally unreachable on a given path — there, the two dotted
reserved names contain `.`, which base62 can never emit, so they need no
generation test; state that exclusion explicitly so the set reads complete.)

**Side-effect-invariance check** (refinement, urlshortener-conformance
2026-05-23, drove rounds 2/3-no/4): when a read path CONDITIONALLY produces
a side effect (a counter increment, a `last_accessed` touch, a cache-tier
population, an audit-log write), the suite usually tests the path that
SHOULD trigger it and forgets every path that should NOT. Each
no-side-effect path needs an explicit *negative* assertion — a follow-up
read proving the side effect did NOT happen — because asserting only the
immediate response cannot catch a "do the work, then mutate" implementation.
Here: only the 302 path was shown to increment `click_count`; the expired
redirect (410), the active preview, and the expired preview (410) each
needed a multi-step "GET … then GET stats → counter unchanged" golden.
Enumerate every code path that touches the side-effected entity and confirm
each is classified (must-trigger → assert the mutation; must-not-trigger →
assert the non-mutation via a follow-up read). A DOM/response value that
happens to render the pre-state (e.g. the preview page showing the old
count) only catches mutate-BEFORE-render, never mutate-AFTER-render.

**Spec-stated-property completeness in the DECISIVE regime** (refinement,
bloomfilter-conformance 2026-06-15, drove **6 of 7** verdict rounds). Beyond
enum values (above) and invalid classes (5b), enumerate every *behavioral
property the suite's OWN spec docs STATE as contract* — PRD/ADR/`convention-
reference.json`/`suite-invariants.json` prose — and confirm each has ≥1
**discriminating** golden that exercises it **in the regime where it actually
bites**, which is frequently an edge the happy-path goldens never reach. A
self-serving author writes the prose and the goldens independently, so a stated
property routinely has no test, or a test only in the regime where a violating
impl still passes. Each property is its own sweep: *would an impl that ignores
this stated property produce the same golden value here?* If the decisive regime
isn't exercised, yes — vacuous. The properties bloomfilter stated-but-didn't-test
until the verdict forced each: per-probe counting under `k>m` collision (add AND
remove — both directions; distinct-position goldens at m=64,k=3 can't see it);
UTF-8-byte vs code-point hashing (ASCII-only goldens are identical across
encodings); `exactly k` vs `≤ k` probe bounds (an upper-bound assertion is
toothless against an under-touching/dedup impl — make add/remove an *equality*
and test it in the collision regime); full per-function domain coverage. The
matrix view matters: when a property has cells (op × variant: plain-add /
counting-add / counting-remove), the neutral verdict drains one cell per round —
sweep the whole matrix at once rather than waiting for each verdict.

### Lens 6 — Suite invariants machine-check

If `suite-invariants.json` exists at repo root:

- Parse every `expected.json` and verify error responses match the declared
  envelope shape.
- Verify any declared global invariants (e.g., "every error response has a
  `code` field matching `^[A-Z_]+$`").
- **Documented wire-format regex closure** — when `convention-reference.json`
  or `suite-invariants.json` declares a literal format pattern for a fixture
  value (e.g., `^crk_[A-Z2-7]{32}$` for plaintext keys, JWT/HMAC shapes, ID
  prefixes, opaque token formats), programmatically validate every fixture
  string in that role against the regex. The PEER's adversarial pass on shape
  will not necessarily catch length/alphabet violations when the literal
  "looks right" — e.g., a 31-char base32 string passes a casual eyeball
  check but fails the 32-char contract. (Run 2026-05-21 crudapi-conformance:
  AUTH-003 had a 33-char literal with `8` outside base32; AUTH-009/010 had
  31-char literals with all-valid chars — both caught by a one-shot regex
  sweep, both missed by Codex's R2 adversarial pass.)
- Report violations with file paths.

If `suite-invariants.json` does NOT exist, recommend authoring one as a
residual (it is the single highest-leverage cross-file invariant artifact
for CDD suites).

### Lens 7 — Architecture/boundaries baseline

Per `/cdd-author` Step 3a, every conformance suite ships
`architecture/dependencies/` and `architecture/boundaries/` directories from
project 1. Verify:

- Both directories exist.
- Each is either populated with assertions OR contains a `README.md`
  justifying why it is empty for this project.
- An empty directory with no README is a defect.
- **`import_pattern` regex robustness — re-derive against deep AND barrel forms.**
  When `architecture/dependencies/` goldens encode import-direction rules as
  `no_import` regexes, a pattern ending in a literal `/` (e.g. `(^|/)(api|components)/`)
  matches a **deep** import (`../api/x`) but SILENTLY MISSES the **barrel** import
  (`../api`, `@app/components` — no trailing slash, idiomatic in TS/Angular/Go
  packages), so a forbidden edge passes. Re-derive each regex against deep, barrel,
  and near-miss specifiers (`api-helpers`, `components-shared`, `openapi` must NOT
  match); the correct tail is `(/|$)`, not `/`. This is invisible to the structural
  gate — the regex compiles and the suite is green.
- **Upstream byte-sync — and actually PARSE the upstream, don't only text-compare.** If
  the goldens mirror a `{project}-architecture/rules/*.yaml`, every `import_pattern` must
  be byte-identical to the upstream assertion; a fix to the regex (e.g. the barrel-tail
  above) must land upstream FIRST, then mirror here, and the gate must assert set-equality
  of `(from_glob, import_pattern)` pairs. **Load the upstream file with a real YAML/JSON
  parser as part of the check** — a text-only assertion compare passes even when the
  upstream file is *unparseable* (a leaked `</content>` wrapper tag, a stray fence). The
  pairs "match" on substring while the file an impl's lint runner must load is broken.
  (merkle-conformance 2026-06-16: the ARCH-001 assertions matched the upstream text, but a
  leaked `</content>` tail made `merkle-typescript-boundaries.yaml` fail `yaml.safe_load` —
  caught only by parsing it, not by the text compare.) (urlshortener-demo-
  frontend-conformance 2026-06-08: the downstream review caught a barrel-import gap in
  ADR-0004's `angular-boundaries.yaml` that the architecture repo's own converged review
  had missed — its regex lens tested `../components/x` but not the bare `../components`;
  fixed upstream `(/|$)` then mirrored into ARCH-002/003.)

### Lens 8 — ACL completeness (migration suites only)

For large-scale migration suites (`/cdd-approach-large-scale`):

- Every legacy field present in the source system is either mapped to a new
  field in an ACL file, OR explicitly dropped in the ACL's `dropped:` list.
- Silent field omission is a defect.

### Lens 9 — Impl-neutrality vs flat-DSL expressiveness (policy/infra suites)

The dominant defect class for **policy-style conformance** (infra `function`
boundary asserting over terraform-plan / rendered-manifest / scan artifacts,
and any suite where `expected.json` is a policy assertion rather than a captured
response) is the tension between **AC11 impl-neutrality** ("assert policy, not
impl-chosen detail") and the **flat declarative DSL's** inability to express OR
/ cross-resource joins / runtime values. Both failure directions ship:

- **Over-pinning → rejects a conforming impl.** An assertion that hardcodes a
  resource name (`/orderflow` ECR repo), an account/ARN, a module version, a
  *single* mechanism where the spec admits several (`topologySpreadConstraints`
  when `podAntiAffinity` is equally valid), or an *explicit* configuration where
  the provider supplies a secure default (ECR/EBS encryption "provider default"
  per a PRD that allows it), will fail an implementation that conforms to the
  PRD by a different-but-valid choice. Cross-check every assertion against the
  PLAN/PRD **decision boundaries** ("may be decided by implementation: resource
  names, …") and the suite's own **ambiguity report** (a `topologyKey` pin that
  contradicts an AMB admitting the alternative is a self-inconsistency — real,
  seen 2026-05-24 orderflow AMB-019).
- **Dropping it → vacuous / too weak.** Deleting the over-pinned assertion (or
  reducing it to a trivially-satisfiable check, e.g. `replicas>=2` alone for an
  "across AZs" requirement) is the opposite failure: the contract no longer
  bites.

**The durable fix is one of two, never pin-one or drop-it:**
1. A **mechanism-neutral assertion type** the runner satisfies via *any* valid
   mechanism (orderflow `az_spread_policy`: topologySpreadConstraints **or**
   podAntiAffinity over the zone key; an "effective" resolver: container
   securityContext inheriting pod-level). Add it to the DSL vocabulary +
   invariants so the audit still enum-checks it.
2. A **documented runner obligation + residual** when the check needs a
   cross-resource join or a runtime value the fixture cannot hold (binding a
   `5432` ingress to the DB instance's SG; the image account == the deployment
   account). The flat fixture asserts the *expressible* security property (5432
   is SG-sourced never a CIDR; the image is digest-pinned ECR); the join/runtime
   part is an explicit obligation in the runner contract (`INFRA-HARNESS.md`) +
   an AMB residual (same class as a multi-AZ-placement correlation limit). **The obligation must
   also emit an exact expected receipt** (for example `proved_obligations`) mirrored input →
   registry → expected and mutation-tested: prose alone is optional in practice because a runner
   that skips every join otherwise returns the same green observation.

**A mini-expression registry needs grammar closure, not just check-ID closure.** If
`policy-registry.json` (or equivalent) stores compact requirement strings, enumerate every
syntactic form actually used and document its semantics: bare boolean/gate selectors,
scalar and empty-list equality, comma sets, subset selectors, numeric comparators,
alternative operators, indexed overwrite vs append, and same-resource prefix joins. Then
make the suite validator fail closed when any grammar clause disappears and mutation-prove
the high-risk forms. A runner can dispatch every known check ID while implementers still
interpret an undocumented expression differently: in stateless-mcp-incident-lab,
`iam.actions_subset=a,b` conflicted with a blanket "comma values are an exact set", and 25
of 55 predicates were bare selectors omitted from the claimed closed grammar. Exact
obligation receipts do not repair an ambiguous predicate language.

Watch for **plan-JSON shape traps** when writing "explicitly configured"
predicates: an omitted optional nested block renders as an **empty list `[]`**
(not null) in `terraform show -json`, so a `where: <block> not_null` wrongly
selects the provider-default case — scope on the **leaf path** (`<block>[0].<leaf>
not_null`) instead. And re-verify **prior fix rounds** in each neutral verdict:
a relaxation/tightening from an earlier round can itself be the new defect
(orderflow 2026-05-24: a round-3 `where` fix introduced the empty-list bug; a
co-editor even reversed its own earlier relaxation — adjudicate against the
charter's decision boundaries, not the co-editor's latest opinion).

**Existence ≠ wiring** (urlshortener-infra-conformance 2026-05-25, 3 instances
in one verdict pass): an `at_least_one_resource X` / "X exists" assertion proves
the resource is *present*, NOT that it is *referenced / attached / consumed* by
the resource that must use it. The contract "S3 private, CloudFront OAC only"
was asserted as "an OAC resource exists" — but an unused OAC plus an S3 origin
using the legacy `s3_origin_config`/OAI would pass; likewise a compliant
`aws_cloudfront_response_headers_policy` that no cache behavior *attaches*
(`response_headers_policy_id`) emits no headers at the edge; likewise a managed
secret that no task-def `secrets[].valueFrom` references. For every "X must be
**used by** Y" contract, do not stop at X's existence: assert the reference
where the plan expresses it, AND — since the reference is frequently a
computed / `(known after apply)` id (`origin_access_control_id`,
`response_headers_policy_id`, `aws_secretsmanager_secret.*.arn`) absent from
plan `values` — pair it with a **documented runner obligation** that resolves
the binding (same correlation class as the SG→SG / ACM-region obligations). A
clean expressible complement is forbidding the wrong mechanism's resource type
outright (`no_resource_matches aws_cloudfront_origin_access_identity` with empty
`conditions` = type forbidden).

Lens 9 applies verbatim to **`workflow-assertion` CI/CD suites** — another
policy-style boundary where `expected.json` is an assertion over an
impl-generated artifact (the GitHub Actions workflow graph), so both failure
directions recur (urlshortener-cicd-conformance 2026-05-28, 4 rounds):
- **Over-pinning a single mechanism.** Asserting a stage by a `run:` substring
  (`docker build`, `aws s3 sync`, ECR `docker push`) excludes the equally-valid
  action form (`docker/build-push-action`, an S3-sync action). Durable fix = a
  **run-OR-uses content predicate** (`by_step_content_contains` /
  `step_content_pattern`) — the workflow analogue of infra's mechanism-neutral
  assertion type. A negated guard also over/under-bites: a main-gate regex that
  merely *contains* `refs/heads/main` matches `github.ref != 'refs/heads/main'`
  (the inverse gate); require a **positive equality** form.
- **Existence ≠ wiring.** `step_present configure-aws-credentials` graph-wide
  proves OIDC exists *somewhere*, not on **each** AWS-touching job (creds don't
  carry across jobs); a CloudFront-invalidation `step_present` unscoped can be
  satisfied by an unrelated job; `permissions_includes id-token:write` unscoped
  isn't proven per credential job. Fix = scope every "X used by Y" assertion to
  the **role-selected job** (`by_environment`, `by_step_uses_contains`), and make
  the scoped form **existence-bearing**. The branch-protection / environment-
  reviewer correlations the flat DSL can't express are **documented runner
  obligations** (same class as infra's plan-time joins), not silent drops.
The genuinely-unexpressible parts (deploy reuses the *freshly-built* SPA bytes;
invalidation ordered *after* sync) are recorded **residuals** — forcing
`job_depends_on(deploy→build)` would falsely fail a valid single-job build+sync
pipeline, so impl-neutrality wins over a check the static boundary can't soundly
make.

### Lens 10 — Red-proof / "checks have teeth" must drive the REAL check, not a parallel reimplementation

When a suite ships a red-proof (a "every check goes red on a deliberately-broken artifact"
script — the CDD "a green that can't go red is worthless" thesis, and the AC peerreview
verifies for it), check that each red-proof case invokes the **actual** check function / gate
command under test — not a standalone re-measurement of the same property. A red-proof that
reimplements the predicate (e.g. its own headless-browser `scrollWidth` measurement beside
the acceptance script's) proves only that the property is *detectable*, NOT that the shipped
check detects it: the real check could be weakened or made always-green and the parallel
red-proof would still pass. The durable fix is to factor the check's verdict into a reusable
function (`assess_file(path)`, `check_X(...)`) that BOTH the gate and the red-proof call —
the red-proof feeding it deliberately-broken inputs and asserting the real verdict goes red.
(touchstone HTML 2026-05-26: the static red-proofs correctly called the real `check_*`
functions, but the browser-L3 red-proof re-measured overflow/nav itself instead of calling
`acceptance.assess_file`; the neutral verdict caught it → refactored so the red-proof drives
the real verdict.) Generalizes to any mutation/negative test: a negative test that exercises
a copy of the logic is blind to the production logic regressing.

### Lens 11 — Vacuous-but-correct golden: the discrimination test (numeric/algorithmic suites)

A golden's `expected.json` can be **arithmetically correct yet vacuous** — it passes
*regardless of whether the implementation implements the behavior the test claims to pin*.
This is "a green that can't go red is worthless" applied to the GOLDEN's discriminating power,
not to the gate. It is the dominant defect class in numeric/algorithmic conformance suites
(raytracers, geometry, codecs, simulators) and structural validators (Lens 1–10) cannot see it
— the value re-derives correctly, the file parses, the schema matches.

For every golden, apply the **discrimination test**: *would an implementation that omits or
breaks the specific behavior this test names still produce this exact expected value?* If yes,
the test is vacuous. Concretely, hunt:
- **Byte-identical input twins.** `find -name input.json | md5 | sort | uniq -d` (and same for
  `expected.json`). Two tests with identical input but `description`s claiming different
  behaviors → at least one is a copy that exercises nothing new (raytracer-conformance:
  TRI-009 "winding" == TRI-001; DIFF-008 "point≈directional" had NO point light, == the
  directional twin). Legitimate output-only dups (all misses `{hit:false}`, all error envelopes)
  are fine — the defect is identical *input*.
- **The named restructuring never fires (rebalancing-structure goldens).** For a
  history-dependent / rebalancing structure (B-tree / B+ tree / red-black / AVL / heap), a
  structure golden claiming a borrow / merge / split / rotation is vacuous two ways: (a) the
  operation sequence never actually TRIGGERS it — the deleted key's leaf doesn't underflow, the
  insert doesn't overflow, the chosen sibling isn't the one with spare capacity — so it pins
  nothing about the named restructuring; (b) the resulting structure is one a WRONG policy
  (different split index, right-first borrow/merge, no copy-up) would ALSO produce. Re-derive the
  final structure under the wrong policy and confirm the sequence both fires the named
  restructuring AND yields a tree the wrong policy would not. (bptree-conformance 2026-06-16:
  STRUCT-006 "borrow-from-left" never underflowed; STRUCT-005 "borrow-from-right" produced the
  same tree as a no-borrow left-heavy split — both vacuous, reworked to decisive sequences.)
- **The named knob has no effect at the chosen operating point.** A parameter the test claims to
  exercise but whose value is multiplied/added out at the sampled point: an aspect-ratio test
  sampling the exact image center (`x_ndc=0`, aspect drops out); a "partial anti-aliasing" scene
  whose geometry every AA sub-ray misses; a "reflects object B" scene whose reflected ray never
  intersects B (reflects background); an "occluder shadows the hit" scene whose occluder is behind
  the hit or off the shadow-ray path. Re-derive the value **with and without** the claimed
  behavior — if they're equal, it's vacuous.
- **The discriminator (epsilon/tie-break/ordering) doesn't flip the result.** An ε-offset /
  acne / tolerance test where the result is identical with and without the offset (raytracer
  SHAD-003: occluder roots rejected both ways); a "nearest wins" test where first-in-order also
  happens to win; a tie-break test that an "always pick first" impl also passes.
- **Multi-step server-value PRESERVATION via independent placeholders.** A multi-step golden
  (`{steps:[...]}`) whose `expected.json` puts the SAME wildcard ({{TIMESTAMP}}, {{GENERATED_ID}},
  {{CODE}}, a generated token) in two different steps does NOT prove the value is *preserved*
  across steps — each placeholder matches independently, so an impl that REGENERATES the value on
  the second read/step still passes. Any test claiming a created value is "read back intact" /
  "durable" / "unchanged" needs an explicit cross-step **equality** assertion tying the two
  resolved paths (e.g. `{"type":"equal_values","paths":[["steps",0,"body","created_at"],
  ["steps",1,"body",0,"created_at"]]}`). This is the equality sibling of the distinct-values need
  (proving two *generated* values differ). The de-correlation twin: an ordering test whose seed
  has id/code/timestamp all sorted the same way passes under id-order or code-order too —
  de-correlate the seed so only the claimed key yields the expected order. (urlshortener-demo-
  conformance 2026-06-08: SQL-001/002 "durable across requests" passed with a regenerated
  `created_at` until an `equal_values` assertion was added; LNK-002 ordering was vacuous until
  id/code/created_at were de-correlated. Same twin on the FRONTEND 2026-06-08: a
  view-model-mapping golden and a table-render golden both claimed "preserves the API array
  order, does not re-sort" but fed input ALREADY in `created_at`-descending order — a
  sort-by-`created_at` impl passed identically; fixed by feeding a deliberately
  non-`created_at`-sorted input so preserve-order and sort-order produce different output.)

The fix is to **redesign the input so the claimed behavior is decisive** (reversed winding that
flips the normal; an off-center sample so aspect scales; geometry the reflected/shadow ray
actually hits; a near-surface occluder where the ε-offset flips occluded→lit; a second element
that must beat the first), then **prove discrimination** by re-deriving the expected value both
ways and confirming they differ. The decisive reviewer tool is an **independent from-scratch
re-derivation oracle** built from the upstream spec (NOT the suite's own generator — Lens 1c):
it both confirms AC3 numeric correctness and powers the with/without discrimination check.
(raytracer-conformance 2026-05-31: 7 vacuous goldens — all arithmetically correct — found via
the discrimination test over a from-scratch PRD oracle; the structural gate was green throughout.)

## Verification gate amendments

Append to the charter's `## Verification` block:

```bash
# Structural validity
# NOTE: `jq -e empty` exits 1 on VALID JSON because the `empty` filter
# produces no output and `-e` treats no-output as failure. Use plain
# `jq empty` (without -e) — it exits 0 on valid input and non-zero only on
# a parse error. This was a real bug in this gate (cardvalidator-conformance
# round 1; see git history).
# NOTE: a suite that tests "malformed/invalid input is rejected" (definition,
# config, schema loaders) ships INTENTIONALLY-invalid fixtures as the SUBJECT of
# those tests. By convention they are named `*_malformed*` / `*_invalid*` and the
# authoring validator (audit.py) skips them BEFORE parsing. The gate must do the
# same, or it fail-closes on a conformant artifact (orderflow-conformance
# 2026-05-23: a genuinely-malformed broken_malformed.json failed a naive
# `find -name '*.json'` parse loop). Skip them here too.
fail=0
while IFS= read -r -d '' f; do
  case "$f" in *_malformed*|*_invalid*) continue;; esac
  jq empty "$f" >/dev/null 2>&1 || { echo "  PARSE FAIL: $f"; fail=1; }
done < <(find conformance -name '*.json' -print0)
[ "$fail" = 0 ] || { echo "JSON parse failure"; exit 1; }

# Required keys per test
find conformance -name test.json -print0 | xargs -0 -I{} sh -c '
  jq -e ".spec_id and .boundary and .source" "$1" >/dev/null \
    || { echo "Missing required key in $1"; exit 1; }
' _ {}

# Leaked agent-wrapper tags — a `Write` tool call routinely leaks its closing
# </content> / </invoke> / </parameter> into scaffolded markdown/YAML/JSON (the same
# class across merkle-prd's 4 docs + merkle-architecture's 8 artifacts, 2026-06-16).
# In YAML/JSON it can break the parse outright; in markdown it renders literally on
# GitHub. Anchor to a line that is ONLY the tag (not this gate's own prose referencing
# the pattern). Sweep this repo AND any cited sibling (../{project}-architecture/).
if grep -rnE '^[[:space:]]*</(content|invoke|parameter)>[[:space:]]*$' . \
     --include='*.md' --include='*.yaml' --include='*.yml' --include='*.json' 2>/dev/null \
     | grep -v '/\.git/'; then echo "Leaked agent-wrapper tag(s)"; exit 1; fi

# Disk ⇔ coverage closure (only when coverage-tracking.md exists)
# IMPORTANT: anchor the doc-side regex to the suite's ACTUAL spec_id prefixes, not
# a generic `[A-Z]+-[0-9]+` — the latter also matches non-spec tokens the doc
# legitimately carries (AMB-008, PLAN-001, ADR-003, RFC-7807), producing
# false "in doc only" diffs (orderflow-conformance 2026-05-23). Derive the prefix
# set from the on-disk spec_ids and build the alternation, e.g.:
if [ -f coverage-tracking.md ]; then
  PREFIXES=$(find conformance -name test.json -exec jq -r .spec_id {} \; \
    | sed -E 's/-[0-9]+$//' | sort -u | paste -sd'|' -)
  diff <(find conformance -name test.json -exec jq -r .spec_id {} \; | sort -u) \
       <(grep -oE "(${PREFIXES})-[0-9]+" coverage-tracking.md | sort -u) \
    || { echo "Disk/coverage bijection broken"; exit 1; }
fi

# Cross-repo mirror fidelity (Lens 1b) — ONLY when a category mirrors a sibling
# suite AND that sibling is checked out. Map each fe golden to the backend golden
# its test.json cites; byte-compare modulo key order. Scope to the RESPONSE; map a
# multi-step upstream test to its relevant step's expected-N.json. Skip cleanly if
# the sibling is absent. (urlshortener-frontend-conformance 2026-05-24)
BK=../<project>-conformance/conformance
if [ -d "$BK" ]; then
  cmp_json() { diff <(jq -S . "$1") <(jq -S . "$2") >/dev/null || { echo "DRIFT: $1 != $2"; exit 1; }; }
  # one cmp_json per mapping, e.g.:
  # cmp_json conformance/api-contract/001-create/expected.json "$BK/links-api/001-create/expected.json"
fi
```

## Mutation analysis (post-implementation, optional)

When the suite is paired with a green implementation, mutation testing measures
suite strength. Per language: Stryker (JS/TS), PIT (Java), mutmut (Python),
go-mutesting (Go), cargo-mutants (Rust). Target mutation score ≥80% per
category. Report survivors with file paths and recommend the smallest set of
new goldens that would kill them.

**Mutation is opt-in**: only run it when explicitly invoked or when the user
has agreed to the cost. Document baseline + post-fix scores.

## What NOT to flag

- Test count being "too low" or "too high" — only `/cdd-plan`'s estimates can
  judge this, and the planner sets the target.
- Test naming style preferences — name conventions are project-scoped.
- "Should test feature X" where X is not in PRD scope — that is a PRD/PLAN
  gap, not a conformance defect. Route findings up to a PRD review instead.

## Forecast hint

Conformance repos are usually medium-sized (50–300 golden files). Forecast:
2–3 rounds. Round 1 surfaces structural defects (parse errors, missing keys,
broken closure); round 2 typically addresses cross-file consistency drift;
round 3 only if mutation analysis was requested and survivors need new
goldens authored.
