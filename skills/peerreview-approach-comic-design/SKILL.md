---
name: peerreview-approach-comic-design
description: >-
  Peer-review lenses for a four-panel (起承转合) comic design brief — cultural adaptation vs
  translation, on-image claim accuracy, drawability, and argument fidelity across the beats
---

# Peer-review approach: four-panel comic design

Loaded by `/peerreview` (usually `--chat`) for a **comic design brief**: an `ARTIFACT.md` that
selects a four-panel (起承转合) comic design — a candidate pool table, a chosen design with four
panels (title, roles, accent, caption, per-panel picture + line), and often its own structural
`check.py`. A specialization of `prose-spec`. This reviews the DESIGN, not the rendered image; the
PNG is checked by the producer's own visual gate (e.g. comic-skills `/comic`), out of scope here.

The dominant defect class is a **culturally-adapted version that is actually a re-skin** — it copies
the source comic's staging and swaps only labels — compounded by **on-image claims stated as fact**
and **elements a raster model cannot draw**. The brief's structural `check.py` cannot see any of
these: on one 8-round run (dns-purpose-scams 2026-09-12) it passed at every round while eight real
defects were fixed. Brief the PEER with the lenses below, up front, so the re-skin and the statistic
surface in round 1 rather than round 5.

## Brief the PEER with these lenses

### Lens 1 — Adaptation, not translation (highest-yield)

When the charter asks for a culturally adapted version of an existing comic, the dominant failure is
a **re-skin**: the design reproduces the source's panel-for-panel staging, characters, and
progression and changes only surface labels (`.co.uk`→`.cn`, add 银联/实名). The two versions must
share ONLY the culture-neutral core — the claim, the 起承转合 arc, the accent — and recast the
pictures, characters, setting, idiom, and punchline for the target audience. A panel-for-panel copy
with swapped labels is a re-skin to rebuild around a native metaphor, not relabel. The structural
gate cannot detect this; it is a reading judgment. (dns-purpose-scams 2026-09-12 R5: a registrar-
counter re-skin was rebuilt into a native crossroads/signpost metaphor with a 被钓鱼 victim the
source lacked.)

### Lens 2 — Every on-image string is a factual claim; verify it, mark estimates in-panel

A comic compresses a nuanced source figure into one bold on-image line, overstating it as settled
fact. For every on-image number, named entity, and claim, open the source and confirm it: keep the
source's exact scope (85M is new **gTLD** registrations, not all domains) and mark disputed or
estimated figures in the PANEL itself (约, （估）, a question mark), not only in the post text. A
pictograph asserts too: two skulls in ten tags states ~1/5 as fact unless the panel also carries the
estimate cue. (dns 2026-09-12 ran four rounds from 「1/5进黑名单」→「约1/5是诈骗」→「约1/5涉诈（估）」
plus the gTLD scope; monkey-patch 2026-09-11 cut a false 收割 pun and a `time.time` "every caller"
overclaim.)

### Lens 3 — Drawability: every on-image element must survive a raster model

Raster image models garble long labels, dense legends, and any distinction that depends on line
style (a solid vs dashed skull). Enforce the style law by READING, not the structural gate (which
only counts cells and quoted lines): at most two short text lines per panel, short board/label text,
no line-style-dependent distinction, and at most three roles **counted by visible props** — an apron
shopkeeper and a prop-less passerby are two visible roles even when the brief calls them one. Prefer
a picture that carries the point over a sentence that labels it. (dns 2026-09-12: an over-long
statistics board with a solid/dashed-skull legend, and a four-role breach hidden behind a one-role
label.)

### Lens 4 — Argument fidelity across the four beats

The beats must preserve the source's real mechanism. The turn (panel 3) is a genuine reversal, not a
restatement. Mirror staging (1↔3, 2↔4), when used, reads the same in a 2×2 grid and a vertical 1×4
strip. The conclusion must not distort the mechanism: the tool must perform the same task it
replaces (a 收割机 harvests the ripe grain panel 1 reaps — not 锄禾 weeding of seedlings), and an
evader must route AROUND the system, not bypass it (a scammer hops to another lax registrar, not
self-issues). (coder-farmer-ai 2026-09-12 R2: 锄禾-vs-收割机 task mismatch; dns 2026-09-12 R8:
scammer bypassing registration rebuilt as a registrar hop.)

## Verification-gate amendments

The brief usually ships its own structural `check.py`: exactly one Chosen candidate scored yes on
every criterion; four panels in 起承转合 order; 1–2 「」 lines per panel; full-width punctuation for
Chinese; 1–3 declared roles. Run it every round — but it is **necessary, not sufficient**. It counts
structure and cannot judge factual accuracy (Lens 2), a re-skin (Lens 1), role-collapse by visible
prop (Lens 3), drawability, or argument fidelity (Lens 4). Those stay judgment lenses; a green gate
is the floor, never the verdict.

## What NOT to flag

- Keeping the source's four-beat argument ARC and mirror staging — that IS the shared idea; only the
  visual surfaces must be recast (Lens 1 targets copied pictures, not a copied argument).
- A pun kept in its literal term across languages (码农 → "code farmer") when the gloss lives in the
  post text, not the comic.
- An estimate stated AS an estimate (约 / 估); only an estimate stated as settled fact is a defect.
- The rendered PNG's fidelity, spelling, or layout — that is the producer's visual gate, not this
  design-brief review.

## Forecast hint

A first cultural adaptation usually needs 2–4 rounds (accuracy, then drawability). A re-skin that
must be rebuilt around a new native metaphor runs longer (dns: 8). Do not cap the loop, but brief
all four lenses up front: the re-skin and the mis-stated statistic are the two defects that, caught
late, cost the most rounds.
