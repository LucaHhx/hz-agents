# Project v2 状态切换通用流程（共享）

供 [info.md](info.md) Step 3 / [fix.md](fix.md) Step 5 共用。

**前置**：token 必须含 `read:project` + `project` scope。
缺权限时让用户跑 `gh auth refresh -s read:project,project`，本步跳过但其它步骤继续（不要因为状态切换失败 abort 整个子命令）。

## Step A — 拿 issue 关联的所有 project items

```bash
gh api graphql -f query="
{
  repository(owner: \"$OWNER\", name: \"$REPO\") {
    issue(number: $ID) {
      projectItems(first: 5) {
        nodes {
          id
          project { id title number }
          fieldValues(first: 30) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                field { ... on ProjectV2SingleSelectField { id name options { id name } } }
                name
                optionId
              }
            }
          }
        }
      }
    }
  }
}"
```

返回 `INSUFFICIENT_SCOPES` → 提示用户 `gh auth refresh -s read:project,project`，**跳过状态切换**继续后续步骤。

`projectItems.nodes` 为空 → 告诉用户"该 issue 未关联任何 Project，跳过状态切换"。

## Step B — 在每个 project item 里找 "Status" 字段

遍历 `fieldValues.nodes`，挑 `field.name == "Status"`（兼容 `"状态"` 字符串）。

记下：
- `$PROJECT_ID` — project.id
- `$PROJECT_TITLE` — project.title
- `$ITEM_ID` — projectItem.id
- `$STATUS_FIELD_ID` — field.id
- `$STATUS_OPTIONS` — field.options 数组

## Step C — 在 field.options 里按目标名字匹配 option

按"包含匹配"找 option（不区分大小写）。例如目标 "修复中"，关键词 `["修复中", "进行中", "in progress", "doing", "working"]`：

```python
target_keywords = [...]   # 调用方传入
match = next(
  (o for o in options
   if any(k.lower() in o["name"].lower() for k in target_keywords)),
  None
)
```

**匹配不到** → 列出全部 option name 让用户挑：

> Project "<title>" 没有匹配 <target_keywords> 的 status 选项。
> 当前选项：[待修复, In Progress, ...]，要切到哪个？

## Step D — mutation 更新

```bash
gh api graphql -f query="
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: \"$PROJECT_ID\",
    itemId: \"$ITEM_ID\",
    fieldId: \"$STATUS_FIELD_ID\",
    value: { singleSelectOptionId: \"$OPTION_ID\" }
  }) { projectV2Item { id } }
}"
```

成功后告诉用户："Project '<title>' 状态切到 '<option name>'"。

## 多 Project 关联

一个 issue 可能关联多个 Project（罕见但有可能）。对每个 Project 都执行 Step B/C/D，每条 mutation 独立跑。

## OWNER / REPO / ID 取值

- `$OWNER` `$REPO`：从 cwd 推断，最简单的命令是 `gh repo view --json owner,name --jq '.owner.login, .name'`，或拆 `git remote get-url origin`
- `$ID`：调用方传入的 issue 编号
