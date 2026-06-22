#!/usr/bin/env uv run
# /// script
# requires-python = ">=3.12"
# dependencies = ["markdown", "pygments"]
# ///

from __future__ import annotations

import argparse
import html
from pathlib import Path

import markdown

STYLES = """
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  font-size: 16px;
  line-height: 1.65;
  color: #111111;
  background: #ffffff;
}
main {
  max-width: 980px;
  margin: 0 auto;
  padding: 32px 28px 56px;
}
h1, h2, h3, h4, h5, h6 {
  color: #000000;
  line-height: 1.25;
  margin: 1.8em 0 0.6em;
}
h1 {
  font-size: 2.2rem;
  margin-top: 0.2em;
  padding-bottom: 0.35em;
  border-bottom: 2px solid #d9d9d9;
}
h2 {
  font-size: 1.55rem;
  padding-bottom: 0.2em;
  border-bottom: 1px solid #e5e5e5;
}
p, ul, ol, table, blockquote, pre {
  margin: 0 0 1rem;
}
ul, ol {
  padding-left: 1.5rem;
}
li + li {
  margin-top: 0.2rem;
}
a {
  color: #0b57d0;
  text-decoration: none;
}
a:hover {
  text-decoration: underline;
}
code {
  font-family: "SF Mono", "Fira Code", Menlo, Consolas, monospace;
  background: #f2f2f2;
  color: #111111;
  padding: 0.12em 0.35em;
  border-radius: 4px;
}
pre {
  background: #f7f7f7;
  color: #111111;
  border: 1px solid #e3e3e3;
  border-radius: 8px;
  padding: 14px 16px;
  overflow-x: auto;
}
pre code {
  background: transparent;
  padding: 0;
}
blockquote {
  border-left: 4px solid #cfcfcf;
  padding: 0.2rem 0 0.2rem 1rem;
  color: #333333;
  background: #fafafa;
}
table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.95rem;
}
th, td {
  text-align: left;
  vertical-align: top;
  padding: 0.6rem 0.7rem;
  border: 1px solid #dcdcdc;
}
th {
  background: #f3f3f3;
  color: #000000;
}
tr:nth-child(even) td {
  background: #fcfcfc;
}
hr {
  border: 0;
  border-top: 1px solid #dddddd;
  margin: 2rem 0;
}
strong {
  color: #000000;
}
@media (max-width: 720px) {
  main { padding: 20px 16px 40px; }
  body { font-size: 15px; }
}
"""


def make_title(text: str) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("# "):
            return stripped[2:].strip()
    for line in text.splitlines():
        stripped = line.strip()
        if stripped:
            return stripped.strip("# ")
    return "Campaign report"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert markdown into a light-themed standalone HTML file.")
    parser.add_argument("markdown_file", type=Path, help="Markdown source file")
    parser.add_argument("-o", "--output", type=Path, help="Output HTML path")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    source = args.markdown_file.read_text()
    title = make_title(source)
    body = markdown.markdown(source, extensions=["extra", "tables", "fenced_code", "codehilite", "sane_lists"])
    output = args.output or args.markdown_file.with_suffix(".html")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        "<!DOCTYPE html>\n"
        "<html lang=\"en\">\n"
        "<head>\n"
        "  <meta charset=\"utf-8\">\n"
        "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        f"  <title>{html.escape(title)}</title>\n"
        f"  <style>{STYLES}</style>\n"
        "</head>\n"
        "<body>\n"
        f"  <main>{body}</main>\n"
        "</body>\n"
        "</html>\n"
    )
    print(output)


if __name__ == "__main__":
    main()
