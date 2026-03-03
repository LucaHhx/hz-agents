"""docs.py task/start/done - 任务生命周期管理"""

from datetime import date
from core import (
    find_project_root, resolve_req_dir, resolve_tasks_file,
    parse_task_row, fmt_task_row, add_log_entry,
)


def cmd_task(args):
    root = find_project_root(args.root)
    role = getattr(args, 'role', None)
    tasks_file = resolve_tasks_file(root, args.req_name, role)
    if not tasks_file.exists():
        print(f"错误: {tasks_file} 不存在")
        return 1

    lines = tasks_file.read_text(encoding="utf-8").split("\n")
    max_num = 0
    last_row_idx = -1
    for i, line in enumerate(lines):
        parsed = parse_task_row(line)
        if parsed:
            max_num = max(max_num, int(parsed[0]))
            last_row_idx = i

    new_num = max_num + 1
    new_row = fmt_task_row(str(new_num), args.description, "待办", "", "", "")

    if last_row_idx >= 0:
        lines.insert(last_row_idx + 1, new_row)
    else:
        lines.append(new_row)

    tasks_file.write_text("\n".join(lines), encoding="utf-8")
    target = f"{args.req_name}/{role}" if role else args.req_name
    print(f"✓ [{target}] 添加任务 #{new_num}: {args.description}")
    return 0


def cmd_start(args):
    root = find_project_root(args.root)
    role = getattr(args, 'role', None)
    docs_dir = root / "docs"
    req_dir = resolve_req_dir(docs_dir, args.req_name)
    if req_dir is None:
        print(f"错误: 需求 {args.req_name} 不存在")
        return 1
    tasks_file = resolve_tasks_file(root, args.req_name, role)
    log_file = req_dir / "log.md"
    if not tasks_file.exists():
        print(f"错误: {tasks_file} 不存在")
        return 1

    today = date.today().isoformat()
    num = str(args.task_number)
    lines = tasks_file.read_text(encoding="utf-8").split("\n")

    for i, line in enumerate(lines):
        parsed = parse_task_row(line)
        if parsed and parsed[0] == num:
            if parsed[2] == "进行中":
                print(f"任务 #{num} 已是进行中")
                return 0
            lines[i] = fmt_task_row(num, parsed[1], "进行中", today, parsed[4], parsed[5])
            tasks_file.write_text("\n".join(lines), encoding="utf-8")
            if log_file.exists():
                prefix = f"[{role}] " if role else ""
                add_log_entry(log_file, "变更", f"{prefix}开始任务 #{num}: {parsed[1]}")
            print(f"✓ 任务 #{num} → 进行中")
            return 0

    print(f"错误: 未找到任务 #{num}")
    return 1


def cmd_done(args):
    root = find_project_root(args.root)
    role = getattr(args, 'role', None)
    docs_dir = root / "docs"
    req_dir = resolve_req_dir(docs_dir, args.req_name)
    if req_dir is None:
        print(f"错误: 需求 {args.req_name} 不存在")
        return 1
    tasks_file = resolve_tasks_file(root, args.req_name, role)
    log_file = req_dir / "log.md"
    if not tasks_file.exists():
        print(f"错误: {tasks_file} 不存在")
        return 1

    today = date.today().isoformat()
    num = str(args.task_number)
    lines = tasks_file.read_text(encoding="utf-8").split("\n")

    for i, line in enumerate(lines):
        parsed = parse_task_row(line)
        if parsed and parsed[0] == num:
            if parsed[2] == "已完成":
                print(f"任务 #{num} 已是完成状态")
                return 0
            start = parsed[3] if parsed[3] else today
            note = parsed[5]
            if args.note:
                note = f"{note}; {args.note}" if note else args.note
            lines[i] = fmt_task_row(num, parsed[1], "已完成", start, today, note)
            tasks_file.write_text("\n".join(lines), encoding="utf-8")
            if log_file.exists():
                prefix = f"[{role}] " if role else ""
                msg = f"{prefix}完成任务 #{num}: {parsed[1]}"
                if args.note:
                    msg += f" ({args.note})"
                add_log_entry(log_file, "完成", msg)
            print(f"✓ 任务 #{num} → 已完成")
            return 0

    print(f"错误: 未找到任务 #{num}")
    return 1
