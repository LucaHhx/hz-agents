#!/usr/bin/env python3
"""
Project docs CLI - 项目文档管理工具 (三层架构)

Usage:
    docs.py init <project-root>                              初始化 docs/
    docs.py req <req-name> [--root DIR]                      创建需求目录
    docs.py role <req-name> <role-name> [--root DIR]         创建角色目录
    docs.py task <req-name> <description> [--role R] [--root] 添加任务
    docs.py start <req-name> <task-num> [--role R] [--root]  开始任务
    docs.py done <req-name> <task-num> [--note] [--role R] [--root] 完成任务
    docs.py log <req-name> <type> <message> [--root]         添加日志
    docs.py status [req-name] [--root]                       查看状态
"""

import sys
import argparse

# Add scripts dir to path for sibling imports
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

from cmd_init import cmd_init
from cmd_req import cmd_req
from cmd_role import cmd_role
from cmd_task import cmd_task, cmd_start, cmd_done
from cmd_log import cmd_log
from cmd_status import cmd_status
from cmd_fix import cmd_fix, cmd_fix_list


def main():
    p = argparse.ArgumentParser(prog="docs.py", description="项目文档管理 (三层架构)")
    sub = p.add_subparsers(dest="cmd")

    s = sub.add_parser("init", help="初始化 docs/")
    s.add_argument("project_root", help="项目根目录")

    s = sub.add_parser("req", help="创建需求目录")
    s.add_argument("req_name", help="需求名称 (kebab-case)")
    s.add_argument("--root", help="项目根目录")

    s = sub.add_parser("role", help="创建角色目录")
    s.add_argument("req_name", help="需求名称")
    s.add_argument("role_name", help="角色名称 (如 backend, frontend)")
    s.add_argument("--root", help="项目根目录")

    s = sub.add_parser("task", help="添加任务")
    s.add_argument("req_name", help="需求名称")
    s.add_argument("description", help="任务描述")
    s.add_argument("--role", help="角色名称 (写入角色级 tasks.md)")
    s.add_argument("--root", help="项目根目录")

    s = sub.add_parser("start", help="开始任务")
    s.add_argument("req_name", help="需求名称")
    s.add_argument("task_number", type=int, help="任务编号")
    s.add_argument("--role", help="角色名称")
    s.add_argument("--root", help="项目根目录")

    s = sub.add_parser("done", help="完成任务")
    s.add_argument("req_name", help="需求名称")
    s.add_argument("task_number", type=int, help="任务编号")
    s.add_argument("--note", help="完成备注")
    s.add_argument("--role", help="角色名称")
    s.add_argument("--root", help="项目根目录")

    s = sub.add_parser("log", help="添加日志")
    s.add_argument("req_name", help="需求名称")
    s.add_argument("type", help="类型: 决策/变更/修复/新增/测试/备注")
    s.add_argument("message", help="日志内容")
    s.add_argument("--root", help="项目根目录")

    s = sub.add_parser("status", help="查看状态")
    s.add_argument("req_name", nargs="?", help="需求名称 (不指定则全部)")
    s.add_argument("--root", help="项目根目录")

    s = sub.add_parser("fix", help="创建修复记录")
    s.add_argument("title", help="修复标题")
    s.add_argument("--severity", help="严重程度: P0/P1/P2 (默认 P1)", default="P1")
    s.add_argument("--root", help="项目根目录")

    s = sub.add_parser("fix-list", help="查看修复记录")
    s.add_argument("--root", help="项目根目录")

    args = p.parse_args()
    cmds = {
        "init": cmd_init, "req": cmd_req, "role": cmd_role,
        "task": cmd_task, "start": cmd_start, "done": cmd_done,
        "log": cmd_log, "status": cmd_status,
        "fix": cmd_fix, "fix-list": cmd_fix_list,
    }
    if args.cmd not in cmds:
        p.print_help()
        return 1
    return cmds[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
