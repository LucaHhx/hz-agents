"""Shared utilities for docs CLI."""

import re
from pathlib import Path
from datetime import date


SKILL_ROOT = Path(__file__).parent.parent
TEMPLATES_DIR = SKILL_ROOT / "assets" / "templates"

VALID_LOG_TYPES = {"决策", "变更", "修复", "新增", "测试", "备注", "完成"}
TASK_ROW_RE = re.compile(
    r"^\|\s*(\d+)\s*\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|$"
)
REQ_TASK_ROW_RE = re.compile(
    r"^\|\s*(\d+)\s*\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|$"
)
REQ_DIR_RE = re.compile(r"^(\d+)-(.+)$")


def find_project_root(hint=None):
    """Walk up from hint (or cwd) to find directory containing docs/."""
    start = Path(hint).resolve() if hint else Path.cwd()
    for p in [start] + list(start.parents):
        if (p / "docs").is_dir():
            return p
    return start


def get_next_req_number(docs_dir):
    """Scan existing numbered directories and return next number."""
    max_num = 0
    for d in docs_dir.iterdir():
        if d.is_dir():
            m = REQ_DIR_RE.match(d.name)
            if m:
                max_num = max(max_num, int(m.group(1)))
    return max_num + 1


def resolve_req_dir(docs_dir, req_name):
    """Resolve requirement name to actual directory path.

    Accepts:
      - Full name with prefix: '1-user-system'
      - Short name without prefix: 'user-system' -> finds N-user-system/
    Returns the Path if found, None otherwise.
    """
    exact = docs_dir / req_name
    if exact.is_dir():
        return exact
    for d in sorted(docs_dir.iterdir()):
        if d.is_dir():
            m = REQ_DIR_RE.match(d.name)
            if m and m.group(2) == req_name:
                return d
    return None


def resolve_tasks_file(root, req_name, role=None):
    """Resolve the correct tasks.md path based on req and optional role."""
    docs_dir = root / "docs"
    req_dir = resolve_req_dir(docs_dir, req_name)
    if req_dir is None:
        req_dir = docs_dir / req_name
    if role:
        return req_dir / role / "tasks.md"
    return req_dir / "tasks.md"


def render(template_name, **kwargs):
    """Read template file and replace {{PLACEHOLDER}}s."""
    path = TEMPLATES_DIR / template_name
    if not path.exists():
        return None
    content = path.read_text(encoding="utf-8")
    content = content.replace("{{DATE}}", date.today().isoformat())
    for k, v in kwargs.items():
        content = content.replace(f"{{{{{k}}}}}", v)
    return content


def parse_task_row(line):
    """Parse task table row -> (num, desc, status, start, end, note) or None."""
    m = TASK_ROW_RE.match(line)
    return tuple(g.strip() for g in m.groups()) if m else None


def parse_req_task_row(line):
    """Parse L1 requirement table row -> (num, name, status, owner, note) or None."""
    m = REQ_TASK_ROW_RE.match(line)
    return tuple(g.strip() for g in m.groups()) if m else None


def fmt_task_row(num, desc, status, start, end, note):
    return f"| {num} | {desc} | {status} | {start} | {end} | {note} |"


def fmt_req_task_row(num, name, status, owner, note):
    return f"| {num} | {name} | {status} | {owner} | {note} |"


def add_log_entry(log_file, entry_type, message):
    """Append entry to log.md under today's date section (newest first)."""
    today = date.today().isoformat()
    lines = log_file.read_text(encoding="utf-8").split("\n")
    entry = f"- [{entry_type}] {message}"
    header = f"## {today}"

    header_idx = next(
        (i for i, l in enumerate(lines) if l.strip() == header), None
    )

    if header_idx is not None:
        insert = header_idx + 1
        while insert < len(lines) and lines[insert].strip() == "":
            insert += 1
        lines.insert(insert, entry)
    else:
        first = next(
            (i for i, l in enumerate(lines)
             if re.match(r"^## \d{4}-\d{2}-\d{2}", l.strip())),
            None,
        )
        new_section = [header, "", entry, ""]
        if first is not None:
            lines[first:first] = new_section
        else:
            lines.extend([""] + new_section)

    log_file.write_text("\n".join(lines), encoding="utf-8")
