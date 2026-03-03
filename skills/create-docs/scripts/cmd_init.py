"""docs.py init - 初始化 docs/ 目录"""

from pathlib import Path
from core import render


def cmd_init(args):
    root = Path(args.project_root).resolve()
    docs = root / "docs"
    if docs.exists():
        print(f"错误: docs/ 已存在: {docs}")
        return 1
    docs.mkdir(parents=True)
    for name in ["project.md", "CHANGELOG.md"]:
        content = render(name)
        if content:
            (docs / name).write_text(content, encoding="utf-8")
    content = render("project-tasks.md")
    if content:
        (docs / "tasks.md").write_text(content, encoding="utf-8")
    print(f"✓ 已创建 docs/ → {docs}")
    return 0
