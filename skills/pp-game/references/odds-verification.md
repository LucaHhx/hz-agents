# 赔率验证方法

## 目标

验证 gameresult 中的赔率数据是否可直接用于结算，或需要自主计算。

## 方法一：HAR 多轮数据交叉验证

从 HAR 中提取所有 gameresult，收集每个 betCode 出现在哪些 winNumber 上：

```python
# 伪代码
bc_to_wins = {}  # bc → set of win numbers
for each gameresult:
    score = gameresult.score
    for bc, payout in gameresult.bXX_payouts:
        bc_to_wins[bc].add(score)

# 对比我方 odds.go 的 betCode → 号码映射
for bc in bc_to_wins:
    expected = roulette_bet_code_numbers(bc)
    actual = bc_to_wins[bc] & all_win_numbers
    if expected != actual:
        print(f"bc{bc} 映射不一致!")
```

## 方法二：赔率数值验证

检查每个赔率值是否与标准赔率一致：

| 投注类型 | 标准赔率（含本金） | Mega Roulette |
|---------|------------------|---------------|
| 直注 | 36.0 (35:1) | 30.0 (29:1) |
| 分注 | 18.0 (17:1) | 18.0 ✓ |
| 街注 | 12.0 (11:1) | 12.0 ✓ |
| 角注 | 9.0 (8:1) | 9.0 ✓ |
| 六线 | 6.0 (5:1) | 6.0 ✓ |
| 列/打 | 3.0 (2:1) | 3.0 ✓ |
| 等额 | 2.0 (1:1) | 2.0 ✓ |

## 方法三：用户下注验证

从 HAR 中找到有用户下注的轮次，验证：

```
用户下注 bc=43 (Dozen 1-12) amt=0.5
开奖 score=16 → 16 在 13-24 → bc43 不中
开奖 score=3 → 3 在 1-12 → bc43 中 → payout = 0.5 × 3.0 = 1.50

对比 <win> 消息: win="1.50" ✓
```

## 决策矩阵

| 条件 | 推荐策略 |
|------|---------|
| gameresult 包含 bXX 赔率 + betCode 编号与标准一致 | 可自主计算或使用 PP 赔率 |
| gameresult 包含 bXX 赔率 + betCode 编号有偏差 | **必须使用 PP 赔率**（如 Mega Roulette） |
| gameresult 不包含 bXX 赔率 + 固定赔率 | 自主计算（如 Crystal Roulette） |
| gameresult 包含动态赔率字段（如 DT 的 d/t/st） | 使用 PP 动态赔率 + fallback 静态 |

## 注意事项

- betCode 编号不能假设与标准轮盘一致（Mega Roulette 六线注偏移 + 6 个独有投注）
- 至少用 5 轮数据验证，覆盖不同号码和颜色
- 验证时排除区域注（bc 160+），这些在不同游戏中定义不同
