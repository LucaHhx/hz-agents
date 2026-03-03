"""docs.py fix - 创建/管理修复记录"""

import re
from pathlib import Path
from datetime import date
from core import find_project_root, render

FIX_DIR_RE = re.compile(r"^(\d+)-(.+)$")


def _get_fixes_dir(root):
    """Get or create docs/fixes/ directory."""
    fixes = root / "docs" / "fixes"
    if not fixes.exists():
        fixes.mkdir(parents=True)
        log_tpl = render("fixes-log.md")
        if log_tpl:
            (fixes / "log.md").write_text(log_tpl, encoding="utf-8")
    return fixes


def _get_next_fix_number(fixes_dir):
    """Scan existing fix files and return next number."""
    max_num = 0
    for f in fixes_dir.iterdir():
        if f.is_file() and f.suffix == ".md" and f.name != "log.md":
            m = FIX_DIR_RE.match(f.stem)
            if m:
                max_num = max(max_num, int(m.group(1)))
    return max_num + 1


def _append_fix_to_log(fixes_dir, fix_id, title, severity):
    """Append fix entry to fixes/log.md."""
    log_file = fixes_dir / "log.md"
    today = date.today().isoformat()
    entry = f"| {fix_id} | [{title}]({fix_id}-{_slugify(title)}.md) | {severity} | {today} | 已修复 |"

    content = log_file.read_text(encoding="utf-8")
    lines = content.split("\n")
    # Find the last table row and append after it
    last_table = len(lines) - 1
    while last_table >= 0 and not lines[last_table].startswith("|"):
        last_table -= 1
    lines.insert(last_table + 1, entry)
    log_file.write_text("\n".join(lines), encoding="utf-8")


def _slugify(text):
    """Convert text to filename-safe slug."""
    # Remove non-alphanumeric (keep CJK and hyphens)
    slug = re.sub(r"[^\w\u4e00-\u9fff-]", "-", text)
    slug = re.sub(r"-+", "-", slug).strip("-").lower()
    return slug[:60]


def cmd_fix(args):
    root = find_project_root(args.root)
    docs = root / "docs"
    if not docs.exists():
        print("错误: docs/ 不存在，请先运行 init")
        return 1

    fixes_dir = _get_fixes_dir(root)
    fix_id = _get_next_fix_number(fixes_dir)
    title = args.title
    severity = args.severity or "P1"
    slug = _slugify(title)
    filename = f"{fix_id}-{slug}.md"

    content = render("fix.md", FIX_ID=str(fix_id), FIX_TITLE=title, SEVERITY=severity)
    if content:
        (fixes_dir / filename).write_text(content, encoding="utf-8")

    _append_fix_to_log(fixes_dir, fix_id, title, severity)
    print(f"✓ 已创建修复记录 → docs/fixes/{filename}")
    return 0


def cmd_fix_list(args):
    root = find_project_root(args.root)
    fixes_dir = root / "docs" / "fixes"
    if not fixes_dir.exists():
        print("暂无修复记录")
        return 0

    log_file = fixes_dir / "log.md"
    if log_file.exists():
        print(log_file.read_text(encoding="utf-8"))
    return 0
