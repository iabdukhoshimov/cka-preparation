#!/usr/bin/env python3
"""Rebuild vault/Notes/*.md from notes/*.md (Obsidian flavour).

notes/ is the source of truth. Run:  python3 vault/build-vault.py
Conversions: frontmatter tags, prev/home/next nav, `### Analogies` -> [!example]+,
⚠️/🔥/💡 lines -> [!warning]/[!danger]/[!tip], <details> answers -> [!success]-,
links to other notes -> [[wikilinks]].
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "notes"
DST = ROOT / "vault" / "Notes"

TAGS = {
    "01": "cka/all-domains",
    "02": "cka/workloads\n  - cka/architecture",
    "03": "cka/workloads",
    "04": "cka/architecture",
    "05": "cka/storage",
    "06": "cka/networking",
    "07": "cka/architecture",
    "08": "cka/troubleshooting",
    "09": "cka/workloads",
    "10": "cka/architecture",
    "11": "cka/exam",
}
CALLOUTS = {"⚠️ ": "warning", "🔥 ": "danger", "💡 ": "tip", "🔑 ": "important"}


def links(line, names):
    line = re.sub(r"\[[^\]]*\]\(((\d\d-[\w-]+))\.md\)", lambda m: f"[[{m.group(1)}]]" if m.group(1) in names else m.group(0), line)
    line = re.sub(r"`((\d\d-[\w-]+))\.md`", lambda m: f"[[{m.group(1)}]]" if m.group(1) in names else m.group(0), line)
    return line


def convert(text, names):
    lines = text.split("\n")
    out = []
    i = 0
    in_code = False
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            in_code = not in_code
            out.append(line)
            i += 1
            continue
        if in_code:
            out.append(line)
            i += 1
            continue
        line = links(line, names)
        if line.startswith("### Analogies") or line.startswith("### The ") and "analogy" in line.lower():
            title = line[4:]
            out.append(f"> [!example]+ {title}")
            i += 1
            while i < len(lines) and lines[i].strip():
                out.append("> " + links(lines[i], names))
                i += 1
            continue
        if line.startswith("<details><summary>"):
            title = re.sub(r"<details><summary>(.*)</summary>", r"\1", line)
            out.append(f"> [!success]- {title}")
            i += 1
            if i < len(lines) and not lines[i].strip():
                i += 1
            while i < len(lines) and not lines[i].startswith("</details>"):
                out.append(("> " + links(lines[i], names)).rstrip() if lines[i].strip() else ">")
                i += 1
            i += 1
            continue
        kind = next((v for k, v in CALLOUTS.items() if line.startswith(k)), None)
        if kind:
            out.append(f"> [!{kind}]")
            out.append("> " + line.split(" ", 1)[1])
            i += 1
            # a trap list directly under "⚠️ Traps:" belongs to the callout
            while i < len(lines) and lines[i].strip() and (lines[i].lstrip().startswith("- ") or lines[i].startswith("  ")):
                out.append("> " + links(lines[i], names))
                i += 1
            continue
        out.append(line)
        i += 1
    return "\n".join(out)


def main():
    files = sorted(p for p in SRC.glob("[0-9][0-9]-*.md"))
    names = [p.stem for p in files]
    for idx, p in enumerate(files):
        prev = names[idx - 1] if idx > 0 else None
        nxt = names[idx + 1] if idx + 1 < len(names) else None
        nav = " · ".join(filter(None, [f"← [[{prev}]]" if prev else None, "[[00 Home|🏠 Home]]", f"[[{nxt}]] →" if nxt else None]))
        body = convert(p.read_text().rstrip("\n"), names)
        tag = TAGS.get(p.name[:2], "cka/notes")
        doc = f"---\ntags:\n  - {tag}\n---\n\n{nav}\n\n{body}\n\n---\n{nav}\n"
        (DST / p.name).write_text(doc)
    # drop vault notes whose source no longer exists
    for q in DST.glob("[0-9][0-9]-*.md"):
        if q.stem not in names:
            q.unlink()
            print("removed stale", q.name)
    print(f"built {len(files)} notes -> {DST.relative_to(ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
