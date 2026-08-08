---
name: peerreview-approach-cdd-implementation
description: "Peer-review lenses for CDD implementation repos — Stage 1 conformance compliance, stub detection, architecture-fitness assertions, suppressed-violation audit"
disable-model-invocation: true
---

# Peer-review approach: CDD implementation repo

Reference loaded by `/peerreview` when Step 1.5 detects a CDD implementation
repo: markers are language manifest files (`package.json`, `pom.xml`,
`build.gradle`, `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`,
etc.) plus EITHER a sibling `*-conformance/` repo on disk OR a top-level
`conformance/` directory with golden files. This is the artifact `/cdd-implement`
produces.

The dominant defect class for implementation repos is **conformance compliance
without correctness**: code that passes all golden tests because it stubs
responses or hardcodes test-input handling, not because it implements the
behavior. This is the gap `/cdd-review`'s Stage 1 was built to catch; it
migrates here verbatim.

## Two-stage review structure

Per the original `/cdd-review` two-stage model:

- **Stage 1 — Conformance compliance.** MUST pass before Stage 2. These are
  the lenses below.
- **Stage 2 — Code quality.** Only after Stage 1 passes. The preferred Stage 2
  surface is `/ultrareview` (cloud-parallel personas) — `/peerreview`'s PEER
  convergence loop handles correctness-and-security adversarially as part of
  the convergence contract, so the role-based persona checklist that
  `/cdd-review` carried inline is now redundant with the convergence loop's
  own adversarial review of the real diff each round.

This module declares Stage 1. Stage 2 is the convergence loop itself plus an
optional `/ultrareview` recommendation in the final report.

## Brief the PEER with these lenses

### Lens 1 — Suite passes, count matches (gate prerequisite)

Run the full conformance suite. Stage 1 fails if any of these hold:

- Any golden file test fails.
- Test count run < test count discovered (skipped tests are a defect unless
  documented in `ambiguity-report.md`).
- CI is not green on the implementation's tracking branch.
- Local and container runs disagree on pass count.

If the suite is not green at baseline, **stop Stage 1 here** and route the
findings back to `/cdd-debug` or `/cdd-implement` — there is nothing to review
until conformance is green.

### Lens 2 — Stub detection heuristic (dominant defect class)

For every handler / endpoint / function exercised by ≥10 golden file tests:

- If the implementation is <5 lines of substantive logic, **investigate**.
  A function that passes 10+ tests with no branching is suspicious.
- Grep for `TODO`, `FIXME`, `HACK`, `PLACEHOLDER` markers. Any in
  conformance-exercised paths are defects.
- Verify different endpoints have different handlers (catch-all routes that
  switch on path string are a defect — they hide the absence of per-endpoint
  logic).
- Check that handler complexity is proportional to the number of tests it
  passes. A 200-line handler passing 30 tests is normal; a 4-line handler
  passing 30 tests is a stub.

### Lens 3 — Hardcoded test-input workarounds

Grep the implementation for string literals that match values from
`seed.json` or `request.json` fixtures. If a handler contains
`if (input.id === "abc-123") return {...}` where `abc-123` is the seed ID
used by one specific test, that is a hardcoded workaround — the function
"passes" the test but does not implement the behavior. Defect.

### Lens 4 — Architecture-fitness assertions

Per `/cdd-author` Step 3a (mandatory baseline):

- `conformance/architecture/dependencies/` MUST pass. No forbidden imports,
  no circular dependencies, no framework leakage into the domain. If the
  directory is empty, a `README.md` MUST justify why.
- `conformance/architecture/boundaries/` MUST pass. No deep cross-module
  imports; modules expose only via public API. If empty, README MUST justify.

If either set fails or is silently empty, that is a Stage 1 defect — Stage 1
requires the architecture-fitness baseline to be intact.

**When the impl ships its OWN hand-rolled import scanner** (the lint-assertion
boundary is analysed by code in the impl's test runner, not by an external tool
like dependency-cruiser / cargo-modules), that scanner is a self-serving artifact:
its green is only as sound as the syntax forms it recognises. The dominant defect
is **import-syntax-form blindness** — the scanner matches the language's *canonical*
single-path form and silently misses the others, so a forbidden edge written in an
unrecognised form passes the dependency goldens vacuously. Enumerate every import
syntax the language admits and confirm the scanner resolves each to the same module
edge: Rust `use crate::a;` AND grouped `use crate::{a, b}` AND nested
`use crate::{a, b::{C}}` AND whitespace-qualified `crate :: a` AND aliased
`use crate::a as x` AND `extern crate`; for path/include edges, EACH macro-delimiter
form (`include!(…)` / `[…]` / `{…}`) with the path STRING fully decoded (Rust escapes
`\x`/`\u{}`, raw strings `r"…"`) and `concat!` resolved recursively, AND `#[path = "…"]`
AND `#[cfg_attr(…, path = "…")]`; TS named/barrel/`import type`; Python `from x import a, b`.
**Plant a forbidden edge in EACH form and confirm the goldens go RED** — the impl's
own teeth-check commonly exercises only the canonical form (that is exactly the hole).
This is in-scope to fix in the impl runner (do not touch the sibling golden suite).
(bitmask-rust 2026-06-13: the Rust `crate::<ident>` scanner missed grouped
`use crate::{permissions}`, so a core→permissions edge passed ARCH-001/003 vacuously;
fixed by token-walking idents + brace-group parsing while preserving case-sensitive
module resolution so `crate::Error` [re-exported type] stays a non-edge.)
**A hand-rolled Rust scanner faces an *open-ended* form set — some classes are
unbounded, so enumerate-and-teeth-check the bounded forms but FAIL CLOSED on the
unbounded ones (emit one unresolved-edge sentinel that violates any assertion).**
Bounded (resolve + teeth-check each RED): raw idents `r#mod`, grouped/chained
`super::{…}`, `#[path]`/`include!` with a literal, string/char/raw-string-aware
comment stripping (a `//`/`/* */` inside a `"…"`/`r#"…"#` must NOT blank an import),
`src/x/**` submodule-dir globs. Unbounded (cannot enumerate → fail closed):
macro `$`-metavariables, a non-literal `#[path]`/`include!`/`cfg_attr` path arg,
and **root aliasing** (`use crate as x;` / `use super as x;` / `crate::{self as x}`
— the alias renames the root so `x::eval` can't be tracked). Don't chase each new
form one verdict at a time; close the whole class. (tagged-union-rust 2026-06-16:
a scanner cloned from bitmask-rust drained over 9 verdict rounds, each a distinct
valid-Rust form — every one a real bypass, no oscillation; converged once the three
unbounded classes failed closed. A static *source* lint inherently cannot defend
against codegen / proc-macro output — document that as a residual, not a defect.)
**Switching a regex scanner to a real AST/parser shrinks but does not close this
class — enumerate the parser's node kinds too.** A TS scanner using the
`typescript` compiler API still misses forms if the visitor only handles the
obvious nodes: beyond `ImportDeclaration` / `ExportDeclaration` (incl. `export *
from`) / `ImportEqualsDeclaration` / dynamic `import()` & `require()` *call*
expressions, it must also handle **`ImportTypeNode`** — a type-position import
`export type Leak = import("./test-hooks.js").X` is a real module edge in a
*different* AST node, invisible to a call-expression-only visitor. And **a
dynamic `import()`/`require()` whose argument is NOT a static string literal
(`import("./"+x)`, `import(varName)`) must FAIL CLOSED, not be skipped** — in a
public barrel asserted to NOT import something, an unresolvable dynamic load
could hide exactly that edge, so silently dropping it is a vacuous pass. Guard
the `ExportDeclaration` branch with `if (node.moduleSpecifier)` so a legitimate
local `export {}` (no module) doesn't trip the fail-closed path. Teeth-check
EVERY form (incl. the type-position and non-literal ones) RED + a clean barrel
with a legitimate `export type {X} from "./safe.js"` PASS. (minheap-typescript
2026-06-13: round 1 replaced a regex scanner with an AST one and still passed
two planted edges vacuously — a multiline dynamic `import()` [caught at the
edit round's teeth check] then `ImportTypeNode` + non-literal dynamic import
[caught at the verdict]; converged once the scanner returned structured
`{kind, specifier}` edges and the lint failed closed on any null specifier.)

**Go `go/parser` scanner — two forms the AST does NOT hand you for free.** A Go
architecture scanner using `go/parser` over `*.go` (excluding `*_test.go`) is less
import-form-prone than Rust/TS (one import syntax; grouped/aliased/blank/dot imports
all expose the same `imp.Path`), but TWO forms still evade a naive scan: (1) a Go
import path is a **string literal that may be raw** (`` import `pkg/internal/testhooks` ``,
valid Go) — `strings.Trim(imp.Path.Value, "\"")` leaves the backticks so the
`no_import` regex misses it; unquote with **`strconv.Unquote`** (handles `"…"` AND
`` `…` ``). (2) `no_exported_symbol` over only top-level `ast.Decls` (FuncDecl /
TypeSpec name / ValueSpec) misses an **exported struct field or interface method**
matching the forbidden pattern (`type X struct{ CompareCount int }`,
`type Y interface{ HeapSnapshot() }`) — also walk `*ast.StructType.Fields` /
`*ast.InterfaceType.Methods` (+ embedded-type names, generics-aware). Note a
*method on a type* (FuncDecl with a receiver) IS caught by the top-level scan; the
gap is fields + interface-method specs. (merge-iterator-go 2026-06-16: R2 raw-string
import, R3 field/iface-method — both red-proofed.)

**Don't hand-roll a STANDARD config format — use its real parser as a dev-dependency.** When the
self-rolled scanner parses a format that HAS a parser (the `Cargo.toml`/`package.json`/`pyproject.toml`
manifest, a YAML rules file, a JSON config), hand-rolling line/header matching leaks form evasions one
verdict at a time — header whitespace (`[ dependencies ]`), trailing comments (`[dependencies] # x`),
dotted keys (`[dependencies . serde]`), quoted keys, inline-table-vs-string specs. The durable fix is
to parse with the format's REAL parser added as a **dev-dependency**: a CDD "dependency-free core"
guarantee is RUNTIME-only (it gates the runtime `[dependencies]`/production imports), so a dev-only
parser used by the test harness is in-bounds and does not regress the architecture goldens. This is
in-scope to fix in the impl runner (do not touch the sibling golden suite). Reserve hand-rolling for a
format with no available parser (e.g. the language's own source — a Rust `use`-form tokenizer is a
justified hand-roll; a TOML manifest is not). Companion rule for composed paths: an `include!`/dynamic
path argument resolves ONLY as a bare string literal or a `concat!` of bare literals (concatenated in
order so split-token `concat!("../te","sts/x.rs")` reassembles to `../tests/x.rs`); `env!`, idents,
nested/mixed expressions, and non-literal `concat!` args FAIL CLOSED, never "any string token present
⇒ resolved". (ringbuffer-rust 2026-06-15: 5 verdict rounds walked the Rust `use`/path scanner from
line-prefix → tokenizer → multiline `#[path]`/`include!` → all-literals → exact resolver, then the
ARCH-003 `Cargo.toml` scanner from exact-header-match → `toml::from_str` [dev-dep] — the manifest class
closed in one move once the real parser replaced the hand-rolled header matcher.) **A robust
import-SOURCE tokenizer does NOT imply a robust manifest parser — they are SEPARATE sub-classes.** A
fresh neutral peer round will commonly nail the source-`use` tokenizer while independently hand-rolling
the manifest TOML *even when this rule is already in the module* (the module briefs the HOST, not the
peer; the peer re-derives from the neutral charter). So the reviewer should **red-probe the manifest
whitespace/dotted/quoted-header forms at the R1 verdict** (a throwaway feeding `[ dependencies ]\nrand="1"`
to the scanner must NOT return `[]`) rather than waiting for the peer to rediscover the manifest class
round-by-round — that pre-emption collapsed ringbuffer's 5-round incremental sweep into one targeted R2
on its sibling (skiplist-rust 2026-06-15).

### Lens 5 — Suppressed-violation audit

Grep for any `@SuppressWarnings`, `// eslint-disable`, `# noqa`,
`#[allow(...)]`, or equivalent suppression on architecture-fitness assertions:

- Each suppression MUST have a paired ADR entry (`docs/adr/`) OR an
  evolve-log entry explaining the exception. Per the
  `cdd-approach-architecture` three-condition gate, suppressions without
  written justification are Stage 1 defects.
- A blanket project-level suppression that disables architecture-fitness
  checks is a critical defect.

### Lens 6 — Test-runner trust

Re-read the test runner's assertion code (not just its output). Common
defects in agent-generated runners:

- Comparison logic that silently coerces types (`'1' == 1` passing).
- Snapshot tests that auto-update on mismatch (snapshot-rewriting is the
  CI-equivalent of cheating).
- Assertion functions that swallow exceptions.
- **Go runner: the `encoding/json` `float64`-integer-decode trap.** Go's
  `encoding/json` decodes EVERY JSON number to `float64`, so an integer-typed
  golden field read as `int(in["n"].(float64))` silently **truncates** a
  fractional (`1.5 → 1`) or out-of-`int`-range value instead of failing the
  malformed golden or matching the oracle's integer-domain check (the oracle's
  `isinstance(n, int)` → typed error). This is the runner-side companion to the
  Go *scanner* note in Lens 4. Decode integer fields through a strict helper
  that panics on non-number / `math.Trunc(x) != x` / out-of-range, and red-probe
  it (`flag n=1.5`, `bit=1.5`, `octal=1.5` must each go RED). In-scope to fix in
  the impl runner. (bitmask-go 2026-06-21: all three integer sites truncated;
  the neutral verdict caught it after the array-field round.)
- **Count-blindness: the runner discovers goldens but never asserts the count.**
  A dynamic-discovery runner that walks for `test.json` (or globs the golden
  dirs) and only guards `len(tests) > 0` will silently lose coverage when a
  golden is dropped, renamed, or fails to sync — the suite still reports
  "N/N green" but N has quietly shrunk, so the parity claim is only
  *incidentally* true. The fix (and what to verify): the discovered count is
  asserted against the **exact relative-path set**, not only a total or
  per-category counts: deleting one golden and adding a stray replacement must
  turn the suite RED even though the count is unchanged. Cross-check the pinned
  set against disk, and red-probe a count-preserving missing+extra substitution.
  This is the impl's own harness, so it is in-scope to fix; do not touch the
  sibling golden suite. (simplekafka-go 2026-05-29: a 117-golden Go suite whose
  runner only guarded `len(tests)==0` — a dropped category would have passed
  green; pinned `expectedConformanceTests = 117`. free-list-python 2026-07-17:
  count 30 passed after a path substitution; exact 30+2 manifests closed it.)
- **Malformed-golden robustness is a FAMILY, not just count-blindness — and an
  in-process golden-file dispatch runner drains it one gap per verdict.** Count-
  blindness catches a dropped FILE; it does NOT catch a golden whose CONTENT is
  corrupt but still parses. The same self-serving runner typically accepts: a step
  with the wrong/extra op key (it picks the first known one); an unknown
  measure/op (returns a sentinel that compares as passing); a required key OMITTED
  whose zero value is also valid (a `merge-structure` golden missing `final_heap`
  → `nil` → len 0 passes a drained-empty case); a required key present-but-**null/
  empty** (`assertions: null`, `steps: null`, `measure: null` → zero assertions
  RUN → vacuous pass); and a value **sub-shape** read by field-name (an
  `{key, streamIndex}` heap entry with an extra/missing field — missing defaults to
  0, extra ignored). Each is a real "a malformed golden passes vacuously" gap the
  count assertion can't see. **Pre-empt the whole drain at the R1 verdict** by
  red-probing the runner against omitted / null / empty / extra-field / wrong-key
  goldens in ONE pass (the in-process-runner twin of Lens-4's manifest red-probe
  pre-emption) — else the neutral verdict drains them one-per-round (merge-iterator-go
  2026-06-16: a FRESH go/parser runner drained count→strict-keys→key-presence→
  null/empty→sub-shape across R1/R3/R4/R5, 5 rounds, production code byte-unchanged).
- **Placeholder scope wider than the convention documents.** If the
  conformance suite's `convention-reference.json` (or equivalent) pins a
  placeholder like `{{ANY_STRING}}` / `__ANY_NON_EMPTY_STRING__` to a
  specific JSON path ("only at `body.error`"), ask the question in both
  directions: (a) does the runner's comparator enforce that scope, or
  does it honor the placeholder at any string position? AND (b) does any
  fixture in the suite already use the placeholder outside the documented
  scope? When (a) is "no scope enforcement" and (b) finds an out-of-scope
  use, the runner is the *symptom* and the suite is the *defect* — fixing
  the runner would knowingly break the suite; the right fix is upstream
  in the conformance repo (broaden the convention or replace the
  placeholder with the canonical literal). Document as a cross-repo
  residual and recommend a follow-up `/peerreview` against the conformance
  suite. cardvalidator-go (2026-05-21) caught the runner side;
  crudapi-go (2026-05-21) caught the inverted suite-side variant.
- **Consumer-driven contract: assert the OBSERVED response, not the mock you
  built.** For an `http-contract` / MSW / Pact boundary in the *consumer* repo, a
  runner that builds the mock response from `expected.json` and then only checks
  the parsed body leaves the **status + selected headers tautological** — nothing
  observes them, so they can never fail. The contract usually says "selected
  response headers asserted" (Location, Retry-After, Content-Type): the runner
  must capture the *actual* response the client received (e.g. MSW
  `server.events.on("response:mocked")`) and assert observed status + each
  documented header (present + value, placeholder-aware, charset-tolerant). Then
  **prove the new assertion bites** with a targeted mutation — drop the header in
  the handler, confirm the dependent test goes RED, revert — so it is not theater.
  urlshortener-react (2026-05-25): `runHttpContract` built the mock from
  `expected.headers` but never asserted them; API-001 `Location` / API-007
  `Retry-After` were tautological until an observed-response assertion was added.
- **Request-shape fidelity (the request-side twin): assert the impl issued the
  DOCUMENTED request, not just that the mock body parses.** When the harness mocks
  a *bare* endpoint and returns the same body regardless of query (common when the
  real backend scopes by token/JWT), it never observes the request the impl made —
  so the impl can call the *unscoped/over-broad* endpoint and still pass green. The
  golden's `source` / `description` usually cites the contract request shape
  (`GET /enrollments?student_id=`, `GET /classes?instructor_id=`,
  `/reports/transcript?student_id=`). Cross-check what the impl ACTUALLY requests
  (path + query) against that cited shape — an omitted scoping param is a
  role-scoped-data / **authorization** defect the suite masks. Corollary: a
  role-scoped *control* (a selector showing only the allowed options, a nav that
  hides admin links) does NOT prove the *action* is gated — exercise the hostile
  deep-link / `route.query` auto-run / direct-call path and confirm it is refused.
  student-mgmt-frontend-vue (2026-05-29): a green 55-golden Vue suite hid four
  variants — `/my/{enrollments,schedule,grades}` + student transcript fetched
  unscoped, and `ReportsPage` auto-ran a `?report=grade-summary` deep-link past the
  role-scoped `ReportSelector` (3 of the run's 5 rounds).
- **DSL / policy-engine runner: every accepted option must affect evaluation.**
  When the impl *is* a policy/DSL evaluator (a conformance runner, an OPA-style
  engine, a rule interpreter), its dominant defect class is **a documented
  option or semantic the runner accepts but silently ignores** — a spec
  parameter that is read (`spec.get("flag")`) but never applied, or a documented
  SHOULD/correlation simplified to a weaker check. The golden suite hides this
  because it exercises one value of the option, so the dead branch never runs.
  Sweep it both ways: (a) grep the evaluator for every `spec.get(...)` /
  parameter and confirm each actually changes a decision (a bound-but-unused flag
  is a silent false-pass); (b) walk the contract's per-assertion semantics and
  confirm each documented clause/option/correlation is implemented, even those no
  golden file exercises — each is either implemented or a recorded deliberate
  residual, never a no-op. orderflow-infrastructure (2026-05-25): the infra runner
  bound `allow_service_wildcards` but never used it (false branch a no-op →
  `ec2:*` would falsely pass under `:false`); `image_ref_policy`
  `same_account_as_deployment` rejected only multi-account spans, so a single
  unrelated third-party ECR account passed; and two documented SHOULDs (the
  TFNET-003 SG→DB-instance correlation, effective pod-securityContext
  inheritance) had been simplified away. All three passed a 35/35-green,
  100%-covered suite. **Implement-vs-residual for a documented runner-obligation
  correlation the suite did NOT encode as an assertion type:** decide by
  *empirically* checking whether the value is available at the artifact's
  evaluation time — don't assume. If it is plan-time-impossible, an honest
  documented residual beats a check that false-passes, and an always-on *implicit*
  check (gated on another assertion's presence) is a defect magnet — verify the
  available-now part, residual the rest. urlshortener-infra (2026-05-25): the
  INFRA-HARNESS NETSEC-005 bucket-policy-*principal* MUST is unverifiable at plan
  time because terraform's `configuration` block exposes only `references` for a
  `jsonencode(...)` policy, never the constant `Principal`/`Action`/`Condition`
  (= the suite's own AMB-015) — so implementing it as an implicit check spawned 5
  successive edge-case defects over 3 rounds (a `["values"]` crash on a
  no-`values` policy resource, over-enforced response-headers attachment, two
  false-GREENs) before settling on: strong check for the parseable-policy case +
  a documented apply/acceptance residual for the known-after-apply case.
  **Third strong instance: urlshortener-cicd (2026-05-28).** The workflow-
  assertion runner — a brand new DSL on top of a brand new boundary — passed
  14/14 on a self-authored conformance suite at every round AND drove **18
  substantive Lens-6 defects across 6 neutral-verdict rounds** (trajectory
  4 → 5 → 3 → 3 → 2 → 1, monotonically decreasing): `scan` bound-but-unused,
  effective permissions ignoring job-level override, download-without-upload,
  negated-`==` main gate, `scan:resolved` missing workflow/job/step `env:` +
  `container.credentials` + `services.*.credentials` + caller `with:` +
  `concurrency.group`, one-level-only `workflow_call`, sole-push-required
  branch-filter fallback, recursive `needs:`-on-uses-job rewriting at every
  inline level, `repo_scan` walking only the resolved workflow set. Same
  pattern as the prior two — green suite + 100% coverage hides everywhere
  the option/clause has only one tested value. **The Lens-6 sweep is now the
  primary engine for DSL-evaluator impls; don't skimp on rounds — a long
  monotonic-decrease trajectory is healthy, not non-progress.**

If you cannot verify the runner is comparing correctly, treat the green
suite as suspect and call this out as a finding.

### Lens 7 — Two-machine verification

Per the original `/cdd-review` "CI green (local and container)" rule: if the
repo ships a containerized test target, verify it passes both locally AND in
the container. Local-only green is a Stage 1 defect (environment skew hides
real bugs).

### Lens 8 — Documentation honesty vs the conformance contract

Lens 2/3 catch the dominant axis: *code that fakes passing tests*. This lens
catches the **converse axis**: code that genuinely passes, but **docs that
overclaim**. The conformance contract is usually *narrower* than the PRD's
product vision — it deliberately scopes some capability out (a GUI shell
tested state-only, a framework the suite never boots, a deferred integration
path). A repo can then be 100%-green, 100%-coverage, and genuinely
non-stubbed, yet its `README` / package + file comments / CLI `--help` text
**advertise the un-built, out-of-contract capability as real**. The green
suite cannot catch this because it never tested that capability.

**The SHIPPED public type/artifact surface is untested by the green suite — build it
and read it.** A library's tests import from `src/` (or a barrel re-export), NEVER
from the compiled `dist/*.d.ts` / packaged artifact a real consumer gets — so a build
step that silently breaks the published surface is invisible to a 100%-green,
100%-coverage, 100%-mutation suite. The recurring shape for a TS lib using
`stripInternal`: a declaration whose JSDoc contains the literal token `@internal`
**anywhere, including prose explaining a test seam**, is treated as internal and
DROPPED from `dist/*.d.ts` — so an `@internal` mention in a CLASS's doc comment strips
the whole exported class, shipping typeless `any` to consumers. Verify it: run the
build, then read `dist/*.d.ts` (or `npm pack --dry-run`) and confirm every public
export is present with ONLY its intended signatures (no test-only seam param/method
leaked, and — the converse — nothing public accidentally stripped). A charter AC that
*claims* "the published .d.ts exposes only the clean signatures" is not evidence until
you have actually read the built file. (merkle-typescript 2026-06-16: the `MerkleTree`
class JSDoc's prose `@internal` token made `stripInternal` remove the entire class from
`dist/merkle.d.ts`; green suite + 100% cov/mutation never saw it.)

**An in-process conformance adapter is not evidence for a separate public runtime path.**
When the runner dispatches fixtures directly to pure adapters while the product ships HTTP/CLI,
trace each stateful or multi-unit AC through that real boundary. Probe protocol continuation
(pagination, streamed-final parsing and broken-stream reissue) and require one atomic storage
operation for coupled state+effect transitions; adapter-only goldens can stay green while the CLI
reads SSE as JSON, returns only page one, or a deadline lands between two writes. (stateless-mcp-
incident-lab-typescript-raw 2026-08-03: 160/160 conformance + 81.9% mutation passed all three.)

Check it: cross-reference every capability claim in user-facing text against
what the tree actually contains — dependency manifest, imports, and scope.
A claim of a framework/feature the tree does not contain (e.g. README says
"Fyne v2 UI shell" + "launches the desktop app" while `go.mod` has no Fyne
dep and no file imports it; a comment says "via Fyne harness" with no Fyne)
is an honesty defect. The fix is to make the docs **truthful** — the unbuilt,
out-of-contract capability is an accepted **residual**, NOT something to build
(do not demand the GUI; flag the false advertisement). Confirm the framing
with the user when scope is ambiguous (is the missing capability a residual or
a deliverable?). gopx-go (2026-05-22): impl was fully green/covered/honest in
code, but README + 3 comments claimed a Fyne GUI the zero-Fyne tree never had.

**AC under-backed by its own gate (self-authored tutorial-completion / fidelity
charters).** When the same agent wrote the impl, the tests, AND the charter (a
`/tutorial` completion), sweep every AC for the converse-of-overclaim: the
capability is genuinely built, but the green test does NOT actually exercise the
AC's claim. Three recurring shapes: (a) a whole-table claim ("the source
coordinates") backed by a single-sample test (3d-render-engine: 1 of 12 verts);
(b) a capability claim backed by a **degenerate input** where a wrong impl still
passes (rasterization 2026-06-06: AC11 "1/z interpolation" tested only on FLAT
triangles, where `Σwi/zi` collapses so a `wi*zi` affine mutant passes; AC16
"centered" checked only by shaded-pixel count, never position); (c) a claim about
a **superseded/absent** output (build-your-own-3d-renderer: AC1 cited Project-1's
transitional ray-viz, not the final shaded PNG). **Fix direction = capability
test:** real-and-retained → **strengthen the test** to a discriminating input and
**mutation-prove it bites** (flip the formula, confirm RED, revert) — this is the
Lens 6 × Lens 8 case; absent/superseded → **reword the AC** to its truthful,
gate-reproducible claim (pure Lens 8). Ask "what mutation would this test fail to
catch?" of each AC, not just "does the AC describe real code?"

**(d) Skip-guarded (no-key) live test = the degenerate under-backed case.** For an
**LLM-application** fidelity charter (RAG/agent/tool-use tutorial reproduced with no
`OPENAI_API_KEY` at gate time — a growing `/tutorial` class), an AC whose only live
assertion is `@skipif(not has_key())` is *not exercised at all* by the green gate.
Confirm each such AC also has a real OFFLINE assertion — local-model behavior
(embeddings/cross-encoder) for the retrieval half, and a deterministic fake
(`FakeListChatModel`) for the chain/graph wiring — else the AC is backed only by a
skip and is under-backed. (rag-from-scratch 2026-06-07: AC-005/011/012 each skip a
live OpenAI test but DO carry fake-model wiring + local-embedding assertions →
adequately backed; verified, not assumed.)

### Lens 9 — Adjacent-input / sibling-path divergence (suite under-enumeration)

A 100%-green, fully-covered, non-stubbed impl can still be wrong on inputs the
golden suite never enumerated — because the suite (often authored by the same
self-serving pipeline) tests ONE representative value per boundary and the impl
quietly diverges from the PRD on its siblings. This is the impl-side mirror of
the cdd-conformance "enum-completeness per consuming code path" lens. For each
validation / routing / boundary the suite exercises, enumerate the *sibling*
inputs it did NOT cover and check the impl against the PRD (not against an
impl-invented shortcut):

- **Boundary-value siblings.** Suite tests "too short = `ab`"; does the impl
  treat the *empty* string the same, or special-case it as absent? Suite tests
  the exact self-host; does `host:443` / `host:80` bypass it? (urlshortener-go,
  2026-05-23: `custom_code:""` was silently treated as absent → minted a random
  code instead of 400; self-loop compared `u.Host` *with* port → trivial
  open-redirect bypass.)
- **Enumerated-set siblings.** Suite tests one member of an exhaustive set
  (one reserved name, one algorithm); are the *other* members handled, or only
  the tested one? (urlshortener-go: reserved names other than the one golden-
  tested fell through to the generic `/{code}` route — "treated as codes" the
  PRD forbids.)
- **Sibling code paths.** A guard is tested on GET; is the same guard on the
  POST/DELETE/preview sibling? (orderflow-go, 2026-05-23: POST lacked the GET
  skip-ahead guard.) A read path tested for status — does it also preserve the
  side-effect invariant the PRD names?

These are not stubs (Lens 2/3) — the code is genuinely implemented — so they
hide behind a green suite; they surface only by reading the PRD's *rule* and
asking "which inputs satisfy this rule that the goldens didn't list?" The
neutral PEER verdict loop is the engine that finds them (it drove 3 verdict
rounds / 5 such defects on urlshortener-go after a green round-1 edit pass);
brief the PEER to hunt sibling inputs, and re-derive the PRD-correct answer
yourself before accepting a fix.

**Oracle-fidelity corollary — PRD *prose* can over-specify beyond what the
oracle-generated goldens implement; matching the goldens wins.** When the
conformance suite is generated by a reference **oracle** (a `_oracle/*.py` that
transcribes the PRD and emits the expected values — common for math/renderer/
codec suites), the goldens encode the *oracle's actual algorithm*, which can be
SIMPLER than the PRD/convention prose describing it. A faithful impl reproduces
the oracle; the verdict loop will then (correctly-sounding, but wrong) push to
change the impl to match the prose. **That push is out-of-scope: applying it
breaks AC1 (the green goldens are the contract).** This is a *cross-repo*
residual (oracle ⇄ prose reconciliation in the conformance repo), not an impl
defect. Refute it with **computed evidence, not debate**: take the golden the
change would touch, compute its expected value (from the oracle/golden) vs the
value the proposed change would produce, and show the Δ exceeds the tier's
tolerance → the golden goes RED. The critic may even have *deferred the same
item itself* in an edit round ("needs suite/PRD reconciliation") then reversed
in the verdict — hold the line with the Δ. (tinyrenderer-cpp 2026-06-06: the
verdict demanded a UV-derived tangent basis + UV-degenerate fallback per PRD R7,
but `_oracle/oracle_shade.py:_perturb` uses a fixed UV-independent basis; the
`normal-mapping/004` golden expects [180,180,180] from that fixed basis, while
the proposed geometric-normal fallback yields [255,255,255] — Δ75 ≫ per_channel
tol 2 → NMAP-004 RED. Recorded as a conformance-repo residual; re-verdict with
the proof → CONVERGED.)

**When TWO pinned goldens contradict each other, keep the live boundary internally
consistent and quarantine compatibility to the fixture adapter.** Prove the conflict
from both expected files, choose the public schema/contract for production, and key the
oracle-only output on runner-owned context that clients cannot spoof. Comment the shim,
record the cross-repo residual, and test both sides of the discriminator; silently making
live output violate its advertised schema just to satisfy the behavioral golden is a defect.
(stateless-mcp-incident-lab-typescript-raw 2026-08-03: MRTR pinned `DECLINE`/`CANCEL`
while tools/list pinned `DECLINED`/`CANCELLED`; live uses the schema, fixtures the oracle.)

**Early-exit must save the work the metric counts (metric-assertion impls).** When a
`metric-assertion`/probe golden pins an *early-exit* claim ("a miss reads `< k`",
"short-circuits"), verify the impl early-exits at the **expensive stage the metric
represents**, not just at a cheap downstream access. The masking shape: the impl
**eagerly precomputes the full work-set** (all k hash positions, the whole candidate
list) into an array, then the early-exit loop only short-circuits the cheap
*consumption* — so the instrument (counting consumptions) reports `< k` and the golden
passes, while the impl actually did all k of the expensive computations the metric is
supposed to bound. The golden can't see it (it only checks the count). Read the impl's
structure: does the early-exit `break`/`return` happen before or after the costly
work? If the work is precomputed up front, the early-exit is cosmetic and the metric
is vacuous. Fix = make the work **lazy** (a generator yielding each unit on demand, or
compute-inside-the-loop) so the early-exit genuinely skips it; no golden value changes,
but the count now reflects real work. (bloomfilter-typescript 2026-06-16: `mightContain`
called an eager `probePositions(): number[]` that computed all k positions before the
bit-read early-exit, so an early-miss reported probe count 1 while 3 positions were
computed; converting `probePositions` to a generator made the miss compute exactly 1.)

### Lens 10 — Mutation-survival triage: a surviving mutant on a CORRECT line is a test-suite gap, not an impl defect

When the impl ships a mutation gate (or you run one), a *surviving* mutant has two
possible causes — and conflating them sends a correct impl into needless edits.
Before treating a survival as an impl bug, verify the mutated line against the
PRD/ADR formula with a clean build:

- **Mutant survives because the line is wrong** → impl defect, fix it.
- **Mutant survives because no test can DISTINGUISH the mutation at the values
  the suite pins** → the line is correct; the gap is in the *test suite's
  discriminating power*. Classic shape: the goldens exercise only degenerate
  inputs where the mutated and original expression coincide. (raytracer-cpp
  2026-06-01: the Schlick `(1−cos_i)^5 → ^4` mutant survived all 151 goldens
  because the only `schlick` goldens pin `cos_i ∈ {0,1}` — exactly where
  `0^n=0` / `1^n=1` make the exponent invisible — and no render glass golden hit
  a sensitive intermediate angle.)

Resolution for the second case: do **not** change the impl. (a) Add an *impl-side
unit test* at a discriminating value (e.g. `cos_i=0.5`) so the mutation gate
genuinely kills it; (b) if the blind spot is the **golden suite's** (it
structurally can't reach the discriminating value), that is a **cross-repo
finding** — record a residual and recommend an upstream golden in the
conformance repo (a follow-up `/peerreview`/`/cdd author` there), exactly like a
suite under-enumeration (Lens 9) that the impl can't fix from its side. This is
the mutation-gate twin of the "vacuous-but-correct golden" discrimination test in
`peerreview-approach-cdd-conformance`. Also: if the gate is a hand-rolled harness
(no off-the-shelf C++/etc. mutation tool), confirm it forces a full rebuild per
mutant and runs *every* suite — an incremental build can leave the mutant out of
the binary and falsely report SURVIVED (the stale-object trap, mutation flavor).

A line-ranged mutation scope is itself stale-able: after reviewed code grows, re-resolve every
`file:start-end` against current line numbers and confirm the named decision still lies inside.
A green score over an old range can exclude the exact fix it claims to prove; keep README range
claims synchronized. (stateless-mcp SDK 2026-08-03: SDK dispatch and Dynamo cancellation fixes
moved past both configured end lines while mutation stayed green.)

Readiness probes must be non-mutating; prefer sentinel reads and deduplicate shared stores.
For staged IaC publication, validate the **actual saved plan** (never a committed fixture),
ground state serial+lineage in a post-apply read, and bind the approved manifest bytes to
provider-verified image/object/package receipts before registration—a boolean prerequisite map
or receipt count is self-attestation. Poll live provider health; on first-deploy failure stop both
services and record each rollback outcome. Teardown inventory stays bound to captured physical
IDs—not name substrings; pin platform-resource ordering to prevent collisions or resurrection.
(Reporting-Platform-CC-Sandbox 2026-08-08: 85/85 green masked all four lifecycle gaps.)

### Lens 11 — De-staled-port test-input fidelity (modernization-charter profile)

When the charter is a **de-staled tutorial port** (a Python-2 book reproduced on
Python 3, an old-framework app on the current major — `/tutorial`'s latest-stable
policy makes these the default), the dominant *masked* defect class is a library
callback/API whose value **type** shifted across the version bump while the
headless test keeps feeding the **old** type, so a green suite hides a runtime
break. Probe every place the impl compares a library-delivered value against a
literal, and confirm the test exercises the type the **new** runtime actually
delivers. KEEP the fix (it restores the source's pre-bump behavior — Fidelity
rule, Step 4.4). (3d-modeller 2026-06-06: PyOpenGL's Py3 `glutKeyboardFunc`
delivers `key` as `bytes` [ctype `c_char`], so `key == 's'` never matched and the
s/c/f place keys silently did nothing; the suite passed because the test called
`handle_keystroke('s', …)` with a `str`. Sibling traps: int-division, `dict.keys()`
views, `map`/`filter` laziness, `iteritems`.)

### Lens 12 — Vertex-generating stages must interpolate EVERY per-vertex attribute, not just position (renderer/rasterizer profile)

For a 3D renderer/rasterizer, any pipeline stage that **creates new vertices** —
clipping, tessellation, subdivision, near-plane splitting — must interpolate the
new vertex's *full* attribute set (normal, UV, color, per-vertex intensity), using
the **same parametric `t`** as the position. The dominant masked defect is a stage
that interpolates position correctly and silently **drops the rest**, so an object
that gets split renders untextured / matte / with fallback face-normals only on the
split path. It hides because the geometry test asserts only the new vertex's
*coordinates* (correct!) while no test checks the carried attributes, and the demo
scene never triggers the split (objects sit fully inside the frustum). Re-derive
each generated vertex's expected normal/UV from the parent attributes at `t` and
assert them exactly; mutation-test by feeding a textured/shiny triangle that
straddles a plane. (cgfs 2026-06-06: `clipTriangle` built new `Triangle`s with
`color` only — `normals`/`uvs`/`specular` defaulted away; 64 green tests checked
only clip *geometry*. Faithful fix per the book's `αQ = αA + t(αB−αA)`; KEEP.)

### Lens 13 — Hand-written per-field copy/transform/clone drifts when the struct gains a field in a later chapter

Any **manually field-listing** method — a `Transform::operator()(Struct)`, a copy
ctor, a `clone()`/`toBuilder()`, a serializer — silently **drops** any field added
to the struct *after* the method was written. In a tutorial built chapter-by-chapter
this is structural: an early chapter writes the transform over the struct's then-3
fields; a later chapter adds `material`/`areaLight`/`mediumInterface` to the struct
but doesn't revisit the transform, so the new field is **zero/null on every
transformed instance**. It hides because the per-field method compiles fine (it's
not `= default`), the struct's *own* unit tests construct it directly (never through
the transform), and the demo scene rarely routes a carrier-laden instance through
the drifted path (e.g. a `TransformedPrimitive` wrapping a `GeometricPrimitive`).
Detect mechanically: for each hand-written copy/transform/clone/serialize method,
diff its assigned-field set against the current struct definition; any struct field
**absent from the method** is a drop-on-copy candidate — confirm whether the omission
is intentional. Mutation-test by routing a fully-populated instance through the
method and asserting *every* field survives, not just the geometric ones.
(pbr-4th-ed 2026-06-06: `Transform::operator()(SurfaceInteraction)` was written in
Ch3 over position/normal/uv; Ch7's `GeometricPrimitive` added `material`+`areaLight`
to `SurfaceInteraction`, never added to the transform → every `TransformedPrimitive`
hit rendered **unshaded and non-emissive**. 355 green tests never noticed: shape
tests build interactions directly; the demo scene's emitters weren't instanced. Fix
copies both pointers; KEEP. This was the 6th and last defect before CONVERGED — the
sampling-edge defects [clipped sphere/disk Sample/PDF, cylinder axial div0, disk
center-hit NaN] were **Lens 9**, the `ImageInfiniteLight::Phi=ConstantSpectrum(1)`
placeholder was **Lens 2**.)

### Lens 14 — A self-authored round-trip test is blind to a SHARED encode/decode error: verify the codec against the external spec, not against itself

Any `encode`/`decode` (serializer/parser, wire codec, marshaller) whose **only**
test is round-trip identity (`decode(encode(x)) == x`) is **structurally blind to a
bug both sides share**: if encode emits the wrong bytes and decode reads them back
the same wrong way, the round-trip passes while the artifact is wire-incompatible
with any *real* peer/spec. The self-authoring makes it worse — the same model wrote
encode, decode, AND the round-trip test, so all three agree on the error. Detect by
asserting the **encoder's output against the external specification or a known
real-world byte sequence**, byte-for-byte, for at least one value that crosses an
encoding boundary (a multi-byte field, a sign bit, a length prefix, an off-by-one
index). Where no spec fixture exists, hand-derive one byte string from the spec and
assert it. (bittorrent-client-c# 2026-06-07, cross-vendor: `EncodeBitfield`/
`DecodeBitfield` used a whole-bitfield `BitArray` reversal that swaps **byte order**
for >8 pieces — piece 8 set emits `80 00` but the BitTorrent spec is `00 80`. The
self-authored 9-piece round-trip test passed [both sides reversed identically]; a
real peer's bitfield would be misread. The fix asserts the exact wire bytes
`00 80`. This was the HIGH finding of round 1 — the canonical "what a self-authored
suite cannot catch" that the cross-vendor pass exists for.)

**A hand-rolled ENCODER of a standard format that REPLACES a std-lib must match the
std-lib on the format's EDGE cases, not just the happy path.** When an impl hand-rolls
a standard encoding to stay dependency-free (a UTF-8 byte encoder replacing
`TextEncoder`; a base64/hex/varint coder; the manifest-parser twin in Lens 4), the
self-authored goldens exercise only well-formed/common inputs, so a malformed/boundary
input the std-lib handles a specific way silently diverges. Verify the hand-roll against
the **std-lib it replaced** (or the format RFC) on the edge inputs: lone UTF-16
surrogates, overlong forms, the BMP/astral and 1/2/3/4-byte boundaries, NaN/±0, empty.
This is the encoder mirror of Lens 14's round-trip blindness and the Lens-4 "use the
real parser" rule — the difference is there's no peer to round-trip against, so the
*reference* is the platform std-lib. (bloomfilter-typescript 2026-06-16: a
dependency-free `utf8Bytes` generator [replacing `TextEncoder` because the `types:[]`
build can't resolve `node:util`] encoded a lone surrogate as an invalid 3-byte sequence
where `TextEncoder` emits U+FFFD `EF BF BD`; no golden used a surrogate and the Python
oracle would *raise*, so only the cross-vendor pass caught it — fixed to match
`TextEncoder`, KEEP.) **Tamper tests over Base64/Base64url must change decoded bytes:**
changing only the final encoded character can alter unused padding bits while decoding to the SAME
bytes, making a supposedly corrupt token intermittently valid. Flip a payload byte or a known
significant encoded character, and assert the decoded bytes differ before trusting the negative test.

### Lens 15 — Normative-serialization fidelity: the language's stdlib defaults silently diverge from the spec

When the impl produces bytes governed by a normative external spec whose exact output is the contract
(RFC 8785 / JCS canonical JSON, a canonical signature/hash input, a wire codec), verify it against the
**spec**, not just the passing goldens — the goldens rarely include the characters/magnitudes where the
language's stdlib defaults diverge, so the suite is green while the contract is violated. Concrete,
recurring footguns to re-derive against the spec + the oracle:

- **Go `json.Marshal` HTML-escapes** `<`, `>`, `&` (→ `<…`) and U+2028/U+2029 by default; RFC 8785
  does NOT. A string filter value `a<b&c>d` hashes to non-standard bytes. Fix: `Encoder.SetEscapeHTML(false)`.
- **Integer types bypass float number-formatting**: a language that special-cases integer JSON numbers
  (Go `json.Number` passthrough, Python `int`) will NOT apply the ECMAScript `Number::toString` rounding
  that RFC 8785 mandates (JCS numbers are IEEE-754 doubles), so a `>2^53` integer or a `1e21`-magnitude
  literal serializes differently than the spec. Route ALL numbers through the float ES-form.
- **Key sort**: UTF-16 code units, not code points (§3.2.3) — diverges for non-BMP keys.

Probe with a string containing `<`/`>`/`&`, a `>2^53` integer, and (if keys can be non-ASCII) a non-BMP
key; hash each and compare to a from-spec derivation. This is Lens 14 (verify the codec against the
external spec, not itself) specialized to canonicalization — and it recurs because the passing goldens
are almost always ASCII/small-integer. (query-search-go 2026-07-02: a green 80-golden impl HTML-escaped
`<>&` via `json.Marshal` AND passed integers through un-rounded; both invisible to the suite, caught by
the cross-vendor pass. Same family's conformance/architecture repos had the Python-side + UTF-16 halves.)

## Verification gate amendments

Append to the charter's `## Verification` block (run every round):

```bash
# Full suite
<project test command>   # bun test, mvn verify, pytest, go test, cargo test

# Test count agreement
echo "Expected: $(find conformance -name test.json | wc -l) ; Ran: <suite output>"

# Architecture-fitness baseline present
test -d conformance/architecture/dependencies || { echo "Missing arch/deps"; exit 1; }
test -d conformance/architecture/boundaries   || { echo "Missing arch/boundaries"; exit 1; }

# Suppression audit
grep -rE 'SuppressWarnings|eslint-disable|# noqa|#\[allow\(' \
  --include='*.java' --include='*.ts' --include='*.tsx' --include='*.py' --include='*.rs' \
  src/ 2>/dev/null | grep -v -f docs/adr/.suppression-allowlist 2>/dev/null \
  | tee /tmp/unaudited-suppressions
test ! -s /tmp/unaudited-suppressions || { echo "Unaudited suppressions"; exit 1; }
```

(Adjust the `find conformance` path if the suite lives in a sibling
`*-conformance/` repo — peerreview operates on a single `repo_path` per run,
so dual-repo setups need the gate to point at the sibling or be reconstructed
statically per `/peerreview` Step 4's un-runnable gate rule. Set the harness's
path env (e.g. `CONFORMANCE_PATH=../{project}-conformance/conformance`) before
running the gate.)

**Spawned-service gates.** When the harness starts an embedded database,
testcontainer, broker, or other real service, the PEER environment may lack the
required process/network/daemon access. That is an environment limitation, not
a clean gate or a code defect: the PEER reports the exact runnable subset and
reconstructs the rest statically, while the HOST runs the full gate for binding
re-verification per Step 4.4. Keep the independent pass neutral and make it read
all affected code even when it cannot execute the service. orderflow-go
(2026-05-23): a constrained peer could not bind embedded Postgres and ran only
package tests; the HOST proved 105/105 + 100% coverage, while static independent
review still found six real handler/validation defects against the PRD.

### Lens 16 — Framework presence is not framework binding

When an implementation's defining claim is use of an official SDK/framework, prove the
production request path actually transits its server/transport/handler boundary. Constructing a
registry and only closing it is decorative, even when live HTTP and every golden pass through a
parallel hand-written dispatcher. Trace one request end-to-end, require a test that fails when the
framework bridge is removed, and verify registered schemas/capabilities are substantive rather
than empty placeholders. Also inspect fixture-only input fields/comments: branching production
outputs on “live server never supplies this” is hardcoded oracle adaptation and belongs in the
test runner, not production. (stateless-mcp-incident-lab SDK 2026-08-03: 159/159 green while the
`McpServer` had no transport/connect call and MRTR status selected fixture vs live vocabulary.)

## What NOT to flag

- Code style / formatting — the project's linter and `/ultrareview` handle that.
- Performance micro-optimizations — only flag if conformance defines a
  latency/resource budget (`metric-assertion` boundary).
- "Could use a better library" suggestions — out of scope unless the suggestion
  would close a conformance gap.
- Test additions — implementation review does not author tests. If a category
  is missing, route the finding up to a conformance review.

## Forecast hint

Implementation repos vary widely (5k–500k lines). Forecast: 1 round for small
green-suite repos with no architecture suppressions, 2–4 rounds for larger
repos or repos with multiple Stage 1 defects. **Exception — an impl that ships its
OWN hand-rolled architecture-fitness scanner (the lint-assertion runner) forecasts
3–5 rounds regardless of how trivial the product code is:** the scanner is a
self-serving artifact and the neutral-verdict loop sweeps every import/path/manifest
syntax form the language+config formats admit, one per verdict (ringbuffer-rust
2026-06-15: 5 rounds, `src/` clean and byte-unchanged throughout — the entire defect
surface was the scanner's form-handling). A round-1 CONVERGED on such a repo is a
false-fast yellow flag — **UNLESS the scanner was cloned verbatim from an
already-Lens-4-converged sibling**, in which case it inherits the hardening and
genuinely converges at round 1 + verdict: verify the clone lineage and re-derive the
form-coverage yourself (plant a forbidden edge in each syntax form), but don't force
extra rounds on an inherited-hardened scanner. (bptree-typescript 2026-06-16: cloned
the minheap/bloomfilter TS-AST scanner — already hardened for `ImportTypeNode` +
non-literal-fail-closed in those siblings' own Lens-4 sweeps — so round 1 found nothing,
Codex's independent 500-op differential fuzz across orders 4/6/8 confirmed clean, verdict
CONVERGED. The 3–5 round forecast is for a FRESH hand-rolled scanner.) **But an
inherited-hardened clone can still carry a LATENT lineage-wide gap — re-derive the
unbounded-form FAIL-CLOSED set against the clone, don't just trust the lineage.** A
syntax form NO sibling's `src/` ever used is unhardened across the WHOLE lineage (it
never surfaced), so the clone inherits the hole: **root aliasing** (`use crate as x;` /
`crate::{self as x}` / `extern crate self as x` — renames the root so a later
`x::tests` edge is untrackable) was fail-closed-MISSING in the entire
bitmask→ringbuffer→skiplist→lrucache Rust lineage and only surfaced on the cross-vendor
pass. So the inherited-hardened scanner still warrants 1 edit + verdict, not a rubber
stamp. **And the in-process RUNNER (`run_op`/`run_interaction`) is a SEPARATE fresh
surface from the scanner** — cloning the scanner does NOT clone runner-input-shape
robustness: red-probe Lens-6 malformed goldens (extra/unknown op keys, missing/null
fields, and any contract IDENTITY invariant the impl doesn't enforce — e.g. a `label`
that "names exactly one blocking acquire request" but the impl's disposition map
silently collapses duplicates). (semaphore-rust 2026-06-17: scanner byte-identical to
the lrucache lineage yet Codex found root-aliasing-not-fail-closed [High] + 3 runner
malformed-golden gaps incl. duplicate-label-collapse [High] over 2 edit + 2 verdict;
`src/lib.rs` correct + untouched throughout.) The non-progress abort is the
key safety valve here — a stub-detection finding that the PEER repeatedly
"fixes" by adding more hardcoded matches should abort the loop with a
recommendation to route back to `/cdd-implement`.
