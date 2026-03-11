"""docs.py check - 前置检查指定阶段所需文件"""

import re
import json
from core import find_project_root, resolve_req_dir

TASK_ROW_RE = re.compile(
    r"\|\s*(\d+)\s*\|([^|]*)\|([^|]*)\|"
)

PHASE_REQUIREMENTS = {
    "review-tech": {"required": ["plan.md", "tasks.md"]},
    "review-ui": {"required": ["plan.md"]},
    "review-all": {
        "required": [
            "plan.md", "tasks.md",
            "tech/design.md", "tech/tasks.md",
            "backend/design.md", "frontend/design.md",
            "backend/tasks.md", "frontend/tasks.md",
            "ui/merge.html", "ui/design.md",
        ]
    },
    "dev": {
        "required": [
            "plan.md",
            "frontend/design.md", "backend/design.md",
            "frontend/tasks.md", "backend/tasks.md",
        ]
    },
    "dev-full": {
        "required": [
            "plan.md",
            "frontend/design.md", "backend/design.md",
            "frontend/tasks.md", "backend/tasks.md",
            "qa/design.md",
        ],
        "optional_warn": ["ui/design.md", "ui/merge.html"],
    },
    "qa": {"required": ["qa/design.md"]},
}


def _check_autocode_done(req_dir):
    """检查 tech/tasks.md 中所有 [autocode] 任务是否已完成。"""
    tech_tasks = req_dir / "tech" / "tasks.md"
    if not tech_tasks.exists():
        return True  # 没有 tech 目录 = 没有 autocode 任务，放行
    for line in tech_tasks.read_text(encoding="utf-8").splitlines():
        if "[autocode]" in line:
            m = TASK_ROW_RE.match(line)
            if m and m.group(3).strip() not in ("已完成", "已取消"):
                return False
    return True


def cmd_check(args):
    root = find_project_root(args.root)
    docs_dir = root / "docs"
    req_dir = resolve_req_dir(docs_dir, args.req_name)
    if req_dir is None:
        result = {
            "pass": False,
            "missing": [],
            "warnings": [],
            "suggested_fix": f"需求目录不存在: {args.req_name}",
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 1

    phase = args.phase
    if phase not in PHASE_REQUIREMENTS:
        phases = ", ".join(PHASE_REQUIREMENTS.keys())
        print(f"错误: 未知阶段 '{phase}'，可选: {phases}")
        return 1

    spec = PHASE_REQUIREMENTS[phase]
    missing = []
    warnings = []

    for rel in spec.get("required", []):
        f = req_dir / rel
        if not f.exists() or f.stat().st_size == 0:
            missing.append(rel)

    for rel in spec.get("optional_warn", []):
        f = req_dir / rel
        if not f.exists() or f.stat().st_size == 0:
            warnings.append(f"{rel} 不存在（非阻塞）")

    # dev 和 dev-full 阶段额外检查 autocode 完成状态
    if phase in ("dev", "dev-full") and not _check_autocode_done(req_dir):
        missing.append("[autocode] 任务未完成 (tech/tasks.md)")

    passed = len(missing) == 0
    suggested_fix = ""
    if not passed:
        fix_map = {
            "plan.md": "/review-pm",
            "tasks.md": "/review-pm",
            "tech/design.md": "/review-tech",
            "tech/tasks.md": "/review-tech",
            "backend/design.md": "/review-tech",
            "frontend/design.md": "/review-tech",
            "backend/tasks.md": "/review-tech",
            "frontend/tasks.md": "/review-tech",
            "qa/design.md": "/review-tech",
            "ui/design.md": "/review-ui",
            "ui/merge.html": "/review-ui",
        }
        cmds = set()
        for m in missing:
            if "[autocode]" in m:
                cmds.add("/cmd-autocode")
            else:
                cmd = fix_map.get(m, "/doc-review")
                cmds.add(cmd)
        suggested_fix = f"建议先运行: {' 或 '.join(sorted(cmds))} {args.req_name}"

    result = {
        "pass": passed,
        "missing": missing,
        "warnings": warnings,
        "suggested_fix": suggested_fix,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if passed else 1
