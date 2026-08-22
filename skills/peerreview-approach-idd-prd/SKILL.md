---
name: peerreview-approach-idd-prd
description: "Peer-review lenses for IDD `{project}-prd/` repos — PRD requirement/slice-ID ↔ PROGRESS.md tracker closure, tracker status semantics, invented-evidence detection, public/private boundary"
disable-model-invocation: true
---

# Peer-review approach: IDD PRD repo

Reference loaded by `/peerreview` when Step 1.5 detects an IDD `{project}-prd/`
repo: markers are a top-level `PRD.md` **plus** a top-level `PROGRESS.md` and
**no** `PLAN-*.md` files (the PLAN presence distinguishes CDD; evaluate this
row after the `cdd-prd` row). This is the artifact `/idd-plan` produces for
issue-driven products: `PRD.md` (stable requirement IDs + dependency-ordered
delivery slices) and `PROGRESS.md` (one verified implemented baseline plus
only rows that still guide delivery, reconciled later from verified live
state). Reconstruction compacts delivered requirements into the baseline;
it does not recreate one tracker row per historical issue or commit.

The dominant defect class is **requirement ↔ tracker drift**: a PRD
requirement or slice that never reaches the tracker, a tracker row that
invents evidence, or statuses that overclaim completion. GitHub is lifecycle
authority; the PRD is requirement authority.

## Brief the PEER with these lenses

### Lens 1 — Requirement ↔ tracker coverage closure (dominant defect class)

Enumerate every stable requirement ID and every delivery slice in `PRD.md`,
then prove semantic closure against the tracker's declared baseline coverage
plus current rows, modulo declared non-goals:

- Every PRD requirement and slice MUST be covered exactly once by either the
  implemented baseline or a current slice row. A reconstructed baseline is
  coverage, not missing rows.
- Every PROGRESS.md row MUST trace to a PRD requirement/slice ID — a row with
  no PRD anchor is scope drift or a speculative backlog (idd-plan forbids
  speculative issue backlogs).
- IDs MUST be stable and consistent across PRD, PROGRESS, and any drafted
  issue contract; a renamed or renumbered ID is a defect unless recorded.
- Do NOT pin the *count* of issues a slice decomposes into — decomposition is
  an implementation choice (the same overfit trap as tutorial roadmaps); keep
  the check to ID closure and dependency order.

### Lens 2 — Tracker status semantics and invented evidence

The tracker's status vocabulary must be explicit and its states distinct:

- The PRD/PROGRESS must declare the status vocabulary (e.g. `pending | active |
  landed | validated`, or the repo's documented equivalent) and every row's
  status must belong to it.
- **Do not conflate lifecycle states**: partially landed ≠ landed ≠ validated
  (merged code is not release validation); post-release work must not advance
  ahead of unmet initial-release dependencies.
- A terminal current row MUST carry evidence appropriate to its documented
  lifecycle (issue/PR/squash, or an explicitly authorized non-PR transition),
  never invented GitHub evidence. A reconstructed baseline instead carries one
  source commit + gate result and MUST NOT be expanded into terminal history
  rows. Live verification is still required where provider state is claimed.
- idd-plan bootstrap rule: the repo contains only `PRD.md` + `PROGRESS.md`;
  issue creation is a later explicit `/idd-issue` action, not a contract file.

### Lens 3 — Slice decomposition and release boundary

- Slices MUST be dependency-ordered and independently reviewable, and each
  MUST enumerate the requirement IDs it covers.
- The release boundary (what the first release must contain, what is deferred)
  must be explicit; ambiguity here is a defect because `/idd-issue` selects
  exactly one next slice from it.

### Lens 4 — Public/private boundary (IDD-specific)

IDD products often plan a later public implementation repo while the PRD stays
private:

- Issue contracts are public-safe: they reference requirement/slice IDs and
  outcome/evidence, and must NOT quote private PRD rationale or private
  motivation.
- The PRD must not leak real credentials, personal data, or third-party
  operational details that a public artifact could inherit.
- Where the PRD declares a publication boundary, the tracker/issue language
  must not contradict it.

### Lens 5 — Prose-spec inheritance

The generic prose-spec lenses still apply: internal cross-reference
consistency (every "section N" / ID reference resolves), no `TBD`/`TODO`/`etc.`
inside declared-exhaustive lists, no leaked agent wrapper tags, no
`[[wikilink]]` refs, markdown link integrity.

## Verification gate amendments

Append to the charter's `## Verification` block (run every round):

- **ID closure** (Lens 1) — extract defined requirement IDs and slice IDs from
  the PRD, then require requirements to close through the explicit baseline
  coverage line or current rows and slices to close through the explicit
  baseline delivered-slices line or current rows:

```sh
python3 - <<'EOF'
import re, sys
prd = open('PRD.md').read(); prog = open('PROGRESS.md').read()
REQ = r'(?:FR|NFR|BR|REQ|R)'; SLICE = r'(?:SLICE|S)'
prd_req = set(re.findall(rf'^#+\s+({REQ}-[0-9]{{3}})\b', prd, re.M))
prd_slice = set(re.findall(rf'^#+\s+({SLICE}-[0-9]{{3}})\b', prd, re.M))
prd_slice |= set(re.findall(rf'^\|\s*`?({SLICE}-[0-9]{{3}})`?(?:\s+—[^|]*)?\s*\|', prd, re.M))
if not prd_req: sys.exit('gate blind: no PRD requirement headings matched')

# Coverage authority is only the explicit baseline Coverage line, a table's
# Requirement(s) column, or a requirement-ID first cell. Incidental prose in
# acceptance/notes must not mask a missing assignment. Expand explicit ranges.
parts = [l for l in prog.splitlines() if re.match(r'^- Coverage:', l)]
req_cols = []
for line in prog.splitlines():
    if not line.lstrip().startswith('|'):
        req_cols = []; continue
    if re.match(r'^\|[\s\-:|]+\|$', line): continue
    cells = [c.strip() for c in line.strip().strip('|').split('|')]
    headers = [c.strip('*` ').lower() for c in cells]
    if any(c in {'requirement', 'requirements'} for c in headers):
        req_cols = [i for i, c in enumerate(headers) if c in {'requirement', 'requirements'}]
        continue
    if cells and re.match(rf'^`?{REQ}-[0-9]{{3}}\b', cells[0]): parts.append(cells[0])
    parts.extend(cells[i] for i in req_cols if i < len(cells))
surface = '\n'.join(parts)
prog_req = set(re.findall(rf'\b{REQ}-[0-9]{{3}}\b', surface))
for pfx, a, b in re.findall(rf'`?({REQ})-(\d{{3}})`?\s*[–-]\s*`?\1-(\d{{3}})`?', surface):
    prog_req |= {f'{pfx}-{n:03d}' for n in range(int(a), int(b) + 1)}
baseline = re.search(r'^## Implemented baseline\s*\n(.*?)(?=^## |\Z)', prog, re.M | re.S)
slice_parts = ([l for l in baseline.group(1).splitlines()
                if re.match(r'^- Delivered slices:', l)] if baseline else [])
slice_parts += re.findall(rf'^\|\s*`?({SLICE}-[0-9]{{3}})`?(?:\s+—[^|]*)?\s*\|', prog, re.M)
slice_surface = '\n'.join(slice_parts)
prog_slice = set(re.findall(rf'\b{SLICE}-[0-9]{{3}}\b', slice_surface))
for pfx, a, b in re.findall(rf'`?({SLICE})-(\d{{3}})`?\s*[–-]\s*`?\1-(\d{{3}})`?', slice_surface):
    prog_slice |= {f'{pfx}-{n:03d}' for n in range(int(a), int(b) + 1)}
if prog_req != prd_req:
    sys.exit(f'requirement closure: missing={sorted(prd_req-prog_req)} orphan={sorted(prog_req-prd_req)}')
if prog_slice != prd_slice:
    sys.exit(f'slice closure: missing={sorted(prd_slice-prog_slice)} orphan={sorted(prog_slice-prd_slice)}')
EOF
```

  The authority surfaces and range expansion are load-bearing. Whole-file ID
  extraction false-positived on three of five legacy repos in 2026-08; accepting
  incidental row prose later false-passed a dropped compact-baseline requirement
  because a slice's re-verification text repeated its ID. Mutation-test both
  shapes: dropped/orphan requirement, dropped slice, and a range interior reachable
  only through that range must fail. For a compact baseline, `Delivered slices:`
  is slice authority; legacy row-shaped trackers continue to use slice rows.

- **Status vocabulary** (Lens 2) — locate the `Status` column from the table
  header (its position is not fixed), derive the closed vocabulary from the
  artifact's status-semantics bullets, and reject undeclared values:

```sh
python3 - <<'EOF'
import re, sys
s = open('PROGRESS.md').read()
section = re.search(r'^## [^\n]*Status[^\n]*\n(.*?)(?=^## |\Z)', s, re.M | re.S | re.I)
if not section: sys.exit('gate blind: no status-semantics section')
vocab = {x.rstrip(':').lower() for x in re.findall(r'^- \*\*([^*]+)\*\*', section.group(1), re.M)}
for chain in re.findall(r'`([^`]*→[^`]*)`', section.group(1)):
    vocab |= {x.strip().lower() for x in chain.split('→')}
vocab |= {x.lower() for x in re.findall(r'^\|\s*`([^`]+)`\s*\|', section.group(1), re.M)}
if not vocab: sys.exit('gate blind: no declared status vocabulary')
status_col = None; checked = 0
for i, line in enumerate(s.splitlines(), 1):
    if not line.lstrip().startswith('|'):
        status_col = None
        continue
    if re.match(r'^\|[\s\-:|]+\|$', line): continue
    cells = [c.strip() for c in line.strip().strip('|').split('|')]
    if 'Status' in cells:
        status_col = cells.index('Status'); continue
    if status_col is not None:
        value = cells[status_col].strip('*` ').rstrip(':').lower() if len(cells) > status_col else '<missing>'
        if value not in vocab: sys.exit(f'PROGRESS.md:{i} unknown status: {value}')
        checked += 1
if not checked: sys.exit('gate blind: no tracker rows checked through a Status column')
EOF
```

  The three vocabulary forms cover current IDD trackers: bold bullets, an inline
  arrow chain, or a status-definition table. Unknown values and an unrecognised
  shape fail closed.

- **Terminal evidence presence** (Lens 2) — adapt to the declared table shape:
  terminal current rows require provider evidence or an explicit authorized
  non-PR transition marker; compact reconstructed baselines require Source,
  Verification, and Acceptance fields instead of historical rows. Do not use
  a fixed status-column index or require an issue/PR for a contract-authorized
  transition.

```sh
python3 - <<'EOF'
import re, sys
s = open('PROGRESS.md').read()
if '## Implemented baseline' in s:
    for field in ('Coverage:', 'Source:', 'Verification:', 'Acceptance:'):
        if not re.search(rf'^- {field}\s*\S', s, re.M):
            sys.exit(f'implemented baseline missing {field}')
# Project-specific charter code locates the Status column as above, then for
# each terminal current row requires either provider evidence (#N, /pull/N,
# commit URL/SHA) or the PRD-authorized non-PR transition evidence it names.
EOF
```

  Legacy artifact rows (PRD, naming, tracker) are exempt from provider-link rules;
  compact baselines use the four explicit evidence fields instead of rows.

- The standard prose-spec amendments from `/peerreview` Step 2 and the
  `cdd-prd` module apply unchanged: leaked-tag grep, `^\|`-anchored TBD/TODO
  check, `[[wikilink]]` grep, internal-link integrity.

## What NOT to flag

- Missing PLAN-*.md / PLAN.md / conformance suite artifacts — their absence is
  the defining property of the IDD profile, not a defect.
- Issue-count decomposition choices per slice (Lens 1).
- Implementation detail absent from the PRD — the PRD is the *what*, issue
  contracts carry the *how*.
- Prose style, "could be clearer" suggestions — out of scope for charter
  convergence.
- Unverified live GitHub state — the offline gate checks format/presence; the
  reconcile step is the live verifier. Record it as a residual.

## Forecast hint

IDD PRD repos are small (2 files), but file count does not bound semantic depth.
Forecast 1–2 rounds for lifecycle-only row trackers; reconstructed baselines or
publication/history-authority transitions require bounded sequential scopes and
may take materially more. Round 1 usually surfaces ID/status drift; neutral
verdicts surface cross-reference, authority, and slice-order contradictions.
Evidence: TraceHeist contract 2026-08-12 — the repo fell to `prose-spec` because no
idd profile existed (cdd-prd requires PLAN files), and the closure lens that
matters for an issue-driven repo (requirement IDs ↔ tracker rows ↔ issue
contracts) was only approximated by ad-hoc charter ACs. Five existing repos
match this profile (`reservation-bola-demo-prd`, `docscan-prd`,
`cloud-sandbox-prd`, `session-echo-prd`, `stateless-mcp-incident-lab-prd`).
