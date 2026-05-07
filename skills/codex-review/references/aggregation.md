# 多 agent 审查结果汇总规范

并行 N 个 codex agent 跑完后，每个 agent 会给出一段 markdown 文本（`agent_message`）。这里规定怎么把它们合并成最终给用户的报告。

## 输入

每个 agent 输出形如：

```
🔴 must-fix
- server/api/v1/foo.go:42 — 直接拼 SQL，存在注入 — 改成参数化查询

🟡 should-fix
- server/service/bar.go:88 — 函数 200+ 行，建议拆分 — 抽 useXxx 子函数

🟢 nice-to-have
- web/src/view/baz.vue:12 — 变量名 `tmp` 不清晰 — 重命名为 `pendingOrders`
```

或自由文本（codex 偶尔不严格遵守格式）。

## 处理步骤

1. **解析每条结论**：尽量提取出 `(severity, file, line, description, suggestion)` 五元组。无法解析的整段保留为 raw。
2. **去重**：以 `(file, line, 描述前 30 字符)` 做近似去重；如果两条文字略不同但指向同一处，保留信息更完整的那条，并在末尾标注 `— 由 N 个 agent 共同提到`。
3. **合并严重度冲突**：如果两个 agent 对同一处给出不同严重度，取**更高**的那个（must > should > nice）。
4. **按严重度分桶输出**，每桶内按 `file → line` 排序。
5. **附加元信息**：报告头部写明 `并行 agent 数：N`、`审查目标：<未提交 / branch A..B / 路径 X>`、`生成时间`。
6. **裁剪**：如果 must-fix 超过 20 条，只保留前 20 条，剩下的概括成"还有 N 条 must-fix，建议先修以上后再回审"。

## 输出模板

```markdown
# Codex 并行审查报告

**审查目标**：{{target}}
**并行 agent 数**：{{N}}
**生成时间**：{{ISO8601}}

## 🔴 must-fix（{{count}}）
- `path/to/file.go:42` — 描述 — 修复建议  _(N agents)_
- ...

## 🟡 should-fix（{{count}}）
- ...

## 🟢 nice-to-have（{{count}}）
- ...

## 未结构化的补充观察
（无法解析进上述三类的原文摘录，原样保留）
```

## 何时跳过去重

如果用户要求"原样并列展示"，不做合并，直接以 `## Agent 1` / `## Agent 2` / `## Agent 3` 三段并列输出每个 agent 的原始文本即可。这种模式下不要"挑选最优答案"——把判断留给用户。
