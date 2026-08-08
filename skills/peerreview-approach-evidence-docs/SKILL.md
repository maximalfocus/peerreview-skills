---
name: peerreview-approach-evidence-docs
description: "Peer-review lenses for evidence-derived documentation repos — artifacts (diagrams/docs) whose correctness criterion is citation fidelity to EXTERNAL ground-truth repos"
disable-model-invocation: true
---

# Peer-review approach: evidence-derived documentation repo

Reference loaded by `/peerreview` when Step 1.5 detects an evidence-derived
docs repo: markers are an evidence file (`SOURCES.md` or equivalent) whose
`path:line` citations point **outside the repo**, plus a charter Source-of-truth
naming external repo paths. Typical producers: architecture-diagram repos
(`/diagrams`, `/system`), audit/inventory docs derived from a codebase.
Commonly co-matches `source-rendered` (Mermaid/Graphviz + committed PNGs) —
load both; the stale-image guard stays with `source-rendered`.

The dominant defect class is **citation-fidelity drift to the external ground
truth** — not internal inconsistency and not rendering hygiene. Internal-only
review of such a repo checks the cheap 20%: every substantive finding in the
first run of this class came from independently opening the cited external
files (legacy-portal-infra 2026-07-05: ~20 confirmed findings over 7 rounds, all
ground-truth-sourced, zero false positives).

## Non-negotiable: brief the PEER with the external ground-truth paths

The round prompt MUST name the external ground-truth repo paths and instruct
the PEER to open cited files itself. A peer briefed only on the repo dir
reviews internal consistency and misses the dominant defect class entirely.
(The PEER can read cited files outside the repo dir — Pi's read tool is
unrestricted and Claude Code gets external dirs via `CLAUDE_ADD_DIRS`; this is
what makes the pass work.)
On co-edit rounds, the HOST's diff re-verification must re-check every edited
claim against the cited external file — an edit that "fixes" a finding by
rewording without re-reading the source is the self-serving failure mode here.
For a Claude PEER, pass every external root (and the active-charter directory
when its gate reads it) to `claude-round.sh` through newline-separated absolute
paths in `CLAUDE_ADD_DIRS`; non-interactive Claude otherwise auto-denies them.

## Brief the PEER with these lenses

### Lens 1 — Citation spot-check (cited line says what the claim says)

For a risk-ranked sample (and every load-bearing claim: identifiers, versions,
addresses/IDs, ownership), open the cited `path:line` and confirm it asserts
the claim — not merely mentions the same nouns. A citation that points at
adjacent-but-different content usually flags a claim that is itself wrong, not
just mis-cited. (legacy-portal-infra 2026-07-05: a WebSEAL entry-domain claim
cited `sys.properties:3-11` — keystore/date-format lines; the real WebSEAL
table at `:200-208` showed *different domains* (`portal.agency.example`, not
`portal2-*`), so the claim conflated legacy entry with the new-platform entry —
one bad cite exposed a two-generation domain mixup.)

### Lens 2 — Evidence provenance (environment / tier of the cited file)

Before accepting a fact as PROD/current, classify the cited file: test or dev
config, archived/legacy copy, template, and commented-out blocks are not
evidence for production claims. Search for the production counterpart
(deploy scripts, prod value files, `*-PRD*` properties) and prefer it.
(legacy-portal-infra: "WebSphere 5.x" was drawn from a committed `PORTAL TEST
Server.wsc` config using WAS 5.0 schemas; prod deploy jobs showed
`/portal/appl/WebSphere85/...` — prod is 8.5. Same axis: a UAT config proved a
delegation URL; the prod profile had to be opened separately to assert it.)

### Lens 3 — Re-derive structure from config, never from the drawn narrative

Topology/flow claims (hub-and-spoke, X-calls-Y, ownership) must be re-derived
from the primary config rows — attachment tables, share/ARN account IDs,
state-machine target ARNs — not accepted because the diagram/story is
coherent. Account/owner IDs embedded in ARNs are a cheap oracle. (love-
portal2-infra: the "single TGW hub" picture dissolved into THREE TGWs once
`tgw.csv`/`ram.csv`/`tgwa.csv` rows were read (central/LLZ/inspection, distinct
owners + share lists), and a mislabeled account was exposed by IAM-role ARNs;
Step Functions "invoke EKS" was actually Lambda-invoke per the ASL JSON.)

### Lens 4 — Completeness sweep (ground truth → artifact, not only artifact → ground truth)

Enumerate the ground truth's own inventory (top-level stacks/dirs, config
files, service lists) and check each is either represented or an explicit
non-goal. Citation-checking alone never catches omissions. (legacy-portal-infra:
an entire `intranet-gen` stack — its own VPC with two CIDRs — was missing
because the evidence base was built claim-first, never inventory-first.)

### Lens 5 — Provisioned ≠ deployed ≠ live (state-of-the-world qualifiers)

Where the artifact asserts something *runs* somewhere, demand the runtime
evidence class: apply/enable flags, deploy-target values (`cluster:`,
env values files), empty-but-present repos. Infra existing is not workloads
running; a pipeline *capable* of deploying is not a deployment. Facts that are
programme/operational status (not derivable from any repo) must be labelled as
such in the artifact and charter — and are then NOT findings (see below).
(legacy-portal-infra: intranet EKS clusters exist in IaC but every Helm values
file says `cluster: internet` and the intranet runtime repos are empty — three
diagrams needed "infra-only / no app deploys yet" qualifiers; Redis "Hibernate
L2 cache" label contradicted `use_second_level_cache: false` in the prod
profile.)

## Verification-gate amendments

- **Render gate:** the repo's own build (`make all` or equivalent) exits 0 on
  a clean tree, every round. Stale committed images: apply the
  `source-rendered` guard from the PROBLEM.md template when PNGs are committed.
- **Citation-existence gate (scriptable, Article 5):** extract every cited
  `path[:line[-line]]` from the evidence file; fail if the path does not exist
  under the ground-truth roots or a cited line exceeds the file's length. This
  catches path rot mechanically; only Lens 1 catches *semantic* mis-cites.
  Skip extracted tokens containing no `/` — `domain:port` and `ip:port`
  strings match `path:line` patterns and false-positive the gate (love-
  portal2-infra 2026-07-06: 6 baseline false-fails, all WebSEAL domains/proxy
  IPs; Step 0.5 self-test caught them).
- **Charter must pin the ground-truth roots.** If the charter's Source of
  truth omits a repo the evidence file cites (or the user names), treat as the
  stale-charter case in Step 0: refresh the active temp charter before the loop.
  (legacy-portal-infra's charter named 2 of the 4 ground-truth repos; the missing
  two contained the dominant findings.)

## What NOT to flag

- Items the artifact already marks `[UNVERIFIED]` / dashed / "not applied" —
  that notation is the honesty mechanism working, not a defect.
- Facts explicitly labelled as programme/operational status (user-supplied,
  not repo-derivable) — verify they are *labelled*, don't demand a repo cite.
- Footers/captions citing at glob level when the evidence file carries the
  line-level citations — flag only if the charter demands per-element
  `path:line` in the artifact itself.

## Forecast hint

Finding-rich class: multi-repo external ground truth sustains discovery across
rounds because each round samples different corners — expect **3–6 rounds**,
non-monotonic finding counts (legacy-portal-infra: 4→3→5→1→3→4→0 over 7
read-only rounds). Feed each round the prior rounds' resolved findings so the
PEER spends attention on unexplored ground truth instead of re-deriving fixes.
**Same-file verdict streak ⇒ sweep that file whole.** When two consecutive
verdicts cite the same inventory/estate/config file (a projects.csv, a service
registry), the HOST sweeps the ENTIRE file next round — every row either
represented, recorded as not-drawn, or marked unverified-non-local — instead of
letting verdicts drain it one row per round. Sweep to a *decision per row*, not
just the subset that triggered it: a partial sweep (non-local groups only)
still left two local rows for another verdict. (legacy-portal-infra 2026-07-06:
verdicts 1–4 each surfaced one devops-cac projects.csv row — golden images,
api-dr-deploy, application-dast, then orchestration+tosca; the full-inventory
close in round 6 produced CONVERGED at verdict 5.)
