# 反模式：假测试图鉴

> 用具体代码识别 AI 自己最容易写出的"假测试"，并给出契约化的重写。每个反例都附**为什么是假**和**重写后的样子**。

## 目录

1. [测私有 helper / 平凡工具函数](#1-测私有-helper--平凡工具函数)
2. [Mock 喂自己](#2-mock-喂自己)
3. [测 nil 检查 / 全局变量初值](#3-测-nil-检查--全局变量初值)
4. [Trivially-true 断言](#4-trivially-true-断言)
5. [占位数据 `"foo"/"bar"/123`](#5-占位数据-foobar123)
6. [测实现细节](#6-测实现细节)
7. [Happy path only](#7-happy-path-only)
8. [Table-driven 混入多个契约](#8-table-driven-混入多个契约)
9. [构造非真实实例](#9-构造非真实实例)
10. [用 `map[string]any` 替代结构体（HTTP/RPC 测试）](#10-用-mapstringany-替代结构体httprpc-测试)

---

## 1. 测私有 helper / 平凡工具函数

### 反例

```go
// service/order.go 内部
func roundToCents(amount float64) int64 { return int64(math.Round(amount * 100)) }
func clampQty(q int) int                { if q < 0 { return 0 }; return q }

// AI 写的测试
func TestRoundToCents(t *testing.T) {
    assert.Equal(t, int64(100), roundToCents(1.0))
    assert.Equal(t, int64(50), roundToCents(0.5))
}
func TestClampQty(t *testing.T) {
    assert.Equal(t, 0, clampQty(-5))
    assert.Equal(t, 3, clampQty(3))
}
```

**为什么是假**：测了平凡的私有工具函数，没有任何业务实例，没体现任何对外契约。这些 helper 挂了 → 一定是某个公共方法的契约也挂 → 那条公共契约的测试自然会失败。直接测 helper 是冗余且耦合实现细节。

### 重写

不写 `TestRoundToCents`。改为测 **使用 `roundToCents` 的公共方法的契约**：

```go
func TestOrderService_Create_RoundsTotalToCents(t *testing.T) {
    svc := NewOrderService(realRepo, realPriceCalc)
    
    order, err := svc.Create(ctx, OrderInput{
        Items: []Item{{SKU: "GAME-001", Qty: 3, UnitCents: 1599}},  // 4797 总价
    })
    
    require.NoError(t, err)
    assert.Equal(t, int64(4797), order.TotalCents)  // 契约：总价以 cents 表达
}
```

如果 `roundToCents` 哪天被 `math.Floor` 替代造成偏差 1 cent，这个公共契约测试会挂；同时 `Create` 改用别的内部算法也无须改测试。

---

## 2. Mock 喂自己

### 反例

```go
func TestUserService_GetByID(t *testing.T) {
    mockRepo := new(MockUserRepo)
    mockRepo.On("FindByID", uint(42)).Return(&User{ID: 42, Name: "Alice"}, nil)
    
    svc := NewUserService(mockRepo)
    user, err := svc.GetByID(ctx, 42)
    
    require.NoError(t, err)
    assert.Equal(t, uint(42), user.ID)
    assert.Equal(t, "Alice", user.Name)
}
```

**为什么是假**：mock 被告知"返回 ID=42, Name=Alice"，然后断言返回 ID=42, Name=Alice。这是在测 `testify/mock` 框架本身，不是测 `UserService.GetByID`。`UserService` 内部即使写 `return nil, nil` 这种错的实现，只要把 mock 改个返回值，测试还是绿的。

### 重写

用真实数据库（sqlite in-memory）：

```go
func TestUserService_GetByID_ReturnsPersistedUser(t *testing.T) {
    db := newTestDB(t)                             // 真实 sqlite
    repo := NewUserRepo(db)
    must(t, repo.Insert(ctx, &User{Name: "Alice", Email: "a@example.com"}))
    
    svc := NewUserService(repo)
    user, err := svc.GetByID(ctx, 1)
    
    require.NoError(t, err)
    assert.Equal(t, "Alice", user.Name)
}

func TestUserService_GetByID_NotFound_ReturnsErrUserNotFound(t *testing.T) {
    db := newTestDB(t)
    svc := NewUserService(NewUserRepo(db))
    
    _, err := svc.GetByID(ctx, 9999)
    assert.ErrorIs(t, err, ErrUserNotFound)        // 契约：missing 时返回特定错误
}
```

第一个测试覆盖"读到的就是写入的"；第二个覆盖"找不到时返回特定错误"。两条都是 `UserService` 对调用方的契约。

---

## 3. 测 nil 检查 / 全局变量初值

### 反例

```go
func TestNewArchiver_NotNil(t *testing.T) {
    a := NewArchiver()
    assert.NotNil(t, a)                            // constructor 不返回 nil
}

func TestSetArchiveManager_NilInput(t *testing.T) {
    SetArchiveManager(nil)
    assert.Nil(t, GetArchiveManager())             // 测 if m == nil 这个分支
}

func TestGlobalManager_InitiallyNil(t *testing.T) {
    assert.Nil(t, GetArchiveManager())             // 测全局变量初值
}
```

**为什么是假**：这些都是**实现的存在性检查**，不是契约。`NewArchiver` 返回 nil 会立即被任何下游测试发现；`SetArchiveManager(nil)` 的 nil 处理是实现细节而非对外契约；全局变量初值是 Go 语言规范保证的，不需要测试。

### 重写

直接删掉。改写实际有意义的契约，例如：

```go
func TestArchiveManager_GetOrCreate_ReturnsArchiverThatAccepts(t *testing.T) {
    mgr := NewArchiveManager(t.TempDir())
    a := mgr.GetOrCreate(42, "ppT1", "roulette", buf)
    
    a.SubmitVideoFrame([]byte{1, 2, 3})            // 契约：拿到的 archiver 立即可用
    // 后续读取归档验证落盘
}
```

---

## 4. Trivially-true 断言

### 反例

```go
func TestParseConfig(t *testing.T) {
    cfg, err := ParseConfig("config.yaml")
    require.NoError(t, err)
    assert.NotNil(t, cfg)                          // <- 然后呢？
}

func TestProcess_Returns(t *testing.T) {
    result := Process(input)
    assert.NotEmpty(t, result)                     // <- 任何非空都过
}
```

**为什么是假**：`NotNil`/`NotEmpty` 是最弱的断言，配上"返回了就行"的逻辑等于没测。`ParseConfig` 即使把所有字段读丢，只返回一个空壳，测试照样绿。

### 重写

断言**具体字段** = 配置文件实际期望值：

```go
func TestParseConfig_LoadsAllFields(t *testing.T) {
    cfg, err := ParseConfig("testdata/full.yaml")
    require.NoError(t, err)
    
    assert.Equal(t, "0.0.0.0:8080", cfg.Addr)      // 契约：addr 字段被读取
    assert.Equal(t, 30*time.Second, cfg.Timeout)   // 契约：duration 解析正确
    assert.True(t, cfg.UseRedis)                   // 契约：bool 字段被读取
    assert.Len(t, cfg.AllowedIPs, 3)               // 契约：list 全部加载
}
```

---

## 5. 占位数据 `"foo"/"bar"/123`

### 反例

```go
func TestOrderService_Create(t *testing.T) {
    svc := NewOrderService(realRepo)
    order, err := svc.Create(ctx, OrderInput{
        UserID: 1,                                 // 真实业务里 UserID 是这个值吗？
        Items: []Item{{SKU: "foo", Qty: 1, UnitCents: 100}},  // SKU "foo"？
    })
    require.NoError(t, err)
    assert.Equal(t, int64(100), order.TotalCents)
}
```

**为什么是假**：占位数据无法触发**真实场景的边界**。生产里 SKU 形如 `"GAME-001"`、金额是 `1599 / 9999`、UserID 跨度大、Qty 偶尔会有 `0` 或上限值。占位数据漏掉的 bug：SKU 长度溢出、金额溢出 int32、Qty=0 应拒绝、Unicode SKU 编码……

### 重写

```go
func TestOrderService_Create_ComputesTotalForRealisticInput(t *testing.T) {
    svc := NewOrderService(newTestDB(t))
    
    order, err := svc.Create(ctx, OrderInput{
        UserID: 100042,
        Items: []Item{
            {SKU: "GAME-CRYSTAL-ROUL-00001", Qty: 2, UnitCents: 1599},
            {SKU: "GAME-SWEET-BONANZA-V2",   Qty: 1, UnitCents: 9999},
        },
        Currency: "USD",
    })
    
    require.NoError(t, err)
    assert.Equal(t, int64(13197), order.TotalCents)     // 1599*2 + 9999
}

// 单独测一条边界契约
func TestOrderService_Create_RejectsZeroQty(t *testing.T) {
    svc := NewOrderService(newTestDB(t))
    _, err := svc.Create(ctx, OrderInput{
        Items: []Item{{SKU: "GAME-001", Qty: 0, UnitCents: 1599}},
    })
    assert.ErrorIs(t, err, ErrInvalidQty)
}
```

`testdata/orders/realistic.json` 这类样本应该来自**真实抓包或导出**，不是手搓。

---

## 6. 测实现细节

### 反例

```go
func TestCache_Set_StoresInMap(t *testing.T) {
    c := NewCache()
    c.Set("k", "v")
    
    // 反射进内部 map 检查
    raw := reflect.ValueOf(c).Elem().FieldByName("data")
    assert.Equal(t, "v", raw.MapIndex(reflect.ValueOf("k")).Interface())
}

func TestService_Create_CallsRepoExactlyOnce(t *testing.T) {
    mockRepo := new(MockRepo)
    mockRepo.On("Save", mock.Anything).Return(nil)
    svc := NewService(mockRepo)
    
    svc.Create(ctx, input)
    mockRepo.AssertNumberOfCalls(t, "Save", 1)     // 断言调用次数
}
```

**为什么是假**：第一个测试断言 cache 内部用 map 存 —— 那天换成 sync.Map 或 LRU，测试挂但行为无变化。第二个断言"调用 1 次" —— 那天加了写入前查重（先 Find 再 Save），调用次数变了但调用方契约不变，测试照样挂。这两个都是把测试和实现绑死。

### 重写

只断言**外部可观察的契约**：

```go
func TestCache_Set_ThenGet_ReturnsSameValue(t *testing.T) {
    c := NewCache()
    c.Set("k", "v")
    
    got, ok := c.Get("k")                          // 通过公共 API 验证
    assert.True(t, ok)
    assert.Equal(t, "v", got)
}

func TestService_Create_PersistsRecord(t *testing.T) {
    db := newTestDB(t)
    svc := NewService(NewRepo(db))
    
    svc.Create(ctx, input)
    
    // 通过同一个公共 API 读回来验证
    got, err := svc.GetByID(ctx, input.ID)
    require.NoError(t, err)
    assert.Equal(t, input.Name, got.Name)
}
```

---

## 7. Happy path only

### 反例

```go
func TestDownloadFile_Success(t *testing.T) {
    err := DownloadFile(ctx, "http://example.com/a.txt", "/tmp/a.txt")
    require.NoError(t, err)
}
```

**为什么是假**：只测了一切顺利的情况。生产里这个函数会遇到：网络超时、404、磁盘写满、ctx 取消、超大文件、重定向、TLS 错误。这些才是 bug 高发地，全没测。

### 重写

按错误分支拆，每条契约一个测试：

```go
func TestDownloadFile_Success_WritesContentToDisk(t *testing.T) {
    server := httptest.NewServer(staticHandler("hello"))
    defer server.Close()
    
    dst := filepath.Join(t.TempDir(), "f.txt")
    require.NoError(t, DownloadFile(ctx, server.URL, dst))
    
    got, _ := os.ReadFile(dst)
    assert.Equal(t, "hello", string(got))
}

func TestDownloadFile_404_ReturnsErrNotFound(t *testing.T) {
    server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        http.Error(w, "not found", 404)
    }))
    defer server.Close()
    
    err := DownloadFile(ctx, server.URL, filepath.Join(t.TempDir(), "f"))
    assert.ErrorIs(t, err, ErrNotFound)
}

func TestDownloadFile_CtxCancelled_AbortsImmediately(t *testing.T) {
    server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        time.Sleep(10 * time.Second)               // 长响应
    }))
    defer server.Close()
    
    ctx, cancel := context.WithCancel(context.Background())
    cancel()                                       // 立即取消
    
    err := DownloadFile(ctx, server.URL, filepath.Join(t.TempDir(), "f"))
    assert.ErrorIs(t, err, context.Canceled)
}

func TestDownloadFile_DiskFull_ReturnsIOError(t *testing.T) {
    // 用只读目录模拟磁盘错误
    readonly := t.TempDir()
    require.NoError(t, os.Chmod(readonly, 0o500))
    
    err := DownloadFile(ctx, "http://example.com", filepath.Join(readonly, "f"))
    assert.Error(t, err)
}
```

---

## 8. Table-driven 混入多个契约

### 反例

```go
func TestUserService(t *testing.T) {
    tests := []struct{
        name    string
        action  string
        userID  uint
        wantErr error
        wantOK  bool
    }{
        {"get existing", "get", 1, nil, true},
        {"get missing", "get", 999, ErrNotFound, false},
        {"delete existing", "delete", 1, nil, false},
        {"delete locked", "delete", 2, ErrUserLocked, false},
        {"update name", "update", 1, nil, true},
        {"update invalid email", "update", 1, ErrInvalidEmail, false},
    }
    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            switch tc.action {
            case "get":   ...
            case "delete":...
            case "update":...
            }
        })
    }
}
```

**为什么是假**：把 Get/Delete/Update **三条不同契约**塞一张表里，测试名 `TestUserService` 完全没说测的什么。table 内部还要 switch 区分 action —— 这就是"用 table-driven 写出来的 god test"。哪天加 Update 的字段，要去维护一张和 Get/Delete 都耦合的表。

### 重写

按契约拆开，table 只用于**同一契约**的多组等价输入：

```go
// 一个契约：GetByID 找不到时返回 ErrUserNotFound
func TestUserService_GetByID_NotFound(t *testing.T) {
    svc := newTestSvc(t)
    cases := []uint{0, 9999, math.MaxUint32}        // 多个"不存在"的 ID
    for _, id := range cases {
        t.Run(fmt.Sprintf("id=%d", id), func(t *testing.T) {
            _, err := svc.GetByID(ctx, id)
            assert.ErrorIs(t, err, ErrUserNotFound)
        })
    }
}

// 另一个契约：Delete 锁定用户时返回 ErrUserLocked
func TestUserService_Delete_LockedUser(t *testing.T) {
    svc := newTestSvc(t)
    must(t, svc.Lock(ctx, 1))
    
    err := svc.Delete(ctx, 1)
    assert.ErrorIs(t, err, ErrUserLocked)
}

// 同一契约多组等价输入：Update 邮箱格式校验
func TestUserService_Update_RejectsInvalidEmail(t *testing.T) {
    svc := newTestSvc(t)
    invalid := []string{"", "no-at", "@no-local", "spaces in@x.com", "a@"}
    for _, email := range invalid {
        t.Run(email, func(t *testing.T) {
            err := svc.Update(ctx, 1, UpdateInput{Email: email})
            assert.ErrorIs(t, err, ErrInvalidEmail)
        })
    }
}
```

---

## 9. 构造非真实实例

### 反例

```go
func TestArchiver_Submit(t *testing.T) {
    // 手搓 struct literal，绕过 NewArchiver 的初始化路径
    a := &archiver{
        path:    "/tmp",
        ch:      make(chan []byte, 10),
        // 漏了：closed 字段、bgWorker、wg、metrics ...
    }
    a.SubmitVideoFrame([]byte{1, 2, 3})            // 后台 goroutine 没起，channel 不会被消费
    // 测试碰巧绿，因为 buffer 没满 —— 但生产路径完全没走到
}
```

**为什么是假**：手搓 struct 跳过了 `NewArchiver` 里的 goroutine 启动、metrics 注册、生命周期钩子等。测试在一个**永远不会出现在生产**的对象状态上跑，等于啥都没测。

### 重写

```go
func TestArchiver_Submit_ProducesFrameOnDisk(t *testing.T) {
    a := NewArchiver(t.TempDir(), "table-42")      // 走完整构造路径
    t.Cleanup(a.Close)
    
    a.SubmitVideoFrame([]byte{1, 2, 3})
    
    require.Eventually(t, func() bool {
        return frameWrittenToDisk(t, a)
    }, time.Second, 10*time.Millisecond)           // 等后台 goroutine 落盘
}
```

如果 `NewArchiver` 真的难调用（依赖太重），那是设计问题 —— 提供一个 test helper（`NewArchiverForTest(t)`）封装合理默认值，而不是手搓 struct 绕过初始化。

---

## 10. 用 `map[string]any` 替代结构体（HTTP/RPC 测试）

这是**最高发**的一个反模式 —— 几乎每次 AI 写 HTTP 接口测试都会这么干。

### 反例

```go
func TestHallB2B_LaunchURL(t *testing.T) {
    c := loadHallB2BClient(t)
    body := map[string]any{                              // <-- 反模式 1：map 拼请求
        "gameId":    "550",
        "playerRef": "pp-game:huluca:probe1",
        "currency":  "IDR",
        "language":  "en",
        "country":   "ID",
        "platform":  "WEB",
        "useLive":   true,
    }
    status, _ := c.do(t, "POST", "/api/v1/b2b/pp/launch-url", "", body)  // <-- 反模式 2：响应丢弃
    if status != http.StatusOK {                         // <-- 反模式 3：只断 status
        t.Errorf("expected 200, got %d", status)
    }
}

func TestHallB2B_GetRoundStatus(t *testing.T) {
    c := loadHallB2BClient(t)
    c.do(t, "GET", "/api/v1/b2b/pp/rounds/x/status", "...", nil)  // <-- 反模式 4：连 status 都不断
}
```

**为什么是假**（四重失败叠加）：

1. **map 拼请求 → 字段拼错也不报错**。`"playerRef"` 写成 `"playRef"` 编译过、运行过、测试过 —— 但实际服务端永远收不到这个字段。AI 没有任何机制能发现自己写错了字段名。
2. **响应丢弃 (`status, _ := ...`)** → 服务端可能返回 `{"errorCode": "INVALID_GAME"}` 配合 HTTP 200（很多框架就这么设计），测试照样绿，但实际功能完全坏。
3. **只断 `status == 200`** → 没验证任何业务字段。`launchUrl` 是空字符串、是错误的域名、是过期的 URL，都查不出来。
4. **后两个测试连 status 都不断**（`c.do(...)` 直接丢） → 等于 "只要不 panic 就算过"。即使后端把整个 endpoint 删了返回 404，测试还是绿的。

这种测试"跑过了"完全无意义 —— 它没回答任何契约问题。

### 重写

四步走：定义请求结构体 → 定义响应结构体 → 解析进结构体 → 断言业务字段。

```go
// === 1. 定义请求/响应结构体（如果业务代码已有，直接复用） ===
type LaunchURLRequest struct {
    GameID    string `json:"gameId"`
    PlayerRef string `json:"playerRef"`
    Currency  string `json:"currency"`
    Language  string `json:"language"`
    Country   string `json:"country"`
    Platform  string `json:"platform"`
    UseLive   bool   `json:"useLive"`
}

type LaunchURLResponse struct {
    Code    int    `json:"code"`
    Message string `json:"msg"`
    Data    struct {
        LaunchURL string `json:"launchUrl"`
        SessionID string `json:"sessionId"`
        ExpiresAt int64  `json:"expiresAt"`
    } `json:"data"`
}

// === 2. 测试 ===
func TestHallB2B_LaunchURL_ReturnsValidPlayURL(t *testing.T) {
    c := loadHallB2BClient(t)

    req := LaunchURLRequest{                             // 真实结构体
        GameID:    "550",
        PlayerRef: "pp-game:huluca:probe1",
        Currency:  "IDR",
        Language:  "en",
        Country:   "ID",
        Platform:  "WEB",
        UseLive:   true,
    }

    status, body := c.do(t, "POST", "/api/v1/b2b/pp/launch-url", "", req)
    require.Equal(t, http.StatusOK, status, "body=%s", body)

    var resp LaunchURLResponse                           // 解析进结构体
    require.NoError(t, json.Unmarshal(body, &resp), "body=%s", body)

    t.Logf("LaunchURL response: %+v", resp)              // 打印结构体便于调试

    // 业务字段断言（契约）
    assert.Equal(t, 0, resp.Code, "msg=%s", resp.Message)        // 契约：成功 code=0
    assert.NotEmpty(t, resp.Data.LaunchURL, "launchUrl 必须返回")  // 契约：必返回 URL
    assert.Contains(t, resp.Data.LaunchURL, "pragmaticplay",      // 契约：URL 指向上游
        "launchUrl 应指向 PP 域名")
    assert.Greater(t, resp.Data.ExpiresAt, time.Now().Unix(),    // 契约：过期时间在未来
        "session 不应已过期")
}
```

### 为什么这样写更好

- **字段拼错立即报错**：`req.PlayrRef = "x"` 编译失败。
- **契约可读**：从测试就能看出 `LaunchURL` 应包含 `pragmaticplay`、`ExpiresAt` 应在未来 —— 这些都是文档没写但生产真在依赖的契约。
- **失败可调试**：`t.Logf("%+v", resp)` 在 CI 失败时一眼能看到完整响应；map 输出顺序不稳定，定位问题难。
- **重构对齐**：服务端给 Response 改字段名（如 `launchUrl` → `playUrl`），测试**编译失败**强制更新；map 版本会 silently 读到零值。
- **复用即契约**：如果服务端代码已有 `LaunchURLResponse` 类型，**直接 import 复用** —— 测试和业务代码共享同一份契约定义。

### 错误响应也要进结构体

```go
func TestHallB2B_LaunchURL_InvalidGameID_ReturnsBusinessError(t *testing.T) {
    c := loadHallB2BClient(t)
    req := LaunchURLRequest{GameID: "not-a-real-game", PlayerRef: "x"}

    status, body := c.do(t, "POST", "/api/v1/b2b/pp/launch-url", "", req)

    var resp LaunchURLResponse
    require.NoError(t, json.Unmarshal(body, &resp))
    t.Logf("error response: %+v", resp)

    assert.Equal(t, http.StatusOK, status)               // 业务错误也是 HTTP 200
    assert.NotZero(t, resp.Code)                          // 契约：错误 code != 0
    assert.NotEmpty(t, resp.Message)                      // 契约：必返回错误信息
    assert.Empty(t, resp.Data.LaunchURL)                  // 契约：错误时不返回 URL
}
```

### 例外（且仅限于此）

只有一种情况可以用 `map[string]any`：测**故意构造畸形请求**（如缺字段、多字段、类型错），验证服务端 schema 校验。这种情况**测试名必须明确说明**：

```go
func TestHallB2B_LaunchURL_MissingGameID_Returns400(t *testing.T) {
    body := map[string]any{"playerRef": "x"}             // 故意省略 gameId
    status, _ := c.do(t, "POST", "/api/v1/b2b/pp/launch-url", "", body)
    assert.Equal(t, http.StatusBadRequest, status)
}
```

---

## 速记口诀

写测试前默念四句：

1. **"我测的是契约还是细节"** —— 重构内部不挂的才叫契约。
2. **"如果删掉这个 mock / 占位数据，测试还有意义吗"** —— 没有就是假测试。
3. **"这个测试挂了，调用方真的会感知到吗"** —— 不会就别测。
4. **"请求和响应都用结构体了吗，业务字段都断言了吗"** —— `map[string]any` + 只断 status 200 = 假测试。
