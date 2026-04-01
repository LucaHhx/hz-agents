#!/usr/bin/env python3
"""
MySQL Query Script for GVA projects.
Reads database config from server/config.local.yaml and executes SQL queries.
"""

import sys
import os
import re
import subprocess
import argparse

try:
    import pymysql
    HAS_PYMYSQL = True
except ImportError:
    HAS_PYMYSQL = False


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

    # 2. Search from cwd upwards (handles `cd /project && python3 script.py`)
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


def parse_yaml_mysql_config(config_path):
    """Simple YAML parser to extract MySQL config."""
    if not os.path.exists(config_path):
        return None

    config = {
        'host': 'localhost',
        'port': 3306,
        'user': 'root',
        'password': '',
        'database': '',
    }

    with open(config_path, 'r') as f:
        lines = f.read().split('\n')

    in_mysql = False
    for line in lines:
        if re.match(r'^mysql:\s*$', line):
            in_mysql = True
            continue
        if in_mysql:
            if re.match(r'^[a-z]', line):
                break
            match = re.match(r'\s+(\S+):\s*(.+?)\s*$', line)
            if match:
                key, value = match.groups()
                value = value.strip('"').strip("'")
                if key == 'path':
                    config['host'] = value
                elif key == 'port':
                    config['port'] = int(value)
                elif key == 'username':
                    config['user'] = value
                elif key == 'password':
                    config['password'] = value
                elif key == 'db-name':
                    config['database'] = value

    return config


def format_table(results):
    """Format query results as a markdown table."""
    if not results:
        print("Empty result set")
        return

    if isinstance(results[0], dict):
        columns = list(results[0].keys())
        rows = results
    else:
        columns = results[0]._fields if hasattr(results[0], '_fields') else []
        rows = [dict(zip(columns, row)) for row in results]

    if not columns:
        print(results)
        return

    col_widths = {col: len(str(col)) for col in columns}
    for row in rows:
        for col in columns:
            col_widths[col] = max(col_widths[col], len(str(row.get(col, ''))))

    header = "| " + " | ".join(str(col).ljust(col_widths[col]) for col in columns) + " |"
    separator = "|-" + "-|-".join("-" * col_widths[col] for col in columns) + "-|"
    print(header)
    print(separator)

    for row in rows:
        row_str = "| " + " | ".join(str(row.get(col, '')).ljust(col_widths[col]) for col in columns) + " |"
        print(row_str)

    print(f"\nTotal rows: {len(rows)}")


def execute_with_pymysql(config, query):
    """Execute query using PyMySQL."""
    try:
        connection = pymysql.connect(
            host=config['host'],
            port=config['port'],
            user=config['user'],
            password=config['password'],
            database=config['database'],
            charset='utf8mb4',
            cursorclass=pymysql.cursors.DictCursor
        )
        with connection.cursor() as cursor:
            cursor.execute(query)
            if cursor.description:
                result = cursor.fetchall()
            else:
                connection.commit()
                result = [{'affected_rows': cursor.rowcount}]
        connection.close()
        return 0, result, None
    except pymysql.err.OperationalError as e:
        return 1, None, f"Connection failed: {e.args[1]} (Code: {e.args[0]})"
    except pymysql.err.MySQLError as e:
        return 1, None, f"Query failed: {e}"
    except Exception as e:
        return 1, None, f"Error: {e}"


def execute_with_mysql_client(config, query):
    """Execute query using mysql command-line client."""
    cmd = [
        'mysql',
        f'-h{config["host"]}',
        f'-P{config["port"]}',
        f'-u{config["user"]}',
    ]
    if config.get('password'):
        cmd.append(f'-p{config["password"]}')
    cmd.append(config['database'])
    cmd.extend(['-e', query])

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        return 0, result.stdout, None
    else:
        return result.returncode, None, result.stderr


def execute_query(config, query):
    """Execute SQL query using available method."""
    if HAS_PYMYSQL:
        returncode, result, error = execute_with_pymysql(config, query)
        if returncode == 0:
            format_table(result)
            return 0
        else:
            print(f"Error: {error}", file=sys.stderr)
            return 1

    try:
        returncode, result, error = execute_with_mysql_client(config, query)
        if returncode == 0:
            print(result, end='')
            return 0
        else:
            print(f"Error: {error}", file=sys.stderr)
            return 1
    except FileNotFoundError:
        print("Error: No MySQL client available.", file=sys.stderr)
        print("Install one of: pip install pymysql | brew install mysql-client", file=sys.stderr)
        return 1


def main():
    parser = argparse.ArgumentParser(description='Execute MySQL queries for GVA project')
    parser.add_argument('query', nargs='?', help='SQL query to execute')
    parser.add_argument('-c', '--config', help='Path to config file')
    parser.add_argument('-v', '--verbose', action='store_true')

    args = parser.parse_args()

    if not args.query and sys.stdin.isatty():
        parser.print_help()
        sys.exit(1)

    query = args.query or sys.stdin.read().strip()
    if not query:
        print("Error: Empty query", file=sys.stderr)
        sys.exit(1)

    # Resolve config path
    if args.config:
        config_path = args.config
    else:
        project_root = find_project_root()
        if not project_root:
            print("Error: Cannot find project root (no server/ directory found)", file=sys.stderr)
            sys.exit(1)
        # Try config.local.yaml first, fall back to config.example.yaml
        config_path = os.path.join(project_root, 'server', 'config.local.yaml')
        if not os.path.exists(config_path):
            config_path = os.path.join(project_root, 'server', 'config.example.yaml')

    if args.verbose:
        print(f"Config: {config_path}", file=sys.stderr)
        print(f"PyMySQL: {HAS_PYMYSQL}", file=sys.stderr)

    mysql_config = parse_yaml_mysql_config(config_path)
    if mysql_config is None:
        print(f"Error: Cannot read config from {config_path}", file=sys.stderr)
        sys.exit(1)

    if args.verbose:
        print(f"Connecting to {mysql_config['host']}:{mysql_config['port']}/{mysql_config['database']}", file=sys.stderr)

    sys.exit(execute_query(mysql_config, query))


if __name__ == '__main__':
    main()
