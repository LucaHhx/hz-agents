---
name: go-unit-testing
description: Write meaningful Go unit tests that verify interface contracts using real instances and real data. Use when the user asks to write/add/improve Go tests, create *_test.go files, "给这个写测试 / 补单测 / 提高覆盖率 / 测一下这个 interface / 写 Go 单元测试 / go test", or whenever Go test files are being created or edited. Stops AI from writing fake tests (testing trivial private helpers, mock-feeds-mock assertions, nil-check / trivially-true assertions, fake-data happy paths) by enforcing a contract-first methodology.
---

# Go Unit Testing — 契约优先

> 这个 skill 解决一个具体问题：AI 写 Go 测试时倾向于测**平凡的私有工具函数**、用**捏造数据**、做**实现细节断言**，结果是 CPU 烧了一堆但真实 bug 一个测不出。
>
> 核心方法论：**找到 interface（或对外公共方法集）→ 提取契约 → 用真实数据构造真实实例 → 一条契约写一条测试**。

## 四条铁律

1. **测接口契约，不测实现细节** — 重构内部实现但保持契约不变时，测试**不应该**挂。
2. **用真实数据构造的真实实例** — 不用 `"foo"/"bar"/123` 占位，不用 mock 喂 mock 自己。
3. **请求和响应一律用结构体** — 禁止用 `map[string]any` 构造请求或解析响应，结构体字段就是契约的载体。
4. **没有契约可测的代码，默认不写测试** — 私有 helper、平凡 getter、nil 检查、wrapper 一律跳过。

## 写测试前的三问过滤器（强制）

每个准备添加的测试，先用三问过一遍。任何一问"否"，**重写或删掉**。

| 问题 | 否 → 怎么办 |
|------|------------|
| 1. 我测的是 **interface 实现** 或 **公共 API 方法集** 吗？ | 默认不测；除非这是包含非平凡业务逻辑的公共函数 |
| 2. 我用 **真实数据构造的真实实例** 调用它吗？ | 重写：去掉 mock-feeds-mock，去掉占位数据 |
| 3. 请求和响应是用 **结构体** 表达的吗？还是 `map[string]any`？ | 重写：定义 Request/Response struct，解析进去再断言字段 |
| 4. 我断言的是 **调用方关心的契约**，还是 **实现细节**？ | 重写：契约失败应导致用户/调用方可感知的故障 |

> "调用方关心的契约" 的判定：如果这个断言挂了，调用方会写一份 bug report 吗？不会 → 在测实现细节。

## 工作流：四步法

### 步骤 1 — 锁定测试目标（一定是 interface / 公共方法集）

测试目标**必须**是其中之一：
- 一个 `interface` 类型
- 一个对外暴露的 struct 的公共方法集（首字母大写的方法）
- 一个对外暴露的顶层函数（且包含业务逻辑）

不在这个清单里的（私有方法、私有函数、getter）**默认不测**。

### 步骤 2 — 提取契约清单

阅读以下信息源，逐条记录契约：

1. **接口注释 / 方法注释** — 显式声明的不变量、前置条件、后置条件、并发保证、幂等性、生命周期。
2. **方法签名** — 返回 `error` 的方法，错误分支就是契约的一部分。
3. **参数语义** — `[]byte` 是否会被内部修改？`context` 是否被尊重？指针是否可为 nil？
4. **文档 / 设计文档** — 调用方期望、调用顺序约束。

**契约写成一句话**，主语是"被测对象"，谓语是"在 X 输入下 Y 行为"：
- "`Submit*` 方法在调用后**不修改**调用方传入的 slice"
- "`Close()` 被调用第二次时**不 panic**"
- "`GetOrCreate(id)` 多次调用相同 id **返回同一指针**"
- "`Process(ctx)` 在 ctx 取消时**返回 ctx.Err()** 且不写入下游"

每一条契约 = 一个独立的测试用例。

### 步骤 3 — 构造真实实例 + 真实数据

**真实实例**意味着：
- 优先 `New<T>(...)` 构造函数走完整的初始化路径，不要手搓 struct literal 绕过 invariants
- 同包内的依赖一律用真实实现
- **跨进程边界的依赖**（DB / Redis / HTTP / message queue）才考虑替身：
  - 数据库：优先 sqlite in-memory 或 testcontainers，避免 `sqlmock`（它测的是 SQL 字符串而非数据语义）
  - Redis：用 `miniredis` 而不是 mock interface
  - HTTP：用 `httptest.Server` 而不是 mock client
- 同包 struct **禁止 mock** —— 用真的；如果真的难构造，说明设计有问题，重构而不是 mock

**真实数据**意味着：
- 反映真实业务场景（真的字段、真的取值范围、真的边界）
- 大块结构化样本放 `testdata/` 目录，从抓包/导出/真实日志获取
- 数值不要总用 `1, 2, 3` —— 用业务里真会出现的数（比如金额用 `1599` 而不是 `100`）
- 字符串不要总用 `"foo"` —— 用真实 ID 形态（如 `"GAME-001"` / `"42_13157494313"`）

**结构体优先（强制）**：
HTTP / RPC / 消息协议测试中，**请求和响应一律用结构体表达**，禁止 `map[string]any`：

| 阶段 | 必做 | 禁止 |
|------|------|------|
| 构造请求 | 定义 `XxxRequest` struct，json tag 对应字段，用 struct literal 填值 | `map[string]any{"foo": ...}` 拼请求 |
| 解析响应 | 定义 `XxxResponse` struct，`json.Unmarshal` 进结构体 | 用 `map[string]any` 接、`result["foo"].(string)` 强转 |
| 断言 | 在结构体字段上做断言（`resp.GameID`, `resp.LaunchURL`） | 只断 `status == 200`，body 丢掉 |
| 调试输出 | 失败时 `t.Logf("resp: %+v", resp)` 打印结构体 | 不打印；或只打 raw bytes |

**为什么强制结构体**：
- map 字段名拼错编译器不报错，AI 容易写出"打了字段名但永远读不到值"的假断言
- 结构体强制声明契约 —— Request/Response 字段就是 API 契约的代码化表达
- 重命名字段时编译器立即报错，测试和契约同步演进
- 失败时 `%+v` 打印结构体一目了然，map 输出顺序还不稳定

被测系统已有的 Request/Response 类型 → **直接复用**，不要在测试里另起一个并行的版本。

### 步骤 4 — 一条契约一条测试

测试名直接写出**被测对象 + 契约**：

```go
func TestRoundArchiver_SubmitVideoFrame_CopiesData(t *testing.T)        // 拷贝契约
func TestRoundArchiver_Close_IsIdempotent(t *testing.T)                 // 幂等契约
func TestArchiveManager_GetOrCreate_SameTableReturnsSameInstance(...)   // 单例契约
```

测试体三段式：
```go
func TestX_Y_Z(t *testing.T) {
    // Arrange — 真实实例 + 真实数据
    obj := NewObj(realDep1, realDep2)
    input := realisticInput()

    // Act — 触发被测契约
    out, err := obj.Method(input)

    // Assert — 只断言契约本身
    require.NoError(t, err)
    assert.Equal(t, expectedContractOutput, out)
}
```

## 完整示例：从 interface 到测试

源代码：

```go
// RoundArchiver 单机台的归档器。
// 所有 Submit* 方法必须是非阻塞的：内部只做 channel 投递或 atomic 丢弃计数，
// 绝不执行磁盘 IO 或数据库调用。
type RoundArchiver interface {
    // SubmitVideoFrame 投递一帧视频数据。传入的 data 会被内部拷贝，调用方无需保留。
    SubmitVideoFrame(data []byte)
    // Close 让后台 goroutine 关闭、flush、退出。幂等。
    Close()
}
```

**契约抽取（4 条）**：
1. `SubmitVideoFrame` 拷贝 data —— 调用方修改原 slice 不影响内部
2. `Submit*` 非阻塞 —— 调用耗时上限可观测（如 < 1ms）
3. `Close` 幂等 —— 调用 N 次不 panic
4. `Close` 后再 `Submit*` —— 不 panic（生命周期契约）

**测试代码（每条契约一个测试）**：

```go
func TestRoundArchiver_SubmitVideoFrame_CopiesData(t *testing.T) {
    a := NewRoundArchiver(t.TempDir(), "table-42")  // 真实实例
    t.Cleanup(a.Close)

    frame := []byte{0x01, 0x02, 0x03}                // 真实数据
    a.SubmitVideoFrame(frame)
    frame[0] = 0xFF                                  // 调用方污染原 buf

    got := readArchivedFrame(t, a)                   // 从真实落盘文件读
    assert.Equal(t, []byte{0x01, 0x02, 0x03}, got)
}

func TestRoundArchiver_Submit_IsNonBlocking(t *testing.T) {
    a := NewRoundArchiver(t.TempDir(), "table-42")
    t.Cleanup(a.Close)

    start := time.Now()
    for i := 0; i < 1000; i++ {
        a.SubmitVideoFrame(make([]byte, 4096))
    }
    assert.Less(t, time.Since(start), 50*time.Millisecond)  // 1000 次调用上限
}

func TestRoundArchiver_Close_IsIdempotent(t *testing.T) {
    a := NewRoundArchiver(t.TempDir(), "table-42")
    a.Close()
    assert.NotPanics(t, a.Close)
}

func TestRoundArchiver_SubmitAfterClose_DoesNotPanic(t *testing.T) {
    a := NewRoundArchiver(t.TempDir(), "table-42")
    a.Close()
    assert.NotPanics(t, func() { a.SubmitVideoFrame([]byte{1}) })
}
```

每个测试都直接对应注释里的一条契约，名字自带契约描述，重构内部实现不会挂。

## 反模式速览

写之前 / 写完之后**都要**对一遍下面这张清单。详见 [references/anti-patterns.md](references/anti-patterns.md)。

| # | 反模式 | 怎么修 |
|---|--------|--------|
| 1 | 测私有 helper / 平凡工具函数 | 删掉；契约从公共方法集进去测，自然覆盖到 |
| 2 | mock 喂自己（`mockRepo.Return(x)` → 断言返回 `x`） | 用真实依赖；非用不可时只断言被测对象的**外部可见**输出 |
| 3 | 测 nil 检查 / 全局变量初值 / constructor 不返回 nil | 删掉；这些不是契约 |
| 4 | trivially-true 断言（`assert.NotNil(obj)` 后无下文） | 删掉或换成实际契约断言 |
| 5 | 占位数据 `"foo"/"bar"/123` | 换成业务里真实出现的数据形态 |
| 6 | 测实现细节（断言内部用了 map / 调用了 X 函数 N 次） | 改成断言外部可见的契约结果 |
| 7 | happy path only | 补错误分支、边界、并发、ctx 取消 |
| 8 | 一个 table-driven 混入多个无关契约 | 拆成多个 test 函数，每个对应一条契约 |
| 9 | `map[string]any` 拼请求 / 解析响应丢字段 | 用 Request/Response struct，json tag 对齐字段，断言结构体字段 |
| 10 | 只断言 HTTP `status == 200`，body 丢弃 | 解析 body 进结构体，断言业务字段（gameId / launchUrl / errorCode 等） |

## 关于 table-driven

table-driven **适用**：同一条契约下，多组等价输入/输出（边界、错误码、状态机转移）。

```go
// 好：一条契约（金额格式化），多组输入
tests := []struct{
    name  string
    cents int64
    want  string
}{
    {"zero", 0, "0.00"},
    {"sub-cent", 1, "0.01"},
    {"large", 999999999, "9999999.99"},
    {"negative", -50, "-0.50"},
}
```

table-driven **不适用**：把不同契约塞同一张表 —— 这种情况拆成多个独立测试。

## 关于 mock

只在被测对象需要跨**进程边界**时使用替身：

| 边界 | 推荐方案 | 不推荐 |
|------|---------|--------|
| 数据库 | sqlite in-memory / testcontainers | sqlmock（测的是 SQL 字符串） |
| Redis | miniredis | mock interface |
| HTTP 客户端 | httptest.Server | mock client interface |
| 文件系统 | t.TempDir() | afero / mock fs |
| 时间 | 注入 clock interface | 直接 mock time.Now |

**绝对禁止**：mock 同包内的 struct 或自己定义的 interface 然后断言"调用了多少次" —— 这就是测实现细节的典型样子。

## 覆盖率不是目标

覆盖率是契约测试**完成后的副产品**，不是目标。出现以下症状时立即停止刷覆盖率：
- 为了覆盖某行而构造永远不会发生的输入
- 写一个测试只是为了 `New()` 跑过
- 测了一遍 `if err != nil { return err }` 这种纯透传

100% 覆盖率 + 全是假测试 < 60% 覆盖率 + 全是契约测试。

## 输出 checklist（提交测试前自检）

- [ ] 每个测试名都包含**被测对象 + 契约**（如 `TestX_Method_Contract`）
- [ ] 没有 mock 同包内的 struct 或自定义 interface
- [ ] 测试数据来自真实业务场景，不是 `"foo"/"bar"/123` 占位符
- [ ] HTTP/RPC 测试的 **请求和响应都用结构体**，没有 `map[string]any`
- [ ] 响应 body **解析进结构体**并断言业务字段，不是只断 `status == 200`
- [ ] 失败时 `t.Logf("%+v", resp)` 打印结构体便于排查
- [ ] 删掉所有 `assert.NotNil` / `assert.NoError` 之后仍然有实质断言
- [ ] 重构内部实现保持契约不变时，测试不会挂（脑内推演一遍）
- [ ] 没有测私有 helper / nil 检查 / 全局变量初值
