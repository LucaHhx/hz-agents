"""docs.py req - 创建需求目录 (自动编号)"""

import re
from core import (
    find_project_root, get_next_req_number, resolve_req_dir,
    render, REQ_DIR_RE,
)


def cmd_req(args):
    root = find_project_root(args.root)
    name = args.req_name
    m = REQ_DIR_RE.match(name)
    if m:
        name = m.group(2)
    if not re.match(r"^[a-z0-9]+(-[a-z0-9]+)*$", name):
        print("错误: 需求名必须是 kebab-case (如 user-system, ledger)")
        return 1
    docs_dir = root / "docs"
    if not docs_dir.exists():
        print("错误: docs/ 不存在，请先运行 init")
        return 1
    existing = resolve_req_dir(docs_dir, name)
    if existing:
        print(f"错误: 需求目录已存在: {existing}")
        return 1
    num = get_next_req_number(docs_dir)
    full_name = f"{num}-{name}"
    req_dir = docs_dir / full_name
    req_dir.mkdir(parents=True)
    for target, src in [("plan.md", "plan.md"), ("tasks.md", "tasks.md"), ("log.md", "log.md")]:
        content = render(src, PLAN_NAME=name)
        if content:
            (req_dir / target).write_text(content, encoding="utf-8")
    print(f"✓ 已创建需求 → {req_dir}")
    return 0
