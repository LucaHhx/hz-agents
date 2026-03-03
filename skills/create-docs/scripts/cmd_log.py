"""docs.py log - 添加日志"""

from core import find_project_root, resolve_req_dir, add_log_entry, VALID_LOG_TYPES


def cmd_log(args):
    root = find_project_root(args.root)
    docs_dir = root / "docs"
    req_dir = resolve_req_dir(docs_dir, args.req_name)
    if req_dir is None:
        print(f"错误: 需求 {args.req_name} 不存在")
        return 1
    log_file = req_dir / "log.md"
    if not log_file.exists():
        print(f"错误: {log_file} 不存在")
        return 1
    if args.type not in VALID_LOG_TYPES:
        print(f"错误: 无效类型 '{args.type}'，可选: {' / '.join(sorted(VALID_LOG_TYPES))}")
        return 1
    add_log_entry(log_file, args.type, args.message)
    print(f"✓ [{args.type}] {args.message}")
    return 0
