# WDA HTTP API 完整参考

Base URL: `http://localhost:8100`

## 状态

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/status` | 服务状态、设备信息 |
| GET | `/healthcheck` | 健康检查 |

## Session

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| POST | `/session` | `{"capabilities":{"alwaysMatch":{"bundleId":"..."}}}` | 创建 session |
| GET | `/session/{sid}` | - | 获取 session 信息 |
| DELETE | `/session/{sid}` | - | 删除 session |

## Source / DOM

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/session/{sid}/source` | XML 格式 source tree |
| GET | `/session/{sid}/source?format=json` | JSON 格式 source tree |
| GET | `/source` | 无 session 获取 source（部分 WDA 版本支持） |

## 查找元素

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| POST | `/session/{sid}/element` | `{"using":"...","value":"..."}` | 查找单个元素 |
| POST | `/session/{sid}/elements` | `{"using":"...","value":"..."}` | 查找多个元素 |
| POST | `/session/{sid}/element/{eid}/element` | `{"using":"...","value":"..."}` | 在元素内查找子元素 |
| POST | `/session/{sid}/element/{eid}/elements` | `{"using":"...","value":"..."}` | 在元素内查找多个子元素 |

### 查找策略 (using 字段)

| 策略 | 示例 value | 说明 |
|------|-----------|------|
| `class name` | `XCUIElementTypeButton` | XCUIElement 类型 |
| `xpath` | `//XCUIElementTypeButton[@name='OK']` | XPath 表达式（最慢） |
| `predicate string` | `label == 'Settings' AND visible == true` | NSPredicate（推荐，最快） |
| `class chain` | `**/XCUIElementTypeCell[\`label CONTAINS 'Wi-Fi'\`]` | Class Chain |
| `link text` | `Settings` | 完全匹配 name/label |
| `partial link text` | `Sett` | 部分匹配 name/label |

### NSPredicate 常用写法

```
label == 'text'              # 精确匹配
label CONTAINS 'text'        # 包含
label BEGINSWITH 'text'      # 开头
label ENDSWITH 'text'        # 结尾
label MATCHES 'regex'        # 正则
name == 'text'               # name 属性
visible == true              # 可见
enabled == true              # 可用
type == 'XCUIElementTypeButton'  # 元素类型

# 组合
label == 'OK' AND type == 'XCUIElementTypeButton'
label CONTAINS 'Save' OR label CONTAINS 'Done'
```

## 元素属性

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/session/{sid}/element/{eid}/text` | 元素文本 |
| GET | `/session/{sid}/element/{eid}/name` | 元素 tag name |
| GET | `/session/{sid}/element/{eid}/displayed` | 是否可见 |
| GET | `/session/{sid}/element/{eid}/enabled` | 是否可用 |
| GET | `/session/{sid}/element/{eid}/selected` | 是否选中 |
| GET | `/session/{sid}/element/{eid}/rect` | 位置和尺寸 {x,y,width,height} |
| GET | `/session/{sid}/element/{eid}/attribute/{attr}` | 任意属性（label/name/value/type 等） |

## 元素操作

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| POST | `/session/{sid}/element/{eid}/click` | `{}` | 点击 |
| POST | `/session/{sid}/element/{eid}/value` | `{"value":["c","h","a","r"]}` | 输入文本（字符数组） |
| POST | `/session/{sid}/element/{eid}/clear` | `{}` | 清空输入框 |
| POST | `/session/{sid}/element/{eid}/doubleTap` | `{}` | 双击 |
| POST | `/session/{sid}/element/{eid}/touchAndHold` | `{"duration":2}` | 长按 |
| POST | `/session/{sid}/element/{eid}/scroll` | `{"direction":"down"}` | 在元素内滚动 |

## 坐标操作

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| POST | `/session/{sid}/wda/tap/0` | `{"x":100,"y":200}` | 坐标点击 |
| POST | `/session/{sid}/wda/doubleTap` | `{"x":100,"y":200}` | 坐标双击 |
| POST | `/session/{sid}/wda/touchAndHold` | `{"x":100,"y":200,"duration":1.5}` | 坐标长按 |
| POST | `/session/{sid}/wda/dragfromtoforduration` | `{"fromX":100,"fromY":500,"toX":100,"toY":200,"duration":0.5}` | 滑动/拖拽 |

## W3C Actions (高级手势)

```bash
curl -H "$H" -X POST -d '{
  "actions": [{
    "type": "pointer",
    "id": "finger1",
    "parameters": {"pointerType": "touch"},
    "actions": [
      {"type": "pointerMove", "duration": 0, "x": 100, "y": 500},
      {"type": "pointerDown", "button": 0},
      {"type": "pause", "duration": 100},
      {"type": "pointerMove", "duration": 300, "x": 100, "y": 200},
      {"type": "pointerUp", "button": 0}
    ]
  }]
}' $WDA/session/$SID/actions
```

## 截图

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/session/{sid}/screenshot` | Base64 PNG 截图 |
| GET | `/screenshot` | 无 session 截图 |

## App 管理

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| POST | `/wda/homescreen` | `{}` | 回到主屏幕 |
| POST | `/session/{sid}/wda/apps/launch` | `{"bundleId":"..."}` | 启动 app |
| POST | `/session/{sid}/wda/apps/activate` | `{"bundleId":"..."}` | 激活 app（切到前台） |
| POST | `/session/{sid}/wda/apps/terminate` | `{"bundleId":"..."}` | 终止 app |
| POST | `/session/{sid}/wda/apps/state` | `{"bundleId":"..."}` | 查询 app 状态 |
| POST | `/session/{sid}/wda/deactivateApp` | `{"duration":3}` | 暂时后台化当前 app |

## Alert 弹窗

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| GET | `/session/{sid}/alert/text` | - | 获取弹窗文本 |
| POST | `/session/{sid}/alert/accept` | `{}` | 确认弹窗 |
| POST | `/session/{sid}/alert/dismiss` | `{}` | 取消弹窗 |
| GET | `/session/{sid}/alert/buttons` | - | 获取弹窗按钮列表 |

## 设备控制

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| POST | `/session/{sid}/wda/lock` | `{}` | 锁屏 |
| POST | `/session/{sid}/wda/unlock` | `{}` | 解锁 |
| GET | `/session/{sid}/wda/locked` | - | 是否锁屏 |
| GET | `/session/{sid}/orientation` | - | 获取方向 |
| POST | `/session/{sid}/orientation` | `{"orientation":"LANDSCAPE"}` | 设置方向 |
| GET | `/session/{sid}/window/size` | - | 窗口尺寸 |
| GET | `/session/{sid}/window/rect` | - | 窗口位置和尺寸 |
| POST | `/session/{sid}/wda/pressButton` | `{"name":"home"}` | 按硬件键 |
| POST | `/session/{sid}/wda/pressButton` | `{"name":"volumeUp"}` | 音量加 |
| POST | `/session/{sid}/wda/pressButton` | `{"name":"volumeDown"}` | 音量减 |

## 设备信息

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/session/{sid}/wda/device/info` | 设备信息 |
| GET | `/session/{sid}/wda/batteryInfo` | 电池信息 |
| GET | `/session/{sid}/wda/activeAppInfo` | 当前活跃 app 信息 |

## 剪贴板

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| GET | `/session/{sid}/wda/clipboard` | - | 获取剪贴板（Base64） |
| POST | `/session/{sid}/wda/clipboard` | `{"content":"base64...","contentType":"plaintext"}` | 设置剪贴板 |

## Siri

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| POST | `/session/{sid}/wda/siri/activate` | `{"text":"..."}` | 唤醒 Siri 并发送文本 |

## Touch ID (仅模拟器)

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| POST | `/session/{sid}/wda/touch_id` | `{"match":1}` | 模拟指纹匹配 |
| POST | `/session/{sid}/wda/touch_id` | `{"match":0}` | 模拟指纹不匹配 |

## 键盘

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| POST | `/session/{sid}/wda/keys` | `{"value":["\\n"]}` | 按键（回车） |

## Settings

| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| GET | `/session/{sid}/appium/settings` | - | 获取设置 |
| POST | `/session/{sid}/appium/settings` | `{"settings":{...}}` | 修改设置 |

### 常用设置项

| Key | 默认 | 说明 |
|-----|------|------|
| `snapshotMaxDepth` | 50 | source tree 最大深度 |
| `elementResponseAttributes` | `type,label` | 元素返回的属性 |
| `shouldUseCompactResponses` | true | 紧凑响应 |
| `pageSourceExcludedAttributes` | - | source 排除的属性（加速） |
| `screenshotQuality` | 1 | 截图质量 (0-2) |
| `mjpegServerScreenshotQuality` | 25 | MJPEG 截图质量 |
| `mjpegServerFramerate` | 10 | MJPEG 帧率 |

## XCUIElementType 常见类型

```
XCUIElementTypeButton          按钮
XCUIElementTypeStaticText      静态文本
XCUIElementTypeTextField       输入框
XCUIElementTypeSecureTextField 密码输入框
XCUIElementTypeTextView        多行文本
XCUIElementTypeImage           图片
XCUIElementTypeCell            单元格
XCUIElementTypeTable           表格
XCUIElementTypeCollectionView  集合视图
XCUIElementTypeSwitch          开关
XCUIElementTypeSlider          滑块
XCUIElementTypeNavigationBar   导航栏
XCUIElementTypeTabBar          标签栏
XCUIElementTypeAlert           弹窗
XCUIElementTypeSheet           底部弹出
XCUIElementTypeScrollView      滚动视图
XCUIElementTypeWebView         WebView
XCUIElementTypeOther           其他
XCUIElementTypeApplication     应用根节点
XCUIElementTypeWindow          窗口
```
