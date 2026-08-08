#!/usr/bin/env python3
"""Validate deterministic structure in a knowledge-skills study repository."""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
errors: list[str] = []
SOURCE_FILES = (ROOT / "context/sources.md", ROOT / "context/sources_zh.md")
CITING_ARTIFACTS = ("concept_graph.md", "critiques.md", "deep_dive.md", "summary_zh.md")
ID_RE = re.compile(r"\b([EZ]\d+)\b")


def fail(message: str) -> None:
    errors.append(message)


def sections(text: str) -> dict[str, str]:
    matches = list(re.finditer(r"^##\s+(.+?)\s*$", text, re.MULTILINE))
    return {
        match.group(1).strip(): text[match.end() : matches[i + 1].start() if i + 1 < len(matches) else len(text)]
        for i, match in enumerate(matches)
    }


known_ids: set[str] = set()
for source_file in SOURCE_FILES:
    if not source_file.is_file():
        fail(f"missing source index: {source_file.relative_to(ROOT)}")
        continue
    text = source_file.read_text(encoding="utf-8")
    entries = list(re.finditer(r"^###\s+\[([EZ]\d+)\].*$", text, re.MULTILINE))
    for i, entry in enumerate(entries):
        source_id = entry.group(1)
        if source_id in known_ids:
            fail(f"duplicate source ID: {source_id}")
        known_ids.add(source_id)
        block = text[entry.end() : entries[i + 1].start() if i + 1 < len(entries) else len(text)]
        tier = re.search(r"^-\s+Trust tier:\s*(Primary|Supplementary)\s*$", block, re.MULTILINE)
        snapshot = re.search(r"^-\s+Snapshot:\s*(.+?)\s*$", block, re.MULTILINE)
        if not tier or not snapshot:
            fail(f"{source_file.relative_to(ROOT)} {source_id}: missing trust tier or Snapshot")
            continue
        path_match = re.search(r"(context/(?:originals|originals-supplementary)/[^\s)`]+\.md)", snapshot.group(1))
        if tier.group(1) == "Primary" and path_match and not (ROOT / path_match.group(1)).is_file():
            fail(f"{source_id}: missing primary snapshot {path_match.group(1)}")

for name in CITING_ARTIFACTS:
    path = ROOT / name
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    split = re.split(r"^##\s+(?:引用文献\s*/\s*)?References\s*$", text, maxsplit=1, flags=re.MULTILINE)
    body_ids = set(ID_RE.findall(split[0]))
    reference_ids = set(ID_RE.findall(split[1])) if len(split) == 2 else set()
    unknown = (body_ids | reference_ids) - known_ids
    if unknown:
        fail(f"{name}: unknown source IDs: {', '.join(sorted(unknown))}")
    if body_ids and len(split) == 1:
        fail(f"{name}: cited IDs but no References section")
    missing_refs = body_ids - reference_ids
    extra_refs = reference_ids - body_ids
    if missing_refs:
        fail(f"{name}: citations missing from References: {', '.join(sorted(missing_refs))}")
    if extra_refs:
        fail(f"{name}: uncited IDs in References: {', '.join(sorted(extra_refs))}")

concept_path = ROOT / "concept_graph.md"
if concept_path.exists():
    text = concept_path.read_text(encoding="utf-8")
    part = sections(text)
    nodes = set(re.findall(r"^\|\s*(C\d+)\s*\|", part.get("Nodes", ""), re.MULTILINE))
    edge_rows = [line for line in part.get("Edges", "").splitlines() if re.match(r"^\|\s*C\d+\s*\|", line)]
    endpoints: set[str] = set()
    table_edges: Counter[tuple[str, str, str]] = Counter()
    for row in edge_rows:
        cells = [cell.strip() for cell in row.strip().strip("|").split("|")]
        ids = re.findall(r"\bC\d+\b", row)
        if len(ids) < 2 or len(cells) < 4:
            fail(f"concept_graph.md: malformed edge row: {row}")
            continue
        endpoints.update(ids[:2])
        table_edges[(ids[0], ids[1], cells[2])] += 1
        if not ID_RE.search(row) and "[inference]" not in row:
            fail(f"concept_graph.md: uncited edge row: {row}")
    graph_edges = Counter(
        (match.group(1), match.group(3), match.group(2).strip())
        for match in re.finditer(r"^\s*(C\d+)\s+[-.]+>\|([^|]+)\|\s*(C\d+)\s*$", part.get("Graph", ""), re.MULTILINE)
    )
    if table_edges != graph_edges:
        for edge, count in (table_edges - graph_edges).items():
            fail(f"concept_graph.md: edge table missing from Mermaid graph ({count}x): {edge}")
        for edge, count in (graph_edges - table_edges).items():
            fail(f"concept_graph.md: Mermaid edge missing from edge table ({count}x): {edge}")
    if not nodes:
        fail("concept_graph.md: no nodes parsed")
    for node in sorted(nodes - endpoints):
        fail(f"concept_graph.md: orphan node {node}")
    tour = re.findall(r"^\d+\.\s+\*\*(C\d+)\b", part.get("Learning Tour", ""), re.MULTILINE)
    counts = Counter(tour)
    for node in sorted(nodes):
        if counts[node] != 1:
            fail(f"concept_graph.md: tour contains {node} {counts[node]} times (expected 1)")
    for node in sorted(set(tour) - nodes):
        fail(f"concept_graph.md: tour references undefined node {node}")

for path in ROOT.glob("*.md"):
    text = path.read_text(encoding="utf-8")
    openings = len(re.findall(r"^```mermaid\s*$", text, re.MULTILINE))
    blocks = re.findall(r"^```mermaid\s*$\n(.*?)^```\s*$", text, re.MULTILINE | re.DOTALL)
    if openings != len(blocks):
        fail(f"{path.name}: unclosed Mermaid fence")
    for index, block in enumerate(blocks, 1):
        first = next((line.strip() for line in block.splitlines() if line.strip()), "")
        if not re.match(r"^(?:flowchart|graph|sequenceDiagram|mindmap|classDiagram|stateDiagram|gantt|erDiagram|pie|timeline|gitGraph|quadrantChart|requirementDiagram|journey)\b", first):
            fail(f"{path.name}: Mermaid block {index} has unknown diagram type: {first!r}")
        if re.search(r"(?:-->|-.->)\s*\|[^|]*<br\s*/?>[^|]*\|", block):
            fail(f"{path.name}: Mermaid block {index} uses <br/> in an edge label")

if errors:
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    raise SystemExit(1)
print(f"PASS: knowledge-artifact structure ({len(known_ids)} source IDs)")
