#!/usr/bin/env python3
"""
Redis CLI Script for GVA projects.
Reads Redis config from server/config.local.yaml and executes Redis commands.
"""

import sys
import os
import re
import subprocess
import argparse

try:
    import redis as redis_lib
    HAS_REDIS_PY = True
except ImportError:
    HAS_REDIS_PY = False


def find_project_root():
    """Find the project root by looking for server/ directory.

    Search order:
    1. PROJECT_ROOT environment variable (if set)
    2. Current working directory, then walk up
    3. Script location, then walk up (original behavior)
    """
    # 1. Env var override
    env_root = os.environ.get('PROJECT_ROOT')
    if env_root and os.path.isdir(os.path.join(env_root, 'server')):
        return env_root

    # 2. Search from cwd upwards, then from script location
    for start in [os.getcwd(), os.path.dirname(os.path.abspath(__file__))]:
        current = start
        for _ in range(10):
            if os.path.isdir(os.path.join(current, 'server')):
                return current
            parent = os.path.dirname(current)
            if parent == current:
                break
            current = parent

    return None


def parse_yaml_redis_config(config_path):
    """Simple YAML parser to extract Redis config."""
    if not os.path.exists(config_path):
        return None

    config = {
        'host': '127.0.0.1',
        'port': 6379,
        'password': '',
        'db': 0,
    }

    with open(config_path, 'r') as f:
        lines = f.read().split('\n')

    in_redis = False
    for line in lines:
        if re.match(r'^redis:\s*$', line):
            in_redis = True
            continue
        if in_redis:
            if re.match(r'^[a-z]', line):
                break
            match = re.match(r'\s+(\S+):\s*(.+?)\s*$', line)
            if match:
                key, value = match.groups()
                value = value.strip('"').strip("'")
                if key == 'addr':
                    # addr format: host:port
                    parts = value.rsplit(':', 1)
                    config['host'] = parts[0]
                    if len(parts) > 1:
                        config['port'] = int(parts[1])
                elif key == 'password':
                    config['password'] = value
                elif key == 'db':
                    config['db'] = int(value)

    return config


def format_result(result):
    """Format Redis result for display."""
    if result is None:
        print("(nil)")
    elif isinstance(result, bytes):
        print(result.decode('utf-8', errors='replace'))
    elif isinstance(result, list):
        if not result:
            print("(empty list)")
            return
        for i, item in enumerate(result):
            if isinstance(item, bytes):
                item = item.decode('utf-8', errors='replace')
            print(f"{i + 1}) {item}")
        print(f"\nTotal items: {len(result)}")
    elif isinstance(result, set):
        for i, item in enumerate(sorted(result)):
            if isinstance(item, bytes):
                item = item.decode('utf-8', errors='replace')
            print(f"{i + 1}) {item}")
        print(f"\nTotal items: {len(result)}")
    elif isinstance(result, dict):
        if not result:
            print("(empty dict)")
            return
        max_key_len = max(len(str(k)) for k in result.keys())
        for k, v in result.items():
            if isinstance(k, bytes):
                k = k.decode('utf-8', errors='replace')
            if isinstance(v, bytes):
                v = v.decode('utf-8', errors='replace')
            print(f"{str(k).ljust(max_key_len)}  {v}")
    elif isinstance(result, int):
        print(f"(integer) {result}")
    elif isinstance(result, bool):
        print("OK" if result else "FAIL")
    else:
        print(result)


def execute_with_redis_py(config, command_parts):
    """Execute command using redis-py library."""
    try:
        r = redis_lib.Redis(
            host=config['host'],
            port=config['port'],
            password=config['password'] or None,
            db=config['db'],
            socket_timeout=5,
            socket_connect_timeout=5,
        )
        # Use execute_command to support any Redis command
        result = r.execute_command(*command_parts)
        r.close()
        return 0, result, None
    except redis_lib.ConnectionError as e:
        return 1, None, f"Connection failed: {e}"
    except redis_lib.RedisError as e:
        return 1, None, f"Command failed: {e}"
    except Exception as e:
        return 1, None, f"Error: {e}"


def execute_with_redis_cli(config, command_parts):
    """Execute command using redis-cli."""
    cmd = [
        'redis-cli',
        '-h', config['host'],
        '-p', str(config['port']),
        '-n', str(config['db']),
    ]
    if config.get('password'):
        cmd.extend(['-a', config['password']])

    cmd.extend(command_parts)

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        return 0, result.stdout, None
    else:
        return result.returncode, None, result.stderr


def parse_command(command_str):
    """Parse a Redis command string into parts, respecting quotes."""
    parts = []
    current = []
    in_quote = None
    for char in command_str:
        if char in ('"', "'") and in_quote is None:
            in_quote = char
        elif char == in_quote:
            in_quote = None
        elif char == ' ' and in_quote is None:
            if current:
                parts.append(''.join(current))
                current = []
        else:
            current.append(char)
    if current:
        parts.append(''.join(current))
    return parts


def execute_command(config, command_str, verbose=False):
    """Execute Redis command using available method."""
    command_parts = parse_command(command_str)
    if not command_parts:
        print("Error: Empty command", file=sys.stderr)
        return 1

    if verbose:
        print(f"Command: {command_parts}", file=sys.stderr)

    if HAS_REDIS_PY:
        returncode, result, error = execute_with_redis_py(config, command_parts)
        if returncode == 0:
            format_result(result)
            return 0
        else:
            print(f"Error: {error}", file=sys.stderr)
            return 1

    try:
        returncode, result, error = execute_with_redis_cli(config, command_parts)
        if returncode == 0:
            print(result, end='')
            return 0
        else:
            print(f"Error: {error}", file=sys.stderr)
            return 1
    except FileNotFoundError:
        print("Error: No Redis client available.", file=sys.stderr)
        print("Install one of: pip install redis | brew install redis", file=sys.stderr)
        return 1


def main():
    parser = argparse.ArgumentParser(description='Execute Redis commands for GVA project')
    parser.add_argument('command', nargs='?', help='Redis command to execute')
    parser.add_argument('-c', '--config', help='Path to config file')
    parser.add_argument('-v', '--verbose', action='store_true')

    args = parser.parse_args()

    if not args.command and sys.stdin.isatty():
        parser.print_help()
        sys.exit(1)

    command = args.command or sys.stdin.read().strip()
    if not command:
        print("Error: Empty command", file=sys.stderr)
        sys.exit(1)

    # Resolve config path
    if args.config:
        config_path = args.config
    else:
        project_root = find_project_root()
        if not project_root:
            print("Error: Cannot find project root (no server/ directory found)", file=sys.stderr)
            sys.exit(1)
        config_path = os.path.join(project_root, 'server', 'config.local.yaml')
        if not os.path.exists(config_path):
            config_path = os.path.join(project_root, 'server', 'config.example.yaml')

    if args.verbose:
        print(f"Config: {config_path}", file=sys.stderr)
        print(f"redis-py: {HAS_REDIS_PY}", file=sys.stderr)

    redis_config = parse_yaml_redis_config(config_path)
    if redis_config is None:
        print(f"Error: Cannot read config from {config_path}", file=sys.stderr)
        sys.exit(1)

    if args.verbose:
        print(f"Connecting to {redis_config['host']}:{redis_config['port']}/{redis_config['db']}", file=sys.stderr)

    sys.exit(execute_command(redis_config, command, args.verbose))


if __name__ == '__main__':
    main()
