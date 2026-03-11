"""docs.py pipeline - 查看需求流水线状态"""

import re
from core import find_project_root, resolve_req_dir, REQ_DIR_RE, TASK_ROW_RE


def _count_tasks(tasks_file):
    """Count total and completed tasks in a tasks.md file."""
    if not tasks_file.exists():
        return 0, 0
    total = 0
    done = 0
    for line in tasks_file.read_text(encoding="utf-8").splitlines():
        m = TASK_ROW_RE.match(line)
        if m:
            total += 1
            status = m.group(3).strip()
            if status == "已完成":
                done += 1
    return total, done


def _check_files(req_dir, files):
    """Check if all files exist and are non-empty."""
    for f in files:
        path = req_dir / f
        if not path.exists() or path.stat().st_size == 0:
            return False
    return True


def _pipeline_status(req_dir):
    """Determine pipeline stage for a requirement directory."""
    stages = []

    # Stage 1: PM business docs
    has_pm = _check_files(req_dir, ["plan.md", "tasks.md"])
    stages.append(("PM 业务文档", "plan.md, tasks.md", has_pm, None))

    # Stage 2: Tech design
    has_tech = _check_files(req_dir, [
        "tech/design.md", "tech/tasks.md",
        "backend/design.md", "frontend/design.md",
        "backend/tasks.md", "frontend/tasks.md",
    ])
    stages.append(("Tech 技术方案", "tech/ + backend/ + frontend/", has_tech, None))

    # Stage 2.5: AutoCode
    tech_tasks_file = req_dir / "tech" / "tasks.md"
    autocode_total = 0
    autocode_done = 0
    if tech_tasks_file.exists():
        for line in tech_tasks_file.read_text(encoding="utf-8").splitlines():
            if "[autocode]" in line:
                m = TASK_ROW_RE.match(line)
                if m:
                    autocode_total += 1
                    if m.group(3).strip() == "已完成":
                        autocode_done += 1

    if autocode_total > 0:
        autocode_progress = f"autocode: {autocode_done}/{autocode_total}"
        autocode_is_done = autocode_done == autocode_total
        stages.append(("AutoCode", autocode_progress, autocode_is_done, autocode_progress))

    # Stage 3: UI design
    has_ui = _check_files(req_dir, ["ui/merge.html"])
    ui_label = "ui/merge.html"
    stages.append(("UI 设计稿", ui_label, has_ui, None))

    # Stage 4: Development
    fe_total, fe_done = _count_tasks(req_dir / "frontend" / "tasks.md")
    be_total, be_done = _count_tasks(req_dir / "backend" / "tasks.md")
    dev_progress = None
    dev_done = False
    if fe_total > 0 or be_total > 0:
        dev_progress = f"frontend: {fe_done}/{fe_total}, backend: {be_done}/{be_total}"
        dev_done = (fe_done == fe_total and be_done == be_total and fe_total > 0 and be_total > 0)
    stages.append(("开发", dev_progress or "未开始", dev_done, dev_progress))

    # Stage 5: QA testing
    qa_total, qa_done = _count_tasks(req_dir / "qa" / "tasks.md")
    has_qa_design = _check_files(req_dir, ["qa/design.md"])
    qa_progress = None
    qa_done_flag = False
    if qa_total > 0:
        qa_progress = f"qa: {qa_done}/{qa_total}"
        qa_done_flag = qa_done == qa_total
    stages.append(("QA 测试", qa_progress or ("已有测试方案" if has_qa_design else "未开始"), qa_done_flag, qa_progress))

    return stages


def cmd_pipeline(args):
    root = find_project_root(args.root)
    docs_dir = root / "docs"

    if args.req_name:
        req_dir = resolve_req_dir(docs_dir, args.req_name)
        if req_dir is None:
            print(f"错误: 需求目录不存在: {args.req_name}")
            return 1
        _print_pipeline(req_dir)
    else:
        # Show all requirements
        found = False
        for d in sorted(docs_dir.iterdir()):
            if d.is_dir() and REQ_DIR_RE.match(d.name):
                _print_pipeline(d)
                print()
                found = True
        if not found:
            print("未找到任何需求目录")
            return 1
    return 0


def _print_pipeline(req_dir):
    """Print pipeline status for a requirement."""
    stages = _pipeline_status(req_dir)
    print(f"需求 {req_dir.name} 流水线状态:")

    current_found = False
    for i, (name, detail, done, progress) in enumerate(stages):
        if done:
            prefix = "  ✓"
        elif not current_found and not done:
            prefix = "  →"
            current_found = True
        else:
            prefix = "  ○"

        if progress:
            print(f"{prefix} {name:<12} ({progress})")
        elif done:
            print(f"{prefix} {name:<12} ({detail})")
        else:
            print(f"{prefix} {name:<12} ({detail})")

    # Next step suggestion
    print()
    for i, (name, detail, done, _) in enumerate(stages):
        if not done:
            suggestions = {
                "PM 业务文档": f"下一步: 运行 /review-pm {req_dir.name} 创建业务文档",
                "Tech 技术方案": f"下一步: 运行 /review-tech {req_dir.name} 创建技术方案",
                "AutoCode": f"下一步: 运行 /cmd-autocode 完成 AutoCode 代码生成",
                "UI 设计稿": f"下一步: 运行 /review-ui {req_dir.name} 产出 UI 设计（如需自定义页面）",
                "开发": f"下一步: 运行 /unify-dev {req_dir.name} 启动开发",
                "QA 测试": f"下一步: 运行 /review-qa {req_dir.name} 执行验收测试",
            }
            print(suggestions.get(name, f"下一步: 继续 {name}"))
            break
    else:
        print("所有阶段已完成 ✓")
