"""docs.py status - 查看状态"""

from core import find_project_root, resolve_req_dir, parse_task_row


def cmd_status(args):
    root = find_project_root(args.root)
    docs_dir = root / "docs"
    if not docs_dir.exists():
        print("错误: docs/ 不存在")
        return 1

    if args.req_name:
        resolved = resolve_req_dir(docs_dir, args.req_name)
        if resolved is None:
            print(f"错误: 需求 {args.req_name} 不存在")
            return 1
        req_dirs = [resolved]
    else:
        req_dirs = sorted(
            d for d in docs_dir.iterdir()
            if d.is_dir() and (d / "plan.md").exists()
        )

    if not req_dirs:
        print("暂无需求")
        return 0

    for req_dir in req_dirs:
        name = req_dir.name
        tasks_file = req_dir / "tasks.md"
        if not tasks_file.exists():
            continue

        counts = {"待办": 0, "进行中": 0, "已完成": 0, "已取消": 0}
        for line in tasks_file.read_text(encoding="utf-8").split("\n"):
            parsed = parse_task_row(line)
            if parsed and parsed[2] in counts:
                counts[parsed[2]] += 1

        total = sum(counts.values())
        if total > 0:
            pct = counts["已完成"] * 100 // total
            bar = "█" * (pct // 5) + "░" * (20 - pct // 5)
            print(f"\n📋 {name}  {bar} {pct}%")
            parts = [f"{k}:{v}" for k, v in counts.items() if v > 0]
            print(f"  {' | '.join(parts)}")

        role_dirs = sorted(
            d for d in req_dir.iterdir()
            if d.is_dir() and (d / "tasks.md").exists()
        )
        for role_dir in role_dirs:
            role_name = role_dir.name
            role_tasks = role_dir / "tasks.md"
            rcounts = {"待办": 0, "进行中": 0, "已完成": 0, "已取消": 0}
            for line in role_tasks.read_text(encoding="utf-8").split("\n"):
                parsed = parse_task_row(line)
                if parsed and parsed[2] in rcounts:
                    rcounts[parsed[2]] += 1
            rtotal = sum(rcounts.values())
            if rtotal > 0:
                rpct = rcounts["已完成"] * 100 // rtotal
                rbar = "█" * (rpct // 5) + "░" * (20 - rpct // 5)
                print(f"  └─ {role_name}  {rbar} {rpct}%")
                rparts = [f"{k}:{v}" for k, v in rcounts.items() if v > 0]
                print(f"     {' | '.join(rparts)}")

    return 0
