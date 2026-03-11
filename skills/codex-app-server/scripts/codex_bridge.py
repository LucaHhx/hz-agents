#!/usr/bin/env python3
"""Codex App-Server Bridge - 通过 stdio 协议程序化控制 Codex。

用法:
    python3 codex_bridge.py "你的任务描述"
    python3 codex_bridge.py --cwd /path/to/project "任务描述"
    python3 codex_bridge.py --model gpt-5.4 --effort high "任务描述"
    python3 codex_bridge.py --interactive
    python3 codex_bridge.py --debug "调试模式任务"
"""

import subprocess
import json
import sys
import time
import shutil
import threading
import queue
import argparse
import os
import collections


class CodexBridge:
    """与 codex app-server 的 stdio 双向通信桥接器。

    支持 context manager 用法:
        with CodexBridge() as bridge:
            bridge.initialize()
            bridge.create_thread(cwd="/path")
            text, cmds = bridge.send_task("任务描述")
    """

    def __init__(self, debug=False):
        self.proc = None
        self.msg_queue = queue.Queue()
        self._id_counter = 0
        self._id_lock = threading.Lock()
        self.thread_id = None
        self.debug = debug
        self._reader_thread = None

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        try:
            self.stop()
        except Exception:
            # 确保 __exit__ 不会因清理失败而掩盖原始异常
            pass
        return False

    def start(self):
        """启动 codex app-server 子进程。"""
        codex_path = shutil.which("codex")
        if not codex_path:
            raise FileNotFoundError(
                "未找到 codex 命令。请先安装: npm install -g @openai/codex"
            )

        self.proc = subprocess.Popen(
            [codex_path, "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self._reader_thread = threading.Thread(
            target=self._read_output, daemon=True
        )
        self._reader_thread.start()
        # 后台读取 stderr 防止缓冲区满卡住子进程
        self._stderr_lines = []
        self._stderr_thread = threading.Thread(
            target=self._read_stderr, daemon=True
        )
        self._stderr_thread.start()

    def _read_stderr(self):
        """后台线程：持续读取 stderr 防止缓冲区满。"""
        while self.proc and self.proc.poll() is None:
            try:
                line = self.proc.stderr.readline()
                if not line:
                    break
                self._stderr_lines.append(line.rstrip())
                # 只保留最近 50 行
                if len(self._stderr_lines) > 50:
                    self._stderr_lines = self._stderr_lines[-50:]
            except (OSError, ValueError):
                break

    def get_stderr(self, last_n=20):
        """获取最近的 stderr 输出，用于错误诊断。"""
        return "\n".join(self._stderr_lines[-last_n:])

    def _read_output(self):
        """后台线程：持续读取 stdout 的 JSONL 输出。"""
        while self.proc and self.proc.poll() is None:
            try:
                line = self.proc.stdout.readline()
                if not line:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                    if self.debug:
                        print(f"  [DEBUG recv] {json.dumps(msg, ensure_ascii=False)[:200]}", file=sys.stderr)
                    self.msg_queue.put(msg)
                except json.JSONDecodeError as e:
                    if self.debug:
                        print(f"  [DEBUG] JSON 解析失败: {e} | 原始行: {line[:100]}", file=sys.stderr)
            except (OSError, ValueError):
                break

    def send(self, method, params=None, is_notification=False):
        """发送 JSON-RPC 消息。notification 不带 id。"""
        if not self.proc or self.proc.poll() is not None:
            raise RuntimeError("codex app-server 进程未运行")

        msg = {"method": method}
        if params:
            msg["params"] = params
        if not is_notification:
            with self._id_lock:
                self._id_counter += 1
                msg["id"] = self._id_counter

        payload = json.dumps(msg, ensure_ascii=False) + "\n"
        if self.debug:
            print(f"  [DEBUG send] {payload.strip()[:200]}", file=sys.stderr)

        self.proc.stdin.write(payload)
        self.proc.stdin.flush()
        return msg.get("id")

    def wait_response(self, msg_id, timeout=30):
        """等待指定 id 的响应，其他消息按序暂存。"""
        start = time.time()
        pending = collections.deque()
        while time.time() - start < timeout:
            try:
                msg = self.msg_queue.get(timeout=1)
                if msg.get("id") == msg_id:
                    # 按原始顺序回放暂存消息
                    while pending:
                        self.msg_queue.put(pending.popleft())
                    return msg
                pending.append(msg)
            except queue.Empty:
                continue
        # 超时：按顺序回放
        while pending:
            self.msg_queue.put(pending.popleft())
        return None

    def initialize(self, client_name="codex_bridge"):
        """执行初始化握手。"""
        mid = self.send("initialize", {
            "clientInfo": {
                "name": client_name,
                "title": "Codex Bridge",
                "version": "0.2.0",
            }
        })
        resp = self.wait_response(mid, timeout=15)
        if not resp:
            stderr_hint = self.get_stderr(5)
            raise RuntimeError(f"初始化超时：codex app-server 无响应\nstderr: {stderr_hint}")
        if "error" in resp:
            raise RuntimeError(f"初始化失败: {resp['error']}")

        # 发送 initialized 通知（注意：没有 id）
        self.send("initialized", is_notification=True)
        # 等待服务端就绪，用短轮询替代固定 sleep
        self._drain_events(max_wait=1.0)
        return resp["result"]

    def create_thread(self, model="gpt-5.4", cwd=None, sandbox="danger-full-access"):
        """创建对话线程。"""
        params = {
            "model": model,
            "approvalPolicy": "never",
            "sandbox": sandbox,  # 必须 kebab-case
        }
        if cwd:
            params["cwd"] = cwd
        mid = self.send("thread/start", params)
        resp = self.wait_response(mid, timeout=20)
        if not resp:
            stderr_hint = self.get_stderr(5)
            raise RuntimeError(f"创建 thread 超时\nstderr: {stderr_hint}")
        if "error" in resp:
            raise RuntimeError(f"创建 thread 失败: {resp['error']}")

        self.thread_id = resp["result"]["thread"]["id"]
        self._drain_events(max_wait=1.0)
        return self.thread_id

    def _drain_events(self, max_wait=1.0):
        """排空队列中的噪音事件。"""
        deadline = time.time() + max_wait
        while time.time() < deadline:
            try:
                self.msg_queue.get(timeout=0.2)
            except queue.Empty:
                break

    def send_task(self, text, model="gpt-5.4", effort="medium", cwd=None, timeout=300):
        """发送一个任务 turn 并等待完成，返回 (agent_text, commands)。"""
        if not self.thread_id:
            raise RuntimeError("请先调用 create_thread()")

        params = {
            "threadId": self.thread_id,
            "input": [{"type": "text", "text": text}],
            "model": model,
            "effort": effort,
        }
        if cwd:
            params["cwd"] = cwd

        mid = self.send("turn/start", params)
        resp = self.wait_response(mid, timeout=15)
        if not resp:
            stderr_hint = self.get_stderr(5)
            raise RuntimeError(f"启动 turn 超时：codex app-server 无响应\nstderr: {stderr_hint}")
        if "error" in resp:
            raise RuntimeError(f"启动 turn 失败: {resp['error']}")

        return self._collect_turn_events(timeout=timeout)

    def _collect_turn_events(self, timeout=300):
        """收集 turn 的所有事件，返回 (agent_text, commands)。"""
        agent_text = ""
        commands = []
        # 用 set 去重，防止两套事件命名导致同一命令被记录两次
        seen_cmd_ids = set()
        start = time.time()
        last_activity = time.time()

        while time.time() - start < timeout:
            try:
                msg = self.msg_queue.get(timeout=3)
                last_activity = time.time()
            except queue.Empty:
                # 超过 120 秒无任何活动且无输出，认为异常
                if time.time() - last_activity > 120 and not agent_text and not commands:
                    print("\n[警告] 长时间无响应，退出等待", file=sys.stderr)
                    break
                continue

            method = msg.get("method", "")
            params = msg.get("params", {})

            # Turn 完成（两套事件名都要处理）
            if method in ("turn/completed", "codex/event/task_complete"):
                if method == "turn/completed":
                    status = params.get("turn", {}).get("status", "?")
                    print(f"\n[完成] 状态={status}")
                break

            # Agent 文本流式输出
            elif method in ("item/agentMessage/delta",
                            "codex/event/agent_message_content_delta"):
                delta = params.get("textDelta", "") or params.get("delta", "")
                if delta:
                    agent_text += delta
                    print(delta, end="", flush=True)

            # Agent 完整消息
            elif method == "codex/event/agent_message":
                text = params.get("text", "") or params.get("content", "")
                if text and not agent_text:
                    agent_text = text

            # 命令开始（去重：同一命令可能通过两套事件名各报一次）
            elif method in ("codex/event/exec_command_begin", "item/started"):
                if method == "codex/event/exec_command_begin":
                    cmd = params.get("command", "")
                    cmd_id = params.get("callId") or params.get("id") or cmd
                else:
                    item = params.get("item", {})
                    cmd = item.get("command", "")
                    cmd_id = item.get("id") or cmd
                    if not cmd:
                        continue
                if cmd and cmd_id not in seen_cmd_ids:
                    seen_cmd_ids.add(cmd_id)
                    print(f"\n  [命令] {cmd}")
                    commands.append({"command": cmd, "exitCode": None, "_id": cmd_id})

            # 命令完成（去重：只更新尚未设置 exitCode 的命令）
            elif method in ("codex/event/exec_command_end", "item/completed"):
                if method == "codex/event/exec_command_end":
                    ec = params.get("exitCode", "?")
                elif params.get("item", {}).get("type") == "commandExecution":
                    ec = params.get("item", {}).get("exitCode", "?")
                else:
                    continue
                if commands and commands[-1]["exitCode"] is None:
                    commands[-1]["exitCode"] = ec
                    print(f"  [命令结束] exit={ec}")

            # 跳过噪音事件
            elif method in ("codex/event/agent_message_delta",
                            "codex/event/token_count",
                            "thread/tokenUsage/updated",
                            "account/rateLimits/updated",
                            "thread/status/changed",
                            "codex/event/item_started",
                            "codex/event/item_completed",
                            "codex/event/user_message",
                            "codex/event/task_started",
                            "codex/event/exec_command_output",
                            "turn/started"):
                pass
            elif self.debug:
                print(f"  [DEBUG] 未处理事件: {method}", file=sys.stderr)

        # 清理内部字段
        for cmd in commands:
            cmd.pop("_id", None)
        return agent_text, commands

    def review(self, target="uncommittedChanges", delivery="inline",
               commit_sha=None, timeout=300):
        """启动代码审查，返回 (agent_text, commands)。

        Args:
            target: "uncommittedChanges" | "baseBranch" | "commit"
            delivery: "inline"（当前线程）| "detached"（新线程）
            commit_sha: 当 target="commit" 时需要指定
        """
        if not self.thread_id:
            raise RuntimeError("请先调用 create_thread()")

        target_param = {"type": target}
        if target == "commit" and commit_sha:
            target_param["sha"] = commit_sha

        params = {
            "threadId": self.thread_id,
            "delivery": delivery,
            "target": target_param,
        }

        mid = self.send("review/start", params)
        resp = self.wait_response(mid, timeout=15)
        if not resp:
            stderr_hint = self.get_stderr(5)
            raise RuntimeError(f"启动 review 超时\nstderr: {stderr_hint}")
        if "error" in resp:
            raise RuntimeError(f"启动 review 失败: {resp['error']}")

        return self._collect_turn_events(timeout=timeout)

    def send_followup(self, text, model="gpt-5.4", effort="medium", cwd=None, timeout=300):
        """在同一 thread 中发送追问（多轮对话）。"""
        return self.send_task(text, model=model, effort=effort, cwd=cwd, timeout=timeout)

    def interrupt(self):
        """中断当前正在执行的 turn。"""
        if self.thread_id:
            self.send("turn/interrupt", {"threadId": self.thread_id})

    def list_models(self, limit=10):
        """获取可用模型列表。"""
        mid = self.send("model/list", {"limit": limit})
        resp = self.wait_response(mid, timeout=10)
        if resp and "result" in resp:
            return resp["result"].get("data", [])
        return []

    def stop(self):
        """停止 app-server 进程。"""
        if self.proc:
            try:
                self.proc.stdin.close()
            except Exception:
                pass
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.proc = None


def _output_result(args, mode, agent_text, commands, thread_id):
    """统一输出结果，支持 --json 模式。"""
    if getattr(args, "json_output", False):
        result = {
            "status": "completed",
            "mode": mode,
            "thread_id": thread_id,
            "text": agent_text,
            "commands": commands,
            "command_count": len(commands),
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"\n\n{'='*60}")
        print(f"[统计] 执行了 {len(commands)} 条命令")
        print("=" * 60)


def run_single_task(args):
    """执行单次任务模式。"""
    with CodexBridge(debug=args.debug) as bridge:
        result = bridge.initialize()
        if not getattr(args, "json_output", False):
            print(f"[初始化成功] {result.get('userAgent', '')}")

        sandbox = getattr(args, "sandbox", "danger-full-access")
        thread_id = bridge.create_thread(
            model=args.model, cwd=args.cwd, sandbox=sandbox
        )
        if not getattr(args, "json_output", False):
            print(f"[线程创建] {thread_id}")
            print(f"\n{'='*60}")
            print(f"[任务] {args.task}")
            print("=" * 60)

        agent_text, commands = bridge.send_task(
            args.task, model=args.model, effort=args.effort, cwd=args.cwd
        )

        _output_result(args, "task", agent_text, commands, thread_id)

    return agent_text


def run_review(args):
    """执行代码审查模式。"""
    with CodexBridge(debug=args.debug) as bridge:
        result = bridge.initialize()
        if not getattr(args, "json_output", False):
            print(f"[初始化成功] {result.get('userAgent', '')}")

        # review 模式默认 read-only
        sandbox = getattr(args, "sandbox", "read-only") or "read-only"
        thread_id = bridge.create_thread(
            model=args.model, cwd=args.cwd, sandbox=sandbox
        )
        if not getattr(args, "json_output", False):
            print(f"[线程创建] {thread_id}")
            target = args.target
            print(f"\n{'='*60}")
            print(f"[审查] target={target}")
            print("=" * 60)

        agent_text, commands = bridge.review(
            target=args.target,
            commit_sha=getattr(args, "commit_sha", None),
        )

        _output_result(args, "review", agent_text, commands, thread_id)

    return agent_text


def run_interactive(args):
    """交互式多轮对话模式。"""
    with CodexBridge(debug=args.debug) as bridge:
        result = bridge.initialize()
        print(f"[初始化成功] {result.get('userAgent', '')}")

        thread_id = bridge.create_thread(
            model=args.model, cwd=args.cwd, sandbox=args.sandbox
        )
        print(f"[线程创建] {thread_id}")
        print("输入任务指令（输入 quit 退出，Ctrl+C 中断当前任务）：\n")

        while True:
            try:
                task = input(">>> ").strip()
            except (EOFError, KeyboardInterrupt):
                break

            if not task:
                continue
            if task.lower() in ("quit", "exit", "q"):
                break

            print(f"\n{'='*60}")
            try:
                agent_text, commands = bridge.send_task(
                    task, model=args.model, effort=args.effort, cwd=args.cwd
                )
                print(f"\n[统计] 执行了 {len(commands)} 条命令\n")
            except KeyboardInterrupt:
                bridge.interrupt()
                print("\n[已中断]")

    print("[已退出]")


def main():
    parser = argparse.ArgumentParser(description="Codex App-Server Bridge")
    parser.add_argument("task", nargs="?", help="要执行的任务描述")
    parser.add_argument("--cwd", default=os.getcwd(), help="工作目录（默认当前目录）")
    parser.add_argument("--model", default="gpt-5.4", help="模型名称（默认 gpt-5.4）")
    parser.add_argument("--effort", default="medium",
                        choices=["low", "medium", "high", "xhigh"],
                        help="推理深度（默认 medium）")
    parser.add_argument("--sandbox", default=None,
                        choices=["danger-full-access", "read-only", "workspace-write"],
                        help="沙箱策略（task 默认 danger-full-access，review 默认 read-only）")
    parser.add_argument("--interactive", "-i", action="store_true",
                        help="进入交互式多轮对话模式")
    parser.add_argument("--review", action="store_true",
                        help="代码审查模式（使用 review/start API）")
    parser.add_argument("--target", default="uncommittedChanges",
                        choices=["uncommittedChanges", "baseBranch", "commit"],
                        help="审查目标（默认 uncommittedChanges）")
    parser.add_argument("--commit-sha", default=None,
                        help="审查指定 commit（--target commit 时使用）")
    parser.add_argument("--json", dest="json_output", action="store_true",
                        help="以 JSON 格式输出结果（适合程序化调用）")
    parser.add_argument("--debug", "-d", action="store_true",
                        help="启用调试模式，输出原始消息")

    args = parser.parse_args()

    # 设置默认 sandbox
    if args.sandbox is None:
        args.sandbox = "read-only" if args.review else "danger-full-access"

    if args.interactive:
        run_interactive(args)
    elif args.review:
        run_review(args)
    elif args.task:
        run_single_task(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
