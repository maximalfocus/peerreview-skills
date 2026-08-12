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
delivery slices) and `PROGRESS.md` (the tracker, reconciled later from
verified live GitHub issue/PR state).

The dominant defect class is **requirement ↔ tracker drift**: a PRD
requirement or slice that never reaches the tracker, a tracker row that
invents evidence, or statuses that overclaim completion. GitHub is lifecycle
authority; the PRD is requirement authority.

## Brief the PEER with these lenses

### Lens 1 — Requirement ↔ tracker coverage closure (dominant defect class)

Enumerate every stable requirement ID and every delivery slice in `PRD.md`,
then prove a bijection with `PROGRESS.md` rows, modulo declared non-goals:

- Every PRD requirement/slice ID MUST appear as a tracker row (or in an
  explicit deferral/non-goal statement).
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
- A row marked landed/done MUST carry verified evidence (an issue/PR/squash
  reference in the documented format, e.g. `owner/repo#N`) or an explicit
  recorded reason — never invented GitHub evidence. The offline gate checks
  format/presence; live verification happens via `/idd-plan --reconcile` and
  is a residual here, not a skip.
- idd-plan greenfield rule: the repo should contain only the PRD + tracker +
  the recommended first issue contract — a speculative backlog is a defect.

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

- **ID closure** (Lens 1) — extract IDs from PRD headings/requirement lines and
  from PROGRESS rows, and require both directions to close:

```sh
python3 - <<'EOF'
import re, sys
prd = open('PRD.md').read()
prog = open('PROGRESS.md').read()
prd_ids = set(re.findall(r'\b(?:FR|NFR|SLICE|BR|REQ)-[0-9]{3}\b', prd))
prog_ids = set(re.findall(r'\b(?:FR|NFR|SLICE|BR|REQ)-[0-9]{3}\b', prog))
missing_in_tracker = prd_ids - prog_ids
orphan_rows = prog_ids - prd_ids
if missing_in_tracker: sys.exit(f'PRD IDs missing from PROGRESS: {sorted(missing_in_tracker)}')
if orphan_rows: sys.exit(f'PROGRESS IDs without PRD anchor: {sorted(orphan_rows)}')
EOF
```

- **Status vocabulary** (Lens 2) — every status cell belongs to the declared
  set; a status value outside it fails:

```sh
# declared set lives in PRD.md or PROGRESS.md; example set below — pin to the repo's own declaration
python3 - <<'EOF'
import re, sys
s = open('PROGRESS.md').read()
vocab = {'pending','active','landed','validated','done','reviewed','blocked','deferred','planned'}
# extract the Status cell (2nd) of each data row; skip separator rows AND the header row
for i, line in enumerate(s.splitlines(), 1):
    if line.lstrip().startswith('|') and not re.match(r'^\|[\s\-:|]+\|$', line):
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells) >= 3 and cells[1].lower() not in vocab and cells[1].lower() != 'status':
            sys.exit(f'PROGRESS.md:{i} unknown status: {cells[1]}')
EOF
```

  (Adjust the vocabulary regex to the repo's declared set at charter time; the
  point is a closed set, not this exact list.)

- **Evidence-link presence** (Lens 2) — rows whose status means "done" must
  carry an evidence reference (link matching `#\d+` or `owner/repo#N`) or an
  explicit exception marker; absence fails:

```sh
python3 - <<'EOF'
import re, sys
s = open('PROGRESS.md').read()
done_status = {'landed','done','validated'}
req_id = re.compile(r'^(?:FR|NFR|SLICE|BR|REQ)-[0-9]{3}\b', re.I)
for i, line in enumerate(s.splitlines(), 1):
    if line.lstrip().startswith('|'):
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells) >= 2 and req_id.match(cells[0]) and cells[1].lower() in done_status:
            row = ' '.join(cells).lower()
            if not re.search(r'#\d+|/pull/\d+|reconcile', row):
                sys.exit(f'PROGRESS.md:{i} done-status requirement row without evidence link')
EOF
```

  (Artifact rows — PRD, naming, tracker — are exempt: only requirement/slice rows
  need evidence links; their completion is recorded in Notes.)

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

IDD PRD repos are small (2 files, PRD + tracker). Forecast 1–2 rounds. Round 1
surfaces the ID-closure and status-semantics class; the neutral verdict round
reliably surfaces cross-reference errors and semantic self-contradictions in
the slice/status wording (the same verdict-gate behavior as cdd-prd repos).
Evidence: TraceHeist contract 2026-08-12 — the repo fell to `prose-spec` because no
idd profile existed (cdd-prd requires PLAN files), and the closure lens that
matters for an issue-driven repo (requirement IDs ↔ tracker rows ↔ issue
contracts) was only approximated by ad-hoc charter ACs. Five existing repos
match this profile (`reservation-bola-demo-prd`, `docscan-prd`,
`cloud-sandbox-prd`, `session-echo-prd`, `stateless-mcp-incident-lab-prd`).
