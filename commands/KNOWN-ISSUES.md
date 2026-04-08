# commit 命令 — 常见问题与解决方案

> 由 skill-doctor 维护，记录 AI 使用本 skill 时遇到的问题和解决方案。
> AI 使用本 skill 前应先阅读此文件，避免重复踩坑。

## [P001] untracked 的客户端资源目录被遗漏

- **现象**: `git status` 显示 `client/` 下有大量 untracked 文件（字体、翻译、游戏客户端、主题、音效等），但提交计划中完全没有包含这些文件
- **原因**: 分类逻辑只关注 `server/` 下的代码变更，忽略了非代码的静态资源目录
- **方案**: Step 3 分类时必须扫描所有 untracked 文件（包括 `client/`、`assets/` 等资源目录），将其纳入提交计划，通常归类为 `chore(client): 更新客户端资源` 独立 commit
- **日期**: 2026-04-08
