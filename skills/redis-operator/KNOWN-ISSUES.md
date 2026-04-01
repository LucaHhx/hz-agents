# Redis Operator — 常见问题与解决方案

> 由 skill-doctor 维护，记录 AI 使用本 skill 时遇到的问题和解决方案。
> AI 使用本 skill 前应先阅读此文件，避免重复踩坑。

## [P001] [已修复] find_project_root() 从脚本位置查找失败

- **现象**: `Error: Cannot find project root (no server/ directory found)`，脚本位于 `~/.claude/skills/redis-operator/scripts/` 下，从该位置往上遍历永远找不到项目的 `server/` 目录
- **原因**: `find_project_root()` 只从 `__file__` 所在目录往上查找，但 skill 脚本不在项目目录树内
- **方案**: 修改 `find_project_root()` 增加搜索顺序：①`PROJECT_ROOT` 环境变量 → ②`cwd` 往上查找 → ③脚本位置往上查找。调用时只需在项目目录下执行即可
- **日期**: 2026-04-01
