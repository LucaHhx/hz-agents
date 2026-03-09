---
name: redis-operator
description: Redis database operations skill for GVA projects. Use this skill whenever the user wants to explore, query, or manipulate the Redis cache defined in server/config.local.yaml. Trigger on phrases like "query redis", "check redis", "redis keys", "explore cache", "redis command", "cache operations", "check cache", "look at redis", "redis get", "redis set", or any request involving Redis data access in the project.
---

# Redis Operator

Execute Redis commands against the project Redis instance using the bundled script.

## Installation

The script requires one of the following (checked in order):

1. **Python redis library** (preferred): `pip install redis`
2. **redis-cli**: `brew install redis`

## Usage

The script is located in this skill's `scripts/` directory. Use the skill's base directory (provided as context when the skill triggers) to construct the path:

```bash
python3 <skill-base-dir>/scripts/redis_cli.py "<REDIS_COMMAND>"
```

The script auto-discovers the project root and reads `server/config.local.yaml` (falls back to `server/config.example.yaml`).

## Workflow

1. Run the command using the script
2. If connection fails, report the error and stop — do not retry
3. Present results clearly to the user

## Examples

```bash
# Key exploration
python3 <skill-base-dir>/scripts/redis_cli.py "KEYS *"
python3 <skill-base-dir>/scripts/redis_cli.py "SCAN 0 MATCH user:* COUNT 100"
python3 <skill-base-dir>/scripts/redis_cli.py "TYPE mykey"
python3 <skill-base-dir>/scripts/redis_cli.py "TTL mykey"
python3 <skill-base-dir>/scripts/redis_cli.py "DBSIZE"

# String operations
python3 <skill-base-dir>/scripts/redis_cli.py "GET mykey"
python3 <skill-base-dir>/scripts/redis_cli.py "SET mykey myvalue"
python3 <skill-base-dir>/scripts/redis_cli.py "MGET key1 key2 key3"

# Hash operations
python3 <skill-base-dir>/scripts/redis_cli.py "HGETALL myhash"
python3 <skill-base-dir>/scripts/redis_cli.py "HGET myhash field1"

# List operations
python3 <skill-base-dir>/scripts/redis_cli.py "LRANGE mylist 0 -1"
python3 <skill-base-dir>/scripts/redis_cli.py "LLEN mylist"

# Set operations
python3 <skill-base-dir>/scripts/redis_cli.py "SMEMBERS myset"

# Sorted set operations
python3 <skill-base-dir>/scripts/redis_cli.py "ZRANGE myzset 0 -1 WITHSCORES"

# Server info
python3 <skill-base-dir>/scripts/redis_cli.py "INFO server"
python3 <skill-base-dir>/scripts/redis_cli.py "INFO memory"
python3 <skill-base-dir>/scripts/redis_cli.py "INFO keyspace"
```

## Rules

- Use `KEYS *` only on small datasets; prefer `SCAN` for large databases
- For FLUSHDB, FLUSHALL, DEL (multiple keys): confirm with the user first
- Use double quotes to wrap the entire command, single quotes for string values inside
