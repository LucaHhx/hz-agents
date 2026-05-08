# Phase 3 — 客户端代码分析（main.js 字典提取）

`grep_client_dict.sh` 的内部逻辑 + 手动深挖时的 grep 模式手册。

## 目标产出（dict.json 结构）

```json
{
  "gameType": "<from main.js or lobby>",
  "client_version": "5.4.11",
  "lpbet_format": {
    "gm_pattern": "${gametype}_${desktop|mobile}",   // 动态拼接
    "gm_resolved": "speedbaccarat_desktop",          // 实际值（含 lobby gameType + desktop）
    "attrs": ["gm", "gId", "uId", "ck"],
    "child_bet_attrs": ["amt", "bc", "ck"],
    "child_freechip_attrs": ["bcode", "bettype", "cv", "cn", "bonusId"]
  },
  "ping_format": "<ping channel=\"...\" time=\"...\"/>",
  "upstream_events": ["table", "dealer", "game", "timer", "betsopen", "..."],
  "downstream_commands": ["ping", "subscribe", "command/lpbet", "decision?"],
  "betcodes": {
    "0": "Player",
    "1": "Banker",
    ...
  },
  "gr_field_to_betcode": {
    "p": 0, "b": 1, "t": 2, ...
  },
  "error_codes": {
    "1007": "BetNotOnTime",
    ...
  },
  "init_sequence": ["table", "dealer", "game", "timer", "betstats", ...]
}
```

## grep 模式手册（按字典分组）

### 1. 上游事件枚举（main.js 字典 `r`）

```bash
# 模式 A：常量对象一次性 grep
rg -o 'Bet:"bet",BetValidationError:"betValidationError",[^}]+' apps/<gameType>/*/main.js

# 模式 B：messageName 注册（分散 case）
rg -o '\w{1,4}\(this,"messageName","([a-zA-Z_]+)"' apps/<gameType>/*/main.js | sort -u
```

产物：完整事件名清单。

### 2. 下游指令格式（lpbet / ping / subscribe）

```bash
# lpbet 完整拼接
rg -o '"<command channel=[^"]+"' apps/<gameType>/*/main.js | head
rg -o 'gm="[^"]*"' apps/<gameType>/*/main.js | sort -u
rg -o 'gm=\\?[\'"]\\?\\.concat\\(.*?,_,.*?_,M\\?"desktop"' apps/<gameType>/*/main.js

# ping 拼接
rg -o '"<ping[^"]+"' apps/<gameType>/*/main.js
```

**关键陷阱**：lpbet 的 `gm` **不是字面量** —— 是 `${session.gametype}_${desktop|mobile}` 动态拼接。
main.js 出现的 `"baccarat_desktop"` 等字面量是 `pbdealnow` / `playerUnsub` / `playerCardPeel` 的固定值，**不是 lpbet 的 gm**。

### 3. betCode 数值表（Pp / Rp / xp 枚举）

```bash
# Pp 字典定义（基础 betCode）
python3 -c "
import re
src = open('apps/<gameType>/<version>/main.js').read()
m = re.search(r'let Pp=function\(e\)\{return\s+(.*?)return\s+e\}\(\{\}\)', src, re.DOTALL)
if m:
    for k, v in re.findall(r'e\.([A-Za-z0-9_]+)\s*=\s*(\d+)', m.group(1)):
        print(int(v), k)
"

# Rp / xp（变体偏移；Korean baccarat 等）
python3 -c "..."   # 同模式，name 改 Rp / xp
```

注意：
- Pp 是基础 betCode
- Rp / xp 是变体偏移（Korean baccarat 的 Banker=26 / Player=11+10 等）
- speedbaccarat → Pp + Up 反查表多出来的（如 14/15/18/19 红黑）

### 4. GR 字段 → betCode 反查表（`Up`）

```bash
rg -o 'Up=\{[^\}]+\}' apps/<gameType>/*/main.js
```

输出形如 `Up={a8:29,b:1,b6:24,bb:13,bp:4,...}`。

**命名陷阱**（baccarat 系常见）：
- `bb` = BankerBonus（13），**不是** banker_pair
- `bp` = BankerPair（4），**不是** banker_black
- `bnc` / `pnc` / `bg` / `sm` 在 capture 下发但 **不在 Up 表 → 不参与结算**

### 5. 错误码表（`qe.a` 或类似）

```bash
python3 -c "
import re
src = open('apps/<gameType>/<version>/main.js').read()
idx = src.find('BetCodeError=1028')
s = src.rfind('let a=function(e){return ', 0, idx)
m = re.search(r'function\(e\)\{return\s+(.*?return\s+e)\}', src[s:s+10000], re.DOTALL)
if m:
    for k, v in re.findall(r'e\.([A-Za-z0-9_]+)\s*=\s*(\d+(?:e\d+)?)', m.group(1)):
        try: print(int(float(v)), k)
        except: pass
"
```

PP 错误码**协议级稳定**（跨机台一致），如发现新值 → 报告。

### 6. 接收侧帧处理（决定服务端要合成哪些帧）

```bash
# Bets / Win / Winners / Command 等接收侧 process(e) 函数
rg -A 30 'qe\.b\.Bets\b' apps/<gameType>/*/main.js | head -40
rg -A 30 'qe\.b\.Win\b' apps/<gameType>/*/main.js | head -40
rg -A 30 'qe\.b\.Winners\b' apps/<gameType>/*/main.js | head -40
```

读 `process(e)` 体反推服务端必须给出哪些字段。

**baccarat 特殊**：grep 不到 `winningBetCodes` / `betSpotWin` → 客户端不收 → 服务端**不合成**这两类帧。

### 7. 错误码 → toast 映射

```bash
# 找 BetValidationError 的 process(e)
rg -A 30 'qe\.b\.BetValidationError\b' apps/<gameType>/*/main.js | head -50
```

读 `switch(r)` 体看每个 PP 错误码触发什么客户端反应（toast / popup / wipeBet）。

### 8. 控制流帧（switch / session / kick）

```bash
rg -B 5 -A 15 'qe\.b\.Switch\b' apps/<gameType>/*/main.js
rg -B 5 -A 15 'qe\.b\.Session\b' apps/<gameType>/*/main.js
rg -B 5 -A 15 'qe\.b\.Kickedout\b' apps/<gameType>/*/main.js
```

### 9. tableVariant / 桌台变体

```bash
rg -o 'Mp=\{[^\}]+\}' apps/<gameType>/*/main.js
# 搭配 Hp 表（变体激活的 betCode 集合）
rg -o 'Hp=\{[^\}]+\}' apps/<gameType>/*/main.js
```

`Mp` 列出所有 tableVariant 字面量（classic/speedbaccarat/megabaccarat/...），`Hp[<variant>]` 给出该变体激活的 betCode 集合。

### 10. 初始化序列（顺序读 message.json）

```python
import json
msgs = json.load(open('tmp/<tableId>/message.json'))
init_seq = []
for m in msgs:
    try:
        p = json.loads(m['payload'])
        for k in p: init_seq.append(k)
        if 'subscribe' in p: break
    except: pass
print(init_seq)
```

输出形如 `['table','dealer','game','timer','betstats','card','ShoeSummary','statistic','disablesidebets','cardinc','subscribe']`。

## 异常情况处理

| 情况 | 处理 |
|---|---|
| `Pp` 字典 grep 不到 | 检查 main.js 是否被压缩成多文件（看 webpack chunks），扫所有 `*.js` |
| `Up` 字典 grep 不到（轮盘类机台没有 GR 反查） | OK — 轮盘是固定赔率表，结算公式不同（参考 frame-synthesis.md） |
| 错误码值与既有先例不一致 | exit + 报告（PP 协议级稳定）|
| 字段类型 grep 不出（数字 vs 字符串）| capture 实际样本是真理，按 capture 字段值的 JSON 类型定义结构体 |

## 一帧多事件检测

```python
import json
msgs = json.load(open('tmp/<tableId>/message.json'))
multi = [m for m in msgs if len(json.loads(m['payload'])) > 1]
print(f"多 key 帧数: {len(multi)}")
for m in multi[:5]:
    print(list(json.loads(m['payload']).keys()))
```

如果**有**多 key 单帧 → 必须实现 `orderKeysByPriority`（gameresult 必须先于 winners 处理）+ 单 key verdict 单独决定（不能"一个 drop 整帧 drop"）。

如果**无**多 key 单帧（capture 验证）→ 仍**必须**实现防御性顺序处理（PP 协议规范要求）。
