"""caseyaml.py — minimal, dependency-free reader for cases/<case>/case.yaml.

case.yaml files use a deliberately small YAML subset (it is also parsed by
bench.sh in pure bash): top-level `key: value` pairs, one level of nested
mappings with 2-space indentation, inline lists (`caps: ["NET_ADMIN"]`), quoted
or bare scalars, `|` block scalars, `null`, and `#` comments.
"""

from __future__ import annotations

import json
import re
from pathlib import Path


def _scalar(raw: str):
    s = raw.strip()
    if not s:
        return None
    if s[0] in "\"'":
        q = s[0]
        end = s.find(q, 1)
        while end != -1 and q == '"' and s[end - 1] == "\\":
            end = s.find(q, end + 1)
        if end == -1:
            return s[1:]
        body = s[1:end]
        return json.loads(f'"{body}"') if q == '"' else body.replace("''", "'")
    s = re.sub(r"\s+#.*$", "", s).strip()
    if s.startswith("["):
        inner = s.strip("[]").strip()
        return [] if not inner else [_scalar(x) for x in inner.split(",")]
    if s in ("null", "~"):
        return None
    if s in ("true", "false"):
        return s == "true"
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    return s


def load_case_yaml(path: str | Path) -> dict:
    """Parse a case.yaml into nested dicts (one level of nesting)."""
    data: dict = {}
    parent = None
    block = None            # (container dict, key) collecting a | block scalar
    block_lines: list[str] = []
    for line in Path(path).read_text().splitlines():
        if block is not None:
            if line.startswith("    ") or not line.strip():
                block_lines.append(line[4:])
                continue
            block[0][block[1]] = "\n".join(block_lines).strip("\n")
            block, block_lines = None, []
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.match(r"^(\s*)([A-Za-z0-9_]+):(.*)$", line)
        if not m:
            continue
        indent, key, rest = len(m.group(1)), m.group(2), m.group(3)
        target = data if indent == 0 else (data.setdefault(parent, {}) if parent else data)
        if indent == 0:
            parent = None
        if rest.strip() in ("|", "|-", ">", ">-"):
            block = (target, key)
            continue
        if indent == 0 and not rest.strip():
            data[key] = {}
            parent = key
            continue
        target[key] = _scalar(rest)
    if block is not None:
        block[0][block[1]] = "\n".join(block_lines).strip("\n")
    return data
