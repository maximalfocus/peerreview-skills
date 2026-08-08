# Problem Charter

<!--
One run, one active review contract. `/peerreview` normally writes this schema
into private temporary storage, not the reviewed repo. It is read adversarially:
the reviewer checks the artifacts AGAINST this charter
and runs the Verification block independently — it does not trust prose claims.
Keep acceptance criteria traceable to the Source of truth, not builder-invented.
-->

- **Producer:** <skill that generated this repo, e.g. cdd-auto / system / tutorial / manual>
- **Generated:** <YYYY-MM-DD>
- **Source of truth:** <path/URL the criteria derive from — CDD golden files, /system source doc, tutorial TOC, PRD, etc.>

## Problem

<1–3 sentences: the problem this repo exists to solve. State the problem, not the solution.>

## Scope

- In: <what this repo is responsible for>

## Non-goals

- Out: <explicitly excluded, so the reviewer does not flag its absence>

## Acceptance criteria

<!-- Each item must be objectively checkable. Prefer criteria that trace to the
     Source of truth over ones the builder invented for itself. -->

- [ ] AC1 — <observable, testable statement>
- [ ] AC2 — <observable, testable statement>

## Verification

<!-- Deterministic commands the reviewer runs every round. Exit 0 = pass.
     Must be fail-closed and must NOT change host state or hit the network
     unless the repo's whole purpose is network I/O (then sandbox it).
     HTML repos: stale system libxml2 `xmllint --html` emits "Tag <X>
     invalid" for VALID HTML5 (figure, figcaption, section, nav, header,
     footer, article, aside, details, summary, mark, time, main) — filter
     those out (grep -v) or the gate fail-closes on a conformant artifact;
     fail only on real "parser error" lines after that filter.
     Source+rendered-artifact repos (Mermaid/PlantUML/Graphviz/etc.): do
     NOT stop at "renders without error" — a source edited without
     regenerating its committed image ships a STALE artifact that passes
     that check. Re-render every source to a tmp dir and perceptual-diff
     vs the committed artifact (e.g. PIL ImageChops RMSE + getbbox; ~0 and
     bbox=None == faithful); a non-trivial diff is a real defect.
     PIN the renderer version and render OFFLINE/cache-only (e.g.
     `npx --no-install -p @mermaid-js/mermaid-cli@X.Y.Z mmdc …` — never
     `@latest`) so the guard is deterministic + network-free; a floating
     `@latest` both hits the network and can change rendering out from under
     the committed PNG. FAIL CLOSED if the renderer is absent — a guard that
     SKIPS yet still greens lets a stale image through (the renderer is a
     project toolchain dep). touchstone 2026-05-25: @latest broke hermeticity;
     a skip-and-green was caught at the verdict and replaced with fail-closed.
     EXCEPTION — inline Mermaid in a `.md` (no committed image): GitHub renders
     it natively, so there is NO committed artifact to go stale and fail-closed-
     red is wrong (it reds the gate over an absent optional tool). Instead the AC
     must NOT claim "parses" while only checking a type-prefix — scope its wording
     to the deterministic structural check (non-empty + closing fence + recognized
     diagram-type keyword), run full `mmdc` only when present, and record a
     Residual for the full-parse gap (validate the blocks out-of-band via the
     Mermaid-Chart MCP validator, `valid:true`). minheap-architecture 2026-06-13:
     verdict-1 flagged AC5 claiming "parses" while structurally-checking only —
     fixed by scoping the claim + a residual, not by reddening the gate.
     Serve-and-curl gates (build a server, background it, run an HTTP suite):
     a stale pre-existing listener on the port false-passes the suite — the
     backgrounded start cannot trip `set -e`. Preflight that the port is free
     with an explicit `if curl …; then exit 1; fi` (NOT `! curl` — set -e
     ignores `!`-prefixed failures) and `kill -0 $SRV` after the suite proves
     your server served it. Also state the gate's complete host/network
     footprint positively (toolchain caches, /tmp scratch, ports bound,
     registry downloads on cold caches) — absolute "no host state/no network"
     claims cost one verdict round per phrase (blockchain-go 2026-06-10). -->

```sh
# e.g.
# ./scripts/validate-config.rb config.yaml
# npm test --silent
# # rendered-artifact fidelity (stale-image guard) — pinned, cache-only, fail-closed:
# V=@mermaid-js/mermaid-cli@11.15.0
# npx --no-install -p "$V" mmdc -V >/dev/null 2>&1 || { echo "renderer absent — AC unverifiable"; exit 1; }
# for s in src/*.mmd; do npx --no-install -p "$V" mmdc -i "$s" -o "/tmp/r/$(basename "$s" .mmd).png"; done
# python3 - <<'EOF'
# from PIL import Image,ImageChops; import glob,os,sys
# for c in glob.glob("png/*.png"):
#   r="/tmp/r/"+os.path.basename(c)
#   d=ImageChops.difference(Image.open(c).convert("RGB"),Image.open(r).convert("RGB"))
#   if d.getbbox(): sys.exit(f"STALE committed artifact: {c}")
# EOF
```

## Residuals & assumptions

- <known-acceptable gaps and explicit out-of-reviewer-scope items, e.g.
  "runtime behaviour on real hardware is unverified by design (would change host state)">
