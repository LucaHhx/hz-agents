---
description: "更新 hz-agents 框架并修复符号链接"
---

# 更新 HZ-Agents

拉取 hz-agents 最新代码，管理分支，并确保当前项目的符号链接正确指向。

## Implementation Steps

### 1. Fetch 并检查分支

```bash
cd "$HOME/.hz-agents" && git fetch origin
```

列出所有远程分支和当前分支：

```bash
CURRENT=$(git branch --show-current)
echo "当前分支: $CURRENT"
git branch -r --format='%(refname:short)' | sed 's|origin/||'
```

向用户展示：
- 当前使用的分支
- 所有可用的远程分支列表
- 询问用户：是否要切换分支？默认保持当前分支

如果用户选择切换分支：

```bash
git checkout "$TARGET_BRANCH" && git pull
```

如果用户保持当前分支：

```bash
git pull
```

如果 pull 失败（本地有修改），提示用户处理冲突。

### 2. 检测配置目录

自动检测当前项目使用的配置目录：

```bash
CONFIG_DIR=""
for dir in .claude .codex .cursor; do
  if [ -d "$dir" ]; then CONFIG_DIR="$dir"; break; fi
done
```

如果未找到配置目录，询问用户使用哪个工具（Claude Code / Codex / Cursor）。

### 3. 验证符号链接

检查三个链接是否存在且指向正确：

```bash
for target in agents commands skills; do
  link="$CONFIG_DIR/$target"
  expected="$HOME/.hz-agents/$target"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$expected" ]; then
    echo "✓ $link → $expected"
  else
    echo "✗ $link 需要修复"
  fi
done
```

### 4. 修复损坏或缺失的链接

对于不正确的链接，重新创建：

```bash
rm -rf "$CONFIG_DIR/$target"
ln -s "$HOME/.hz-agents/$target" "$CONFIG_DIR/$target"
```

### 5. 汇报结果

向用户展示：
- 当前使用的分支
- git pull 的更新内容（新增/修改的文件摘要）
- 符号链接状态（全部正常 / 已修复）
- 提示：更新对所有链接了 hz-agents 的项目自动生效
