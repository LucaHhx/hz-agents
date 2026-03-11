#!/usr/bin/env python3
"""Codex App-Server Bridge - 通过 stdio 协议程序化控制 Codex。

用法:
    python3 codex_bridge.py "你的任务描述"
    python3 codex_bridge.py --cwd /path/to/project "任务描述"
    python3 codex_bridge.py --model gpt-5.3-codex --effort high "任务描述"
    python3 codex_bridge.py --interactive
"""

import subprocess
import json
import sys
import time
import threading
import queue
import argparse
import os


class CodexBridge:
    """与 codex app-server 的 stdio 双向通信桥接器。"""

    def __init__(self):
        self.proc = None
        self.msg_queue = queue.Queue()
        self._id_counter = 0
        self.thread_id = None

    def start(self):
        """启动 codex app-server 子进程。"""
        self.proc = subprocess.Popen(
            ["codex", "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        threading.Thread(target=self._read_output, daemon=True).start()

    def _read_output(self):
        """后台线程：持续读取 stdout 的 JSONL 输出。"""
        while True:
            try:
                line = self.proc.stdout.readline()
                if not line:
                    break
                line = line.strip()
                if line:
                    self.msg_queue.put(json.loads(line))
            except Exception:
                break

    def send(self, method, params=None, is_notification=False):
        """发送 JSON-RPC 消息。notification 不带 id。"""
        msg = {"method": method}
        if params:
            msg["params"] = params
        if not is_notification:
            self._id_counter += 1
            msg["id"] = self._id_counter
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()
        return self._id_counter if not is_notification else None

    def wait_response(self, msg_id, timeout=30):
        """等待指定 id 的响应，其他消息暂存。"""
        start = time.time()
        pending = []
        while time.time() - start < timeout:
            try:
                msg = self.msg_queue.get(timeout=1)
                if msg.get("id") == msg_id:
                    for p in pending:
                        self.msg_queue.put(p)
                    return msg
                pending.append(msg)
            except queue.Empty:
                continue
        for p in pending:
            self.msg_queue.put(p)
        return None

    def initialize(self, client_name="codex_bridge"):
        """执行初始化握手。"""
        mid = self.send("initialize", {
            "clientInfo": {
                "name": client_name,
                "title": "Codex Bridge",
                "version": "0.1.0",
            }
        })
        resp = self.wait_response(mid)
        if not resp or "error" in resp:
            raise RuntimeError(f"初始化失败: {resp}")
        # 发送 initialized 通知（注意：没有 id）
        self.send("initialized", is_notification=True)
        time.sleep(0.5)
        return resp["result"]

    def create_thread(self, model="gpt-5.4", cwd=None, sandbox="danger-full-access"):
        """创建对话线程。"""
        params = {
            "model": model,
            "approvalPolicy": "never",
            # 注意: sandbox 必须用 kebab-case
            "sandbox": sandbox,
        }
        if cwd:
            params["cwd"] = cwd
        mid = self.send("thread/start", params)
        resp = self.wait_response(mid, timeout=15)
        if not resp or "error" in resp:
            raise RuntimeError(f"创建 thread 失败: {resp}")
        self.thread_id = resp["result"]["thread"]["id"]
        # 排空初始事件
        time.sleep(1)
        while not self.msg_queue.empty():
            try:
                self.msg_queue.get_nowait()
            except queue.Empty:
                break
        return self.thread_id

    def send_task(self, text, model="gpt-5.4", effort="medium", cwd=None):
        """发送一个任务 turn 并等待完成，返回 agent 文本和命令列表。"""
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
        resp = self.wait_response(mid, timeout=10)
        if resp and "error" in resp:
            raise RuntimeError(f"启动 turn 失败: {resp}")

        return self._collect_turn_events()

    def _collect_turn_events(self, timeout=180):
        """收集 turn 的所有事件，返回 (agent_text, commands)。"""
        agent_text = ""
        commands = []
        start = time.time()

        while time.time() - start < timeout:
            try:
                msg = self.msg_queue.get(timeout=3)
            except queue.Empty:
                if time.time() - start > 60 and not agent_text and not commands:
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

            # 命令开始
            elif method in ("codex/event/exec_command_begin",):
                cmd = params.get("command", "")
                if cmd:
                    print(f"\n  [命令] {cmd}")
                    commands.append(cmd)
            elif method == "item/started":
                item = params.get("item", {})
                cmd = item.get("command", "")
                if cmd:
                    print(f"\n  [命令] {cmd}")
                    commands.append(cmd)

            # 命令完成
            elif method in ("codex/event/exec_command_end",):
                ec = params.get("exitCode", "?")
                print(f"  [命令结束] exit={ec}")
            elif method == "item/completed":
                item = params.get("item", {})
                if item.get("type") == "commandExecution":
                    ec = item.get("exitCode", "?")
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
                            "turn/started"):
                pass

        return agent_text, commands

    def interrupt(self):
        """中断当前正在执行的 turn。"""
        if self.thread_id:
            self.send("turn/interrupt", {"threadId": self.thread_id})

    def list_models(self, limit=10):
        """获取可用模型列表。"""
        mid = self.send("model/list", {"limit": limit})
        resp = self.wait_response(mid, timeout=10)
        if resp and "result" in resp:
            return resp["result"]["data"]
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
            except Exception:
                self.proc.kill()


def run_single_task(args):
    """执行单次任务模式。"""
    bridge = CodexBridge()
    bridge.start()

    try:
        result = bridge.initialize()
        print(f"[初始化成功] {result.get('userAgent', '')}")

        thread_id = bridge.create_thread(
            model=args.model, cwd=args.cwd, sandbox=args.sandbox
        )
        print(f"[线程创建] {thread_id}")
        print(f"\n{'='*60}")
        print(f"[任务] {args.task}")
        print("=" * 60)

        agent_text, commands = bridge.send_task(
            args.task, model=args.model, effort=args.effort, cwd=args.cwd
        )

        print(f"\n\n{'='*60}")
        print(f"[统计] 执行了 {len(commands)} 条命令")
        print("=" * 60)

    finally:
        bridge.stop()

    return agent_text


def run_interactive(args):
    """交互式多轮对话模式。"""
    bridge = CodexBridge()
    bridge.start()

    try:
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

    finally:
        bridge.stop()
        print("[已退出]")


def main():
    parser = argparse.ArgumentParser(description="Codex App-Server Bridge")
    parser.add_argument("task", nargs="?", help="要执行的任务描述")
    parser.add_argument("--cwd", default=os.getcwd(), help="工作目录（默认当前目录）")
    parser.add_argument("--model", default="gpt-5.4", help="模型名称（默认 gpt-5.4）")
    parser.add_argument("--effort", default="medium",
                        choices=["low", "medium", "high", "xhigh"],
                        help="推理深度（默认 medium）")
    parser.add_argument("--sandbox", default="danger-full-access",
                        choices=["danger-full-access", "read-only", "workspace-write"],
                        help="沙箱策略（默认 danger-full-access）")
    parser.add_argument("--interactive", "-i", action="store_true",
                        help="进入交互式多轮对话模式")

    args = parser.parse_args()

    if args.interactive:
        run_interactive(args)
    elif args.task:
        run_single_task(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
