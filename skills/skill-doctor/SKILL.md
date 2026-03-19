---
name: skill-doctor
description: |
  Skill 问题诊断与知识沉淀工具。当 AI 使用某个 skill 遇到问题并自行解决后，
  自动定位该 skill 的主目录，在其下创建/追加 KNOWN-ISSUES.md 记录常见错误与解决方案，
  同时在 skill-doctor/logs/ 下记录修改日志。防止 AI 反复踩同一个坑。
  触发场景：
  (1) 使用 skill 遇到错误并解决后，记录到目标 skill 目录
      (triggers: '记录问题', '记录错误', 'log issue', 'skill问题', 'skill error',
       'skill-doctor', '沉淀经验', '记录解决方案')
  (2) 修改/优化 skill 后记录修改日志
      (triggers: '记录修改', 'log fix', 'skill修改记录', 'skill change log')
  (3) 使用 skill 前查阅该 skill 的已知问题
      (triggers: '查看已知问题', 'check known issues', '有什么坑', '避坑指南',
       'skill注意事项', '查看skill问题')
  (4) 批量审查所有 skill 的健康状况
      (triggers: 'skill健康检查', 'skill health check', '审查所有skill')
---

# Skill Doctor — Skill 问题诊断与知识沉淀

## 强制规则（MANDATORY）

**所有 agent 必须遵守以下规则，无例外：**

1. **使用前必查**：使用任何 skill 之前，必须先 Glob 检查该 skill 目录下是否有 `KNOWN-ISSUES.md`，存在则必须阅读
2. **解决后必记**：使用 skill 过程中遇到错误并自行解决后，必须立即将问题和方案记录到该 skill 的 `KNOWN-ISSUES.md`
3. **修改后必记**：修改任何 skill 的代码/配置后，必须在 `skill-doctor/logs/YYYY-MM.md` 中追加日志

## 核心目标

解决 AI 使用 skill 时的「失忆循环」：遇到问题 → 自行解决 → 下次又遇到同样问题 → 又从头解决。
通过在**目标 skill 自身目录**下维护 `KNOWN-ISSUES.md`，让 AI 每次加载 skill 时自动感知已知问题。

## 关键设计

- `KNOWN-ISSUES.md` 放在目标 skill 的主目录下（与 SKILL.md 同级）
- 修改日志集中在 `skill-doctor/logs/YYYY-MM.md`
- AI 使用任何 skill 前，**必须**先检查该 skill 目录下是否有 `KNOWN-ISSUES.md`

## 定位目标 Skill 目录

按以下优先级查找目标 skill 主目录：

1. 在 `skills/` 目录下查找：`skills/{skill-name}/SKILL.md`
2. 在 `.claude/skills/` 下查找：`.claude/skills/{skill-name}/SKILL.md`
3. 用 Glob 搜索：`**/skills/{skill-name}/SKILL.md`

找到 `SKILL.md` 所在目录即为该 skill 的主目录。

## 工作流

### 1. 记录问题和解决方案（最常用）

当使用某个 skill 遇到错误并解决后：

1. **定位目标 skill 主目录**（按上述规则）
2. 读取该目录下的 `KNOWN-ISSUES.md`（不存在则按模板创建）
3. 检查是否已有相同问题记录，避免重复
4. 用下一个编号追加新条目
5. 在 `skill-doctor/logs/YYYY-MM.md` 追加修改日志

**KNOWN-ISSUES.md 模板**（放在目标 skill 主目录下）：

```markdown
# {Skill Name} — 常见问题与解决方案

> 由 skill-doctor 维护，记录 AI 使用本 skill 时遇到的问题和解决方案。
> AI 使用本 skill 前应先阅读此文件，避免重复踩坑。

## [P001] {问题简述}

- **现象**: 具体错误表现、错误信息
- **原因**: 根因分析
- **方案**: 具体解决步骤
- **日期**: YYYY-MM-DD
```

**日志模板** (`skill-doctor/logs/YYYY-MM.md`)：

```markdown
# YYYY-MM 修改日志

| 日期 | 目标 Skill | 操作类型 | 问题编号 | 描述 |
|------|-----------|---------|---------|------|
| MM-DD | skill-name | 新增问题 | P001 | 简述 |
```

### 2. 修改 Skill 后记录

修改/优化某个 skill 代码后：

1. 如果修改是因为已知问题，在目标 skill 的 `KNOWN-ISSUES.md` 中将对应条目标记 `[已修复]`
2. 在 `skill-doctor/logs/YYYY-MM.md` 追加，操作类型标记「修改skill」
3. 简述修改内容和解决的问题

### 3. 使用 Skill 前查阅

在使用某 skill 前：

1. 定位该 skill 主目录
2. 检查是否存在 `KNOWN-ISSUES.md`
3. 存在则阅读，提前规避已知问题
4. 不存在则正常使用

### 4. 批量健康检查

1. 扫描所有 skill 目录，查找包含 `KNOWN-ISSUES.md` 的 skill
2. 统计每个 skill 的问题数量（总数/未解决/已修复）
3. 识别高频问题模式
4. 输出健康报告

## 编号与状态规则

- 每个 skill 独立编号：P001, P002, P003...
- 编号只增不减
- 已修复的问题在标题加 `[已修复]`，如：`## [P001] [已修复] 路径错误`

## 操作类型

| 类型 | 说明 |
|------|------|
| 新增问题 | 首次发现并记录到目标 skill 的 KNOWN-ISSUES.md |
| 更新方案 | 补充或更正已有问题的解决方案 |
| 修改skill | 修改了目标 skill 的代码/配置 |
| 标记修复 | 问题已通过 skill 更新永久修复 |

## 重要约定

- **问题描述要具体**：包含实际错误信息、堆栈关键行，方便后续搜索匹配
- **方案要可操作**：写清楚具体步骤，不要笼统描述
- **文件位置**：KNOWN-ISSUES.md 必须放在目标 skill 主目录下（与 SKILL.md 同级）
- **AI 自查**：使用任何 skill 时，先 Glob 检查 `{skill-dir}/KNOWN-ISSUES.md` 是否存在
