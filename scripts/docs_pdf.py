#!/usr/bin/env python3
"""Join the DocC articles listed in docs/pdf_articles.yaml into one printable PDF.

Usage (from anywhere):  scripts/docs_pdf.py [docs/pdf_articles.yaml]
Needs pandoc and pdflatex. DocC-only markup (@Metadata blocks, <doc:...> links,
``Symbol`` links, image names without extension) is converted to plain Markdown.
"""
import re
import subprocess
import sys
from pathlib import Path
from string import Template

import yaml

setTmplt = lambda tmpl, dct: Template(tmpl).substitute(dct)

ROOT = Path(__file__).resolve().parent.parent

PART_TMPL = "\n\n\\part{$name}\n\n"
ARTICLE_TMPL = "\n\n$body\n\n\\newpage\n"
META_TMPL = """---
title: "$title"
author: "$author"
documentclass: report
toc: true
toc-depth: 2
geometry: margin=2.5cm
colorlinks: true
---
"""


def strip_directives(text):
    """Remove DocC @Directive { ... } blocks (brace-balanced, may span lines)."""
    out, i = [], 0
    for m in re.finditer(r"^[ \t]*@\w+[^\n{]*\{", text, re.M):
        if m.start() < i:
            continue
        depth, j = 0, m.end() - 1
        while j < len(text):
            depth += {"{": 1, "}": -1}.get(text[j], 0)
            j += 1
            if depth == 0:
                break
        out.append(text[i:m.start()])
        i = j
    out.append(text[i:])
    return "".join(out)


def find_image(name, image_dirs):
    cands = [name] if Path(name).suffix else [name + ".png", name]
    for d in image_dirs:
        for c in cands:
            p = ROOT / d / c
            if p.is_file():
                return str(p)
    return None


def convert(text, image_dirs):
    text = strip_directives(text)
    text = re.sub(r"<doc:([^>]+)>", r"*\1*", text)          # article links
    text = re.sub(r"``([^`]+)``", r"`\1`", text)             # symbol links

    def img(m):
        path = find_image(m.group(2), image_dirs)
        return f"![{m.group(1)}]({path})" if path else f"*[figure: {m.group(1)}]*"
    text = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)", img, text)
    # Each article's first "# Title" becomes a chapter; demote nothing else.
    return text


def main():
    cfg_path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/pdf_articles.yaml"
    cfg = yaml.safe_load(cfg_path.read_text())
    chunks = [setTmplt(META_TMPL, cfg)]
    for part in cfg["parts"]:
        chunks.append(setTmplt(PART_TMPL, part))
        for art in part["articles"]:
            body = convert((ROOT / art).read_text(), cfg["image_dirs"])
            chunks.append(setTmplt(ARTICLE_TMPL, {"body": body}))
    md = ROOT / cfg["output"]
    md = md.with_suffix(".md")
    md.write_text("".join(chunks))
    out = ROOT / cfg["output"]
    subprocess.run(
        ["pandoc", str(md), "-o", str(out), "--pdf-engine=pdflatex",
         "--top-level-division=chapter", "-V", "fontenc=T1",
         "-H", str(ROOT / "docs/unicode_chars.sty")],
        check=True)
    print(out)


if __name__ == "__main__":
    main()
