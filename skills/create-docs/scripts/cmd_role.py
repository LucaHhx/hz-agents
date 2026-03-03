"""docs.py role - 创建角色目录"""

from core import find_project_root, resolve_req_dir, render


def cmd_role(args):
    root = find_project_root(args.root)
    req_name = args.req_name
    role_name = args.role_name
    docs_dir = root / "docs"
    req_dir = resolve_req_dir(docs_dir, req_name)
    if req_dir is None:
        print(f"错误: 需求目录不存在: {docs_dir / req_name}，请先运行 req {req_name}")
        return 1
    role_dir = req_dir / role_name
    if role_dir.exists():
        print(f"错误: 角色目录已存在: {role_dir}")
        return 1
    role_dir.mkdir(parents=True)
    content = render("design.md", REQ_NAME=req_name, ROLE=role_name)
    if content:
        (role_dir / "design.md").write_text(content, encoding="utf-8")
    content = render("tasks.md", PLAN_NAME=f"{req_name}/{role_name}")
    if content:
        (role_dir / "tasks.md").write_text(content, encoding="utf-8")
    print(f"✓ 已创建角色 → {role_dir}")
    return 0
