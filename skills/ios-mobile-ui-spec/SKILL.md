---
name: ios-mobile-ui-spec
description: >
  iOS 移动端 UI 设计规范速查与应用。涵盖 iOS 26 Liquid Glass 设计理念、组件尺寸、
  画布定义、间距系统、排版规范、SwiftUI 组件参考、以及 iOS 18 对比。
  用于：(1) 设计移动端页面时查询组件尺寸和设计规范,
  (2) 创建符合 iOS 26 Liquid Glass 风格的 UI 设计稿,
  (3) 审查 UI 还原度是否符合 HIG 规范,
  (4) 生成移动端设计原型图,
  (5) 为 SwiftUI 开发提供组件和 API 参考。
  触发词: iOS 设计规范, 移动端规范, 组件尺寸, iOS 26, 画布尺寸,
  间距规范, 按钮尺寸, 输入框规范, 移动端 UI, mobile ui spec, ios spec,
  Liquid Glass, SwiftUI 组件, glass effect, 毛玻璃
---

# iOS 26 移动端 UI 设计规范

## 一、设计理念 — Liquid Glass

iOS 26（WWDC 2025）引入 **Liquid Glass**，是自 iOS 7 以来最重大的视觉重设计。

### 核心特征

| 特征 | 说明 |
|------|------|
| **动态透明** | UI 元素实时折射/反射底层内容，随滚动和交互动态变化 |
| **深度与层次** | 通过光线弯曲（lensing）、高光、自适应阴影营造物理深度感 |
| **内容优先** | 控件收缩/变形以突出内容（如 Tab Bar 滚动时折叠） |
| **跨平台统一** | iOS、iPadOS、macOS Tahoe、watchOS、tvOS、visionOS 共享设计语言 |

### 材质属性

- 折射底层内容（refraction）
- 反射环境光线（reflection）
- 边缘光弯曲效果（edge lensing）
- 自适应明暗模式和高对比模式
- 玻璃元素之间不能互相采样（需用 `GlassEffectContainer` 分组）

### 设计原则

1. **克制使用** — 仅在导航、工具栏等系统级组件使用，不要满屏玻璃
2. **层级清晰** — 玻璃覆盖层需配合 dimming layer
3. **触控友好** — 最小触控目标 44×44pt（小于此值错误率增加 25%+）
4. **三模测试** — 必须在 Light、Dark、Increased Contrast 下验证

---

## 二、画布尺寸

| 类型 | 尺寸 | 适用场景 |
|------|------|---------|
| 最小画布 | 375×667 | iPhone SE / 8，小程序，Flutter 跨平台 |
| 中等画布 | 393×852 | iPhone 14 / 15 |
| **最新画布** | **402×874** | **iPhone 16 Pro / 17 Pro，iOS 26 官方推荐** |

新项目使用 **402 宽**。小程序统一 375 宽。

---

## 三、iOS 26 组件尺寸

### 系统组件

| 组件 | 尺寸 | 备注 |
|------|------|------|
| 状态栏 | 62pt | iPhone 16/17 Pro 通用（含 Dynamic Island） |
| 导航栏（标题栏） | 54pt | 比 iOS 18 增加 10pt |
| 大标题（Large Title） | 106pt | 导航栏展开态 |
| 列表行 | 52pt | 比 iOS 18 增加 8pt |
| 底部 Tab Bar | 95pt | **悬浮 Liquid Glass 设计**，可交互区域 62pt，距底 21pt |
| 底部指示器 | 34pt | Home Indicator 区域 |
| 搜索栏 | 36pt | 圆角胶囊形，背景半透明 |
| Toolbar | 44pt | 底部工具栏 |

### 按钮（44pt 分界线）

| 类型 | 高度 | 圆角 | 场景 |
|------|------|------|------|
| 大按钮 | 50pt | 全圆角（capsule） | 主操作，全宽 CTA |
| 标准按钮 | 44pt | 全圆角 | 通用操作 |
| 中按钮 | 36pt | 全圆角 | 带图标的次要操作 |
| 小按钮 | 28pt | 全圆角 | 描边按钮、紧凑布局 |
| 文字按钮 | 24pt | 无背景 | 辅助链接 |

**iOS 26 新增按钮样式:**

| 样式 | 说明 | SwiftUI |
|------|------|---------|
| Glass | 半透明玻璃按钮（次要操作） | `.buttonStyle(.glass)` |
| Glass Prominent | 不透明玻璃按钮（主要操作） | `.buttonStyle(.glassProminent)` |
| Close | X 关闭按钮（带玻璃效果） | `Button(role: .close) { }` |

### 标签

| 类型 | 高度 |
|------|------|
| 大标签 | 40pt |
| 中标签 | 28pt |
| 小标签 | 16pt |

### 输入框（44pt 标准线）

| 类型 | 高度 |
|------|------|
| 大输入框 | 56pt |
| 中输入框 | 44pt |
| 小输入框 | 32pt |

### 自定义横栏

| 类型 | 高度 |
|------|------|
| 中横栏 | 48pt |
| 大横栏 | 60pt |

### 图标

| 类型 | 尺寸 | 用途 |
|------|------|------|
| 大图标 | 56pt | 快速入口区域 (40-80) |
| 中图标 | 28pt | 导航栏图标 (24-36) |
| 小图标 | 16pt | 列表行内图标 (<24) |

### App Icon（iOS 26 新规）

| 属性 | 规格 |
|------|------|
| 主尺寸 | 1024×1024px PNG |
| 构造方式 | 多层：前景（主体）+ 背景（表面） |
| 安全区 | 核心内容保持在中心 70% 范围内 |
| 模式 | 标准 / 深色 / 透明（Clear Mode） |
| 工具 | Icon Composer（Xcode 内置） |

---

## 四、iOS 18 组件尺寸（对比）

| 组件 | iOS 18 | iOS 26 | 差异 |
|------|--------|--------|------|
| 状态栏 | 50pt | 62pt | +12pt |
| 标题栏 | 44pt | 54pt | +10pt |
| 列表行 | 44pt | 52pt | +8pt |
| 底部导航 | 83pt | 95pt | +12pt（悬浮） |
| 底部指示器 | 34pt | 34pt | 不变 |

---

## 五、排版规范

### 字体

| 字体 | 适用范围 |
|------|---------|
| SF Pro Text | ≤19pt |
| SF Pro Display | ≥20pt |
| SF Pro Rounded | 圆润风格（可选） |
| SF Mono | 等宽/代码 |

### 字号层级

| 样式 | 字号 | 字重 | 用途 |
|------|------|------|------|
| Large Title | 34pt | Bold | 页面主标题 |
| Title 1 | 28pt | Bold | 区域标题 |
| Title 2 | 22pt | Bold | 子标题 |
| Title 3 | 20pt | Semibold | 小标题 |
| Headline | 17pt | Semibold | 强调文本 |
| **Body** | **17pt** | Regular | **正文（推荐默认）** |
| Callout | 16pt | Regular | 辅助说明 |
| Subheadline | 15pt | Regular | 次要信息 |
| Footnote | 13pt | Regular | 脚注 |
| Caption 1 | 12pt | Regular | 小型标签 |
| Caption 2 | 11pt | Regular | 最小文本 |

> iOS 26 中文本整体更 **粗体、左对齐**，尤其在 Alert、Onboarding 等关键场景。

---

## 六、间距系统（4 的倍数）

可用值: 2, 4, 6, 8, 12, 16, 20, 24, 28, 32, 36

| 间距类型 | 推荐值 | 范围 | 说明 |
|----------|--------|------|------|
| 页边距 | 20pt | 16-20 | HIG 官方 16，实际 App 常 ≤10 |
| 组件外间距 | 16pt | 12-36 | 卡片/区块之间 |
| 组件内间距 | 16pt | 12-20 | 卡片内部 padding |
| 元素间距 | 12pt | 4-12 | 图标与文字、行间距 |
| 最小间距 | 8pt | 8+ | 元素间最小安全距离 |

### 圆角

| 用途 | 推荐圆角 |
|------|---------|
| 小元素（标签、徽标） | 8px |
| 中元素（卡片、输入框） | 12px |
| 大元素（弹窗、Sheet） | 16px |
| 按钮、Tab Bar | capsule（全圆角） |

---

## 七、颜色系统

### 系统颜色

| 名称 | Hex（Light） | 用途 |
|------|-------------|------|
| Blue | #007AFF | 主交互色、链接、可选中 |
| Green | #34C759 | 成功、收入 |
| Red | #FF3B30 | 错误、删除、支出 |
| Orange | #FF9500 | 警告 |
| Yellow | #FFCC00 | 提醒 |
| Purple | #AF52DE | 特殊标记 |
| Teal | #5AC8FA | 辅助信息 |

### 语义颜色

| 名称 | 说明 |
|------|------|
| `.label` | 一级文本（黑/白） |
| `.secondaryLabel` | 二级文本（灰） |
| `.tertiaryLabel` | 三级文本（浅灰） |
| `.systemBackground` | 一级背景 |
| `.secondarySystemBackground` | 二级背景（分组内） |
| `.separator` | 分隔线（0.5pt） |

> iOS 26 颜色经过调整以与 Liquid Glass 和谐共存，色相区分度更高。

---

## 八、SwiftUI 组件参考（iOS 26 新增）

### Liquid Glass 效果

```swift
// 基础玻璃效果（默认胶囊形）
Text("Hello").padding().glassEffect()

// 指定形状
Text("Hello").padding().glassEffect(.regular, in: .rect(cornerRadius: 16))

// 透明变体（更通透）
Text("Hello").padding().glassEffect(.clear)

// 带色调
Text("Hello").padding().glassEffect(.regular.tint(.blue))

// 可交互（按压响应）
Text("Hello").padding().glassEffect(.regular.interactive())
```

**变体:** `.regular`（默认半透明）、`.clear`（更通透）、`.identity`（无效果）

### 玻璃按钮样式

```swift
// 半透明玻璃按钮
Button("Cancel") { }.buttonStyle(.glass)

// 不透明玻璃按钮（主操作）
Button("Submit") { }.buttonStyle(.glassProminent)

// 关闭按钮
Button(role: .close) { }
```

### GlassEffectContainer（分组玻璃元素）

```swift
// 多个玻璃元素合并为一个混合形状，支持态射动画
GlassEffectContainer {
    HStack {
        Button("A") { }.glassEffect()
        Button("B") { }.glassEffect()
    }
}
```

### Tab Bar（新悬浮导航）

```swift
// 新结构（替代已废弃的 tabItem）
TabView(selection: $selectedTab) {
    Tab("Feed", systemImage: "list.star", value: 0) {
        FeedView()
    }
    Tab("Settings", systemImage: "gear", value: 1) {
        SettingsView()
    }
}

// 滚动时最小化 Tab Bar
.tabBarMinimizeBehavior(.onScrollDown)

// Tab Bar 底部附件（如正在播放）
.tabViewBottomAccessory {
    NowPlayingView()
}

// 浮动搜索按钮（右下角）
Tab(role: .search) {
    SearchView()
}
```

### 导航栏 & 工具栏

```swift
// 导航副标题
.navigationSubtitle("3 items")

// 搜索栏折叠
.searchToolbarBehavior(.minimize)

// 工具栏间距控制
ToolbarSpacer()

// 隐藏玻璃背景
.sharedBackgroundVisibility(.hidden)
```

### 其他新组件

```swift
// WebView（原生网页嵌入）
WebView(url: URL(string: "https://apple.com")!)

// 富文本编辑
TextEditor(text: $attributedString)  // 支持 AttributedString

// 自动 Animatable 合成
@Animatable
struct MyModifier: ViewModifier {
    var progress: Double
}

// 3D 图表
Chart3D {
    SurfacePlot(data) { ... }
}

// 场景级 padding
.scenePadding()

// 标签图标固定宽度
Label("Title", systemImage: "star")
    .labelFixedIconWidth()

// 列表分区索引
.listSectionIndexLabel("A")
```

---

## 九、核心原则速记

1. **4 的倍数** — 所有尺寸和间距以 4 递增
2. **44pt 分界线** — 控件以 44pt 区分大/中小尺寸，最小触控目标 44×44pt
3. **Liquid Glass** — 仅系统级组件使用（导航、Tab Bar、工具栏），克制不滥用
4. **画布 402×874** — 新项目首选（iPhone 16/17 Pro）
5. **SF Pro 17pt** — 正文默认字号
6. **三模验证** — Light / Dark / Increased Contrast 必须测试
7. **`glassEffect()` 放最后** — 在 modifier chain 中最后应用

---

## 十、设计原型

生成原型时参考 `assets/prototype.html`，展示完整 iOS 26 Liquid Glass 设计系统。

原型包含：
- 画布尺寸可视化对比
- 完整页面结构（状态栏 → 导航栏 → 内容 → 悬浮 Tab Bar）
- iOS 26 vs iOS 18 尺寸对比
- Liquid Glass 效果演示（Tab Bar、导航栏、按钮）
- 控件规范交互展示（按钮、标签、输入框、图标）
- SwiftUI 代码示例面板
- 间距系统可视化
