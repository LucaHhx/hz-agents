#!/bin/bash
# Agent File Validator (v0.2.0)
# Validates agent markdown files for correct structure and content
# Aligned with official Claude Code documentation:
# https://code.claude.com/docs/en/sub-agents

set -uo pipefail

# Usage
if [ $# -eq 0 ]; then
  echo "Usage: $0 <path/to/agent.md>"
  echo ""
  echo "Validates agent file for:"
  echo "  - YAML frontmatter structure"
  echo "  - Required fields (name, description)"
  echo "  - Optional fields format (model, tools, permissionMode, etc.)"
  echo "  - Tools format (comma-separated string, NOT array)"
  echo "  - System prompt presence and length"
  echo "  - Example blocks in description"
  exit 1
fi

AGENT_FILE="$1"

echo "Validating agent file: $AGENT_FILE"
echo ""

# Check 1: File exists
if [ ! -f "$AGENT_FILE" ]; then
  echo "FAIL: File not found: $AGENT_FILE"
  exit 1
fi
echo "PASS: File exists"

# Check 2: Starts with ---
FIRST_LINE=$(head -1 "$AGENT_FILE")
if [ "$FIRST_LINE" != "---" ]; then
  echo "FAIL: File must start with YAML frontmatter (---)"
  exit 1
fi
echo "PASS: Starts with frontmatter"

# Check 3: Has closing ---
if ! tail -n +2 "$AGENT_FILE" | grep -q '^---$'; then
  echo "FAIL: Frontmatter not closed (missing second ---)"
  exit 1
fi
echo "PASS: Frontmatter properly closed"

# Extract frontmatter and system prompt
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$AGENT_FILE")
SYSTEM_PROMPT=$(awk '/^---$/{i++; next} i>=2' "$AGENT_FILE")

# Helper: extract field value from frontmatter (returns empty if not found)
get_field() {
  echo "$FRONTMATTER" | grep "^${1}:" | sed "s/${1}: *//" | sed 's/^"\(.*\)"$/\1/' || true
}

# Check 4: Required fields
echo ""
echo "Checking required fields..."

error_count=0
warning_count=0

# Check name field
NAME=$(get_field "name")

if [ -z "$NAME" ]; then
  echo "FAIL: Missing required field: name"
  ((error_count++))
else
  echo "PASS: name: $NAME"

  # Validate name format
  if ! [[ "$NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]]; then
    echo "FAIL: name must start/end with alphanumeric and contain only letters, numbers, hyphens"
    ((error_count++))
  fi

  # Validate name length
  name_length=${#NAME}
  if [ $name_length -lt 3 ]; then
    echo "FAIL: name too short (minimum 3 characters)"
    ((error_count++))
  elif [ $name_length -gt 50 ]; then
    echo "FAIL: name too long (maximum 50 characters)"
    ((error_count++))
  fi

  # Check for generic names
  if [[ "$NAME" =~ ^(helper|assistant|agent|tool)$ ]]; then
    echo "WARN: name is too generic: $NAME"
    ((warning_count++))
  fi
fi

# Check description field (handles multiline YAML with |)
DESC_FIRST_LINE=$(get_field "description")

if [ -z "$DESC_FIRST_LINE" ]; then
  echo "FAIL: Missing required field: description"
  ((error_count++))
else
  # For multiline descriptions, extract full content
  DESCRIPTION=$(awk '/^description:/{found=1; sub(/^description: */, ""); if($0 == "|" || $0 == ">") {next} else {print; next}} found && /^[a-zA-Z]/{found=0} found{print}' <<< "$FRONTMATTER")
  if [ -z "$DESCRIPTION" ]; then
    DESCRIPTION="$DESC_FIRST_LINE"
  fi
  desc_length=${#DESCRIPTION}
  echo "PASS: description: ${desc_length} characters"

  if [ $desc_length -lt 10 ]; then
    echo "WARN: description too short (minimum 10 characters recommended)"
    ((warning_count++))
  elif [ $desc_length -gt 5000 ]; then
    echo "WARN: description very long (over 5000 characters)"
    ((warning_count++))
  fi

  # Check for example blocks (optional, INFO only)
  if ! echo "$FRONTMATTER" | grep -q '<example>'; then
    echo "INFO: description has no <example> blocks (optional but helps triggering)"
  fi
fi

# Check 5: Optional fields validation
echo ""
echo "Checking optional fields..."

# Check model field (optional, defaults to inherit)
MODEL=$(get_field "model")

if [ -n "$MODEL" ]; then
  echo "INFO: model: $MODEL"
  case "$MODEL" in
    inherit|sonnet|opus|haiku) ;;
    claude-*) echo "INFO: Using full model ID" ;;
    *)
      echo "WARN: Unknown model: $MODEL (valid aliases: inherit, sonnet, opus, haiku; or full model ID)"
      ((warning_count++))
      ;;
  esac
else
  echo "INFO: model: not specified (defaults to inherit)"
fi

# Check color field (optional, UI only)
COLOR=$(get_field "color")

if [ -n "$COLOR" ]; then
  echo "INFO: color: $COLOR"
  case "$COLOR" in
    blue|cyan|green|yellow|magenta|red) ;;
    *)
      echo "WARN: Unknown color: $COLOR (valid: blue, cyan, green, yellow, magenta, red)"
      ((warning_count++))
      ;;
  esac
else
  echo "INFO: color: not specified"
fi

# Check tools field format (should be comma-separated string, NOT array)
TOOLS_LINE=$(get_field "tools")

if [ -n "$TOOLS_LINE" ]; then
  echo "INFO: tools: $TOOLS_LINE"
  if echo "$TOOLS_LINE" | grep -q '^\['; then
    echo "WARN: tools should be comma-separated string, not YAML array. Use: tools: Read, Write, Grep"
    ((warning_count++))
  fi
else
  echo "INFO: tools: not specified (agent has access to all tools)"
fi

# Check permissionMode field
PERM_MODE=$(get_field "permissionMode")

if [ -n "$PERM_MODE" ]; then
  echo "INFO: permissionMode: $PERM_MODE"
  case "$PERM_MODE" in
    default|acceptEdits|dontAsk|bypassPermissions|plan) ;;
    *)
      echo "WARN: Unknown permissionMode: $PERM_MODE (valid: default, acceptEdits, dontAsk, bypassPermissions, plan)"
      ((warning_count++))
      ;;
  esac
fi

# Check for skills field
if echo "$FRONTMATTER" | grep -q '^skills:'; then
  echo "INFO: skills: defined"
fi

# Check for memory field
MEMORY=$(get_field "memory")
if [ -n "$MEMORY" ]; then
  echo "INFO: memory: $MEMORY"
  case "$MEMORY" in
    user|project|local) ;;
    *)
      echo "WARN: Unknown memory scope: $MEMORY (valid: user, project, local)"
      ((warning_count++))
      ;;
  esac
fi

# Check 6: System prompt
echo ""
echo "Checking system prompt..."

if [ -z "$SYSTEM_PROMPT" ]; then
  echo "FAIL: System prompt is empty"
  ((error_count++))
else
  prompt_length=${#SYSTEM_PROMPT}
  echo "PASS: System prompt: $prompt_length characters"

  if [ $prompt_length -lt 20 ]; then
    echo "FAIL: System prompt too short (minimum 20 characters)"
    ((error_count++))
  elif [ $prompt_length -gt 10000 ]; then
    echo "WARN: System prompt very long (over 10,000 characters)"
    ((warning_count++))
  fi

  # Check for second person
  if ! echo "$SYSTEM_PROMPT" | grep -q "You are\|You will\|Your"; then
    echo "WARN: System prompt should use second person (You are..., You will...)"
    ((warning_count++))
  fi

  # Check for structure
  if ! echo "$SYSTEM_PROMPT" | grep -qi "responsibilities\|process\|steps\|workflow"; then
    echo "INFO: Consider adding clear responsibilities or process steps"
  fi

  if ! echo "$SYSTEM_PROMPT" | grep -qi "output"; then
    echo "INFO: Consider defining output format expectations"
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $error_count -eq 0 ] && [ $warning_count -eq 0 ]; then
  echo "PASS: All checks passed!"
  exit 0
elif [ $error_count -eq 0 ]; then
  echo "PASS: Validation passed with $warning_count warning(s)"
  exit 0
else
  echo "FAIL: Validation failed with $error_count error(s) and $warning_count warning(s)"
  exit 1
fi
