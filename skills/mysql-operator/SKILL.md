---
name: mysql-operator
description: MySQL database operations skill for GVA projects. Use this skill whenever the user wants to explore, query, or manipulate the MySQL database defined in server/config.local.yaml. Trigger on phrases like "query database", "check mysql", "show tables", "explore database", "sql query", "database operations", "check data", "look at database", or any request involving MySQL/MariaDB data access in the project.
---

# MySQL Operator

Execute MySQL queries against the project database using the bundled script.

## Usage

The query script is located in this skill's `scripts/` directory. Use the skill's base directory (provided as context when the skill triggers) to construct the path:

```bash
python3 <skill-base-dir>/scripts/mysql_query.py "<SQL>"
```

The script auto-discovers the project root and reads `server/config.local.yaml` (falls back to `server/config.example.yaml`).

## Workflow

1. Run the query using the script
2. If connection fails, report the error and stop — do not retry
3. Present results to the user in markdown table format

## Examples

```bash
python3 <skill-base-dir>/scripts/mysql_query.py "SHOW TABLES"
python3 <skill-base-dir>/scripts/mysql_query.py "DESCRIBE sys_users"
python3 <skill-base-dir>/scripts/mysql_query.py "SELECT * FROM sys_users LIMIT 10"
python3 <skill-base-dir>/scripts/mysql_query.py "SELECT COUNT(*) as total FROM sys_users"
```

## Rules

- Always use `LIMIT` for SELECT on large tables
- For UPDATE, DELETE, DROP, TRUNCATE: confirm with the user first
- Use single quotes for SQL string values
