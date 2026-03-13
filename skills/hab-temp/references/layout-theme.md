# 布局与主题系统

## 概览

HAB Admin Base 的布局系统由以下核心部分组成：

- **布局框架**：`web/src/view/layout/index.vue` -- 顶层容器，组合 header + aside + 内容区
- **三种布局模式**：normal（侧边栏）、head（顶部导航）、combination（混合模式）
- **状态管理**：`web/src/pinia/modules/app.js` -- 所有布局/主题配置的唯一数据源
- **样式体系**：TailwindCSS 3 + SCSS + Element Plus CSS Variables 三层协作
- **暗黑模式**：基于 `@vueuse/core` 的 `useDark` + TailwindCSS `dark:` 类 + Element Plus dark CSS Variables

---

## 一、应用配置（App Store）

文件：`web/src/pinia/modules/app.js`

### config 对象完整字段

```js
const config = reactive({
  // 显示控制
  weakness: false,              // 色弱模式（filter: invert(80%)）
  grey: false,                  // 灰色模式（filter: grayscale(100%)）
  show_watermark: false,        // 水印开关（el-watermark 组件）
  showTabs: true,               // 标签页开关

  // 主题
  primaryColor: '#3b82f6',      // 主题色（默认 TailwindCSS blue-500）
  darkMode: 'auto',             // 暗黑模式：'dark' | 'light' | 'auto'

  // 布局
  side_mode: 'normal',          // 布局模式：'normal' | 'head' | 'combination'
  layout_side_width: 256,       // 侧边栏展开宽度（px）
  layout_side_collapsed_width: 80,  // 侧边栏折叠宽度（px）
  layout_side_item_height: 48,  // 菜单项高度（px）

  // 动画
  transition_type: 'slide',     // 页面过渡动画：'fade' | 'slide' | 'zoom' | 'none'

  // 国际化
  language: 'en-US',

  // 表格
  table_hight_enable: false,    // 是否启用固定表格高度
  table_hight: 588,             // 固定表格高度值（px）

  // 运行时
  messages: {},                 // i18n 消息缓存
})
```

### 关键响应式状态

| 状态 | 类型 | 说明 |
|------|------|------|
| `isDark` | `Ref<boolean>` | 由 `useDark()` 驱动，自动在 `<html>` 上切换 `dark` / `light` class |
| `device` | `Ref<string>` | `'mobile'` 或 `'desktop'`，由 responsive hook 根据窗口宽度判断 |
| `drawerSize` | `Ref<string>` | 移动端 `'100%'`，桌面端 `'800'` |
| `operateMinWith` | `Ref<string>` | 操作列最小宽度：移动端 `'80'`，桌面端 `'240'` |

### Store 方法

| 方法 | 说明 |
|------|------|
| `toggleTheme(dark)` | 直接切换深/浅色 |
| `toggleDarkMode(mode)` | 设置暗黑模式策略（'dark'/'light'/'auto'） |
| `toggleDevice(device)` | 切换设备类型 |
| `togglePrimaryColor(color)` | 切换主题色 |
| `toggleTabs(show)` | 切换标签页显示 |
| `toggleWeakness(enable)` | 切换色弱模式 |
| `toggleGrey(enable)` | 切换灰度模式 |
| `toggleSideMode(mode)` | 切换菜单模式 |
| `toggleTransition(type)` | 切换过渡动画 |
| `toggleLanguage(lang)` | 切换语言 |
| `toggleConfigSideWidth(width)` | 设置侧边栏宽度 |
| `toggleConfigSideCollapsedWidth(width)` | 设置折叠宽度 |
| `toggleConfigSideItemHeight(height)` | 设置菜单项高度 |
| `toggleConfigWatermark(show)` | 切换水印 |
| `setMessages(messages)` | 设置 i18n 消息 |
| `getMessages()` | 获取 i18n 消息 |

### 暗黑模式切换逻辑

```js
// useDark 管理 <html> 元素的 class
const isDark = useDark({
  selector: 'html',
  attribute: 'class',
  valueDark: 'dark',
  valueLight: 'light'
})

const preferredDark = usePreferredDark()

// 三种模式的处理
watchEffect(() => {
  if (config.darkMode === 'auto') {
    isDark.value = preferredDark.value  // 跟随系统
    return
  }
  isDark.value = config.darkMode === 'dark'
})
```

`useDark()` 会自动在 `<html>` 元素上设置 `class="dark"` 或 `class="light"`，这同时驱动：
- TailwindCSS 的 `dark:` variant（`darkMode: 'class'` 模式）
- Element Plus 的 dark CSS variables（通过 `element-plus/theme-chalk/dark/css-vars.css`）

### 主题色动态应用

文件：`web/src/utils/format.js` 中的 `setBodyPrimaryColor()`

通过 `watchEffect` 监听 `config.primaryColor` 变化，动态设置 CSS 变量：

```js
export const setBodyPrimaryColor = (primaryColor, darkMode) => {
  // 亮色混合目标：rgb(240, 248, 255)（淡蓝白）
  // 暗色混合目标：rgb(10, 10, 30)（深黑蓝）
  let fmtColorFunc = darkMode === 'light' ? generateAllLightColors : generateAllColors

  // 主色
  document.documentElement.style.setProperty('--el-color-primary', primaryColor)
  // 背景色（40% 透明度）
  document.documentElement.style.setProperty('--el-color-primary-bg', addOpacityToColor(primaryColor, 0.4))
  // dark-1 ~ dark-2 色阶
  for (let times = 1; times <= 2; times++) {
    document.documentElement.style.setProperty(`--el-color-primary-dark-${times}`, fmtColorFunc(primaryColor, times / 10))
  }
  // light-1 ~ light-10 色阶
  for (let times = 1; times <= 10; times++) {
    document.documentElement.style.setProperty(`--el-color-primary-light-${times}`, fmtColorFunc(primaryColor, times / 10))
  }
  // 菜单 hover 背景色
  document.documentElement.style.setProperty('--el-menu-hover-bg-color', addOpacityToColor(primaryColor, 0.2))
}
```

在 app store 中通过 watchEffect 自动调用：

```js
watchEffect(() => {
  setBodyPrimaryColor(config.primaryColor, isDark.value ? 'dark' : 'light')
})
```

### 色弱/灰度模式

```js
watchEffect(() => {
  document.documentElement.classList.toggle('html-weakenss', config.weakness)
  document.documentElement.classList.toggle('html-grey', config.grey)
})
```

对应 CSS（`style/main.scss`）：

```scss
.html-grey { filter: grayscale(100%); }
.html-weakenss { filter: invert(80%); }
```

### 配置持久化

设置面板保存时调用 `setSelfSetting(newConfig)` API 将配置存到后端用户表。本地同时以 `localStorage.setItem('originSetting', ...)` 做缓存。

---

## 二、三种布局模式

### 总体结构（layout/index.vue）

```
┌──────────────── header（fixed, h-16, z-10）──────────────┐
│ logo + breadcrumb/nav + tools + user                     │
├──────────────────────────────────────────────────────────┤
│ aside（可选） │  tabs（可选） + router-view              │
│               │  ┌─────────────────────────────────┐    │
│               │  │ <keep-alive> + <transition>      │    │
│               │  │   <component :is="Component" />  │    │
│               │  └─────────────────────────────────┘    │
│               │  BottomInfo                              │
└───────────────┴──────────────────────────────────────────┘
```

### 核心结构代码

```vue
<div class="bg-gray-50 dark:bg-slate-800 w-screen h-screen">
  <!-- 水印层 -->
  <el-watermark v-if="config.show_watermark" :content="userStore.userInfo.nickName" ... />
  <!-- 顶部导航 -->
  <hab-header />
  <!-- 主体区域 -->
  <div class="flex flex-row pt-16 h-full">
    <!-- 侧边栏 1：normal 模式 或 移动端降级 -->
    <hab-aside v-if="config.side_mode === 'normal' ||
      (device === 'mobile' && config.side_mode == 'head') ||
      (device === 'mobile' && config.side_mode == 'combination')" />
    <!-- 侧边栏 2：combination 桌面端的左侧子菜单 -->
    <hab-aside v-if="config.side_mode === 'combination' && device !== 'mobile'" mode="normal" />
    <!-- 内容区 -->
    <div class="flex-1 px-2 w-0 h-full">
      <hab-tabs v-if="config.showTabs" />
      <router-view v-slot="{ Component, route }">
        <transition mode="out-in" :name="route.meta.transitionType || config.transition_type">
          <keep-alive :include="routerStore.keepAliveRouters">
            <component :is="Component" :key="route.fullPath" />
          </keep-alive>
        </transition>
      </router-view>
    </div>
  </div>
</div>
```

### 2.1 Normal 模式（`side_mode === 'normal'`）

文件：`web/src/view/layout/aside/normalMode.vue`

- 左侧显示完整侧边栏
- Header 中显示 breadcrumb（目前已注释掉），不显示导航菜单
- 侧边栏可折叠/展开（底部箭头按钮）
- 展开宽度由 `config.layout_side_width` 控制，折叠宽度由 `config.layout_side_collapsed_width` 控制
- 菜单数据来自 `routerStore.asyncRouters[0].children`
- 使用 `el-scrollbar` 包裹，菜单过长时可滚动
- 激活菜单项使用主题色背景 + 白色文字

### 2.2 Head 模式（`side_mode === 'head'`）

文件：`web/src/view/layout/aside/headMode.vue`

- 侧边栏消失（桌面端）
- 所有一级菜单在 Header 中以水平导航形式展示
- 使用 `el-menu` 的 `mode="horizontal"`
- 菜单宽度自动填充 Header 剩余空间：`w-[calc(100vw-600px)]`
- 激活项使用主题色浅色背景高亮：`background-color: var(--el-color-primary-light-8)`
- 移动端自动降级为 Normal 模式

### 2.3 Combination 模式（`side_mode === 'combination'`）

文件：`web/src/view/layout/aside/combinationMode.vue`

- Header 中展示一级菜单（水平导航），点击后切换左侧二级菜单
- 左侧侧边栏展示当前一级菜单的子菜单
- 内部同时包含 `mode="head"` 和 `mode="normal"` 两个视图
- 一级菜单状态由 `routerStore.topActive` 跟踪
- 二级菜单通过 `routerStore.setLeftMenu(name)` 切换，数据存入 `routerStore.leftMenu`
- 点击顶部一级菜单时自动导航到第一个非隐藏子菜单
- 移动端自动降级为 Normal 模式

### 模式切换条件总结

| 条件 | normal | head | combination |
|------|--------|------|-------------|
| 桌面端 | 左侧边栏 | 顶部菜单 | 顶部一级 + 左侧二级 |
| 移动端 | 左侧边栏(折叠) | 左侧边栏(折叠) | 左侧边栏(折叠) |

---

## 三、侧边栏机制

### 菜单组件层次

```
aside/index.vue                    -- 模式分发器（根据 side_mode 和 device 选择渲染哪个模式）
├── normalMode.vue                 -- 垂直侧边栏
├── headMode.vue                   -- 水平顶部导航
└── combinationMode.vue            -- 混合（顶部一级 + 侧边二级）
    └── asideComponent/index.vue   -- 递归菜单组件（决定渲染 menuItem 还是 asyncSubmenu）
        ├── menuItem.vue           -- 叶子节点（el-menu-item）
        └── asyncSubmenu.vue       -- 分组节点（el-sub-menu，包含子菜单）
```

### 折叠/展开

- `isCollapse` 通过 `provide('isCollapse', isCollapse)` 向下传递给 asyncSubmenu
- 移动端自动折叠（`device === 'mobile'` 时 `isCollapse = true`）
- 折叠按钮在侧边栏底部（`absolute bottom-8`），使用 `DArrowLeft` / `DArrowRight` 图标
- 折叠时宽度切换：`config.layout_side_width` -> `config.layout_side_collapsed_width`
- 折叠时菜单图标居中显示（`el-menu :collapse="isCollapse"`）

### 菜单项高度

通过 `config.layout_side_item_height` 控制（默认 48px），在 menuItem.vue 和 asyncSubmenu.vue 中以内联样式绑定：

```js
const sideHeight = computed(() => config.value.layout_side_item_height + 'px')
```

asyncSubmenu.vue 还通过 CSS `v-bind` 将高度应用到 `.el-sub-menu__title`：

```scss
.hab-sub-menu {
  .el-sub-menu__title {
    height: v-bind('sideHeight') !important;
  }
}
```

### 菜单导航

`selectMenuItem()` 处理三种情况：
1. **普通路由**：`router.push({ name: index, query, params })`
2. **外部链接**（http/https）：`window.open(index, '_blank')`
3. **Iframe 内嵌**：`router.push({ name: 'Iframe', query: { url } })`

菜单路由参数通过 `routerStore.routeMap[index].parameters` 获取，支持 query 和 params 两种传参方式。

### 菜单选中状态

```js
active.value = route.meta.activeName || route.name
```

支持通过 `route.meta.activeName` 自定义选中项（用于详情页保持父菜单高亮）。

### 菜单国际化

菜单标题通过 vue-i18n 翻译，key 格式为 `menu.{route.meta.title}`：

```vue
{{ t("menu." + routerInfo.meta.title) }}
```

---

## 四、标签页系统

文件：`web/src/view/layout/tabs/index.vue`

### 核心功能

- 使用 Element Plus `el-tabs`（`type="card"`）
- 标签唯一标识：`name + JSON.stringify(query) + JSON.stringify(params)`
- 持久化到 `sessionStorage`（key: `historys`、`activeValue`）
- 与 `keep-alive` 联动：通过 `emitter.emit('setKeepAlive', historys)` 同步缓存列表

### 标签操作

| 操作 | 触发方式 | 说明 |
|------|---------|------|
| 新增标签 | 路由变化自动触发 | 去重检查后追加到 historys |
| 关闭标签 | 点击 X | 自动跳转到相邻标签 |
| 中键关闭 | 鼠标中键点击 | 同关闭标签 |
| 关闭所有 | 右键菜单 | 只保留默认路由，跳转到默认路由 |
| 关闭左侧 | 右键菜单 | 关闭右键目标左侧所有标签 |
| 关闭右侧 | 右键菜单 | 关闭右键目标右侧所有标签 |
| 关闭其他 | 右键菜单 | 只保留右键目标标签 |

### 全局事件

| 事件名 | 说明 |
|--------|------|
| `closeThisPage` | 关闭当前页签 |
| `closeAllPage` | 关闭所有页签 |
| `setQuery` | 更新当前标签的 query 参数（不刷新页面，通过 `history.replaceState` 更新 URL） |
| `switchTab` | 切换到指定标签（by name + query + params，自动更新标签参数） |
| `setKeepAlive` | （标签发出）通知 routerStore 更新 keepAlive 缓存列表 |

### 页签与 keep-alive

layout/index.vue 中：

```html
<keep-alive :include="routerStore.keepAliveRouters">
  <component :is="Component" :key="route.fullPath" />
</keep-alive>
```

标签列表变化时通过 `emitter.emit('setKeepAlive', historys)` 通知 router store 更新 `keepAliveRouters`。

### 特殊行为

- 带 `meta.closeTab: true` 的路由在 watch 中被自动过滤（离开后标签自动关闭）
- `needCloseAll` sessionStorage flag：角色切换后自动关闭所有标签
- 右键菜单使用 `position: absolute`，坐标为鼠标点击位置 + 10px 偏移

### 标签页样式

使用 `::v-deep` 覆盖 Element Plus 默认 tabs 样式：
- 去除默认 border
- 每个标签使用 1px 边框 + 2px 圆角
- 激活标签使用主题色边框：`border: 1px solid var(--el-color-primary)`
- 高度 34px

### 显示控制

通过 `config.showTabs` 开关。关闭标签页后内容区高度类切换：

```html
:class="config.showTabs ? 'hab-container2' : 'hab-container pt-1'"
```

---

## 五、Header 区域

文件：`web/src/view/layout/header/index.vue`

### 结构

```
┌─ logo + 应用名称 ─┬─ breadcrumb(normal) / 导航菜单(head/combination) ─┬─ 时间 + tools + 用户 ─┐
```

- **固定定位**：`fixed top-0 left-0 right-0 z-10 h-16`
- **Logo**：来自 `$GIN_VUE_ADMIN.appLogo`（`core/config.js` 中配置，默认 `logo.svg`），点击导航至首页
- **应用名称**：`getPageTitle()` 获取，移动端隐藏，`font-bold text-2xl`
- **导航区域**：
  - normal 模式 => breadcrumb（当前已注释）
  - head 模式 => `<hab-aside>` 水平菜单
  - combination 模式 => `<hab-aside mode="head">` 一级水平菜单
- **时间显示**：每秒更新的本地时间，使用 `$serverDate(currentTime, 'long')` 格式化
- **用户下拉**：角色切换（调用 `setUserAuthority` API 后刷新页面）、个人设置、退出登录

### Tools 工具栏

文件：`web/src/view/layout/header/tools.vue`

工具按钮（均为 `w-8 h-8` 圆形图标按钮，带 shadow + border + tooltip）：

| 按钮 | 图标 | 功能 |
|------|------|------|
| 缓存刷新 | Coin | 打开 bcache 对话框，刷新 gRPC + 本地缓存 |
| 搜索 | Search | 打开 CommandMenu 命令面板（支持 Ctrl+K 快捷键） |
| 设置 | Setting | 打开设置 Drawer |
| 刷新 | Refresh | 触发 `emitter.emit('reload')`，带 `animate-spin` 旋转动画 |
| 主题 | Sunny/Moon | 暗黑模式快速切换（`appStore.toggleTheme()`） |

### 缓存管理（bcache.vue）

文件：`web/src/view/layout/header/bcache.vue`

- 点击后弹出 `ElMessageBox.confirm` 确认框
- 调用 `refreshBCache` API 刷新后端缓存
- Dialog 中以表格形式展示 gRPC 服务和本地服务的缓存刷新结果（成功/失败状态）

---

## 六、设置面板

文件：`web/src/view/layout/setting/index.vue`

通过 `el-drawer` 打开，宽度：桌面 500px，移动端 100%。

### 配置项分组

**主题模式**（el-segmented 三段选择）：
- dark / light / auto

**主题色**：
- 6 个预设色：`#EB2F96`(粉) / `#3b82f6`(蓝) / `#2FEB54`(绿) / `#EBEB2F`(黄) / `#EB2F2F`(红) / `#2FEBEB`(青)
- 自定义色：el-color-picker
- 选中色显示 `<Select />` 对勾图标

**显示设置**：

| 配置项 | 控件 | 说明 |
|--------|------|------|
| 水印 | Switch | 开启后显示用户昵称水印 |
| 灰度模式 | Switch | 页面变灰 |
| 色弱模式 | Switch | 反色 80% |
| 语言 | Select | 从字典 API（`getDict('Language')`）获取可用语言列表 |
| 菜单模式 | Segmented | normal / head / combination |
| 显示标签页 | Switch | 控制 Tabs 组件可见性 |
| 过渡动画 | Select | fade / slide / zoom / none |

**布局设置**：

| 配置项 | 控件 | 范围 | 说明 |
|--------|------|------|------|
| 侧边栏宽度 | InputNumber | 150-400，步长 10 | 展开状态宽度(px) |
| 侧边栏折叠宽度 | InputNumber | 60-100 | 折叠状态宽度(px) |
| 菜单项高度 | InputNumber | 30-50 | 侧边栏菜单项高度(px) |
| 固定表格高度 | Switch | - | 是否启用全局表格固定高度 |
| 表格高度 | InputNumber | 300-1000 | 启用后的固定高度值(px)，仅在开关开启时显示 |

### 配置保存

点击保存按钮：
1. 复制 config 并清空 messages 字段（避免将 i18n 数据发送到后端）
2. 调用 `setSelfSetting(newConfig)` API 持久化到后端
3. 同步保存到 `localStorage('originSetting')`

---

## 七、样式体系

### 三层样式架构

```
TailwindCSS 3                -- 工具类优先，处理布局、间距、颜色
    ↕ 桥接（通过 var() 引用 Element Plus 变量）
Element Plus CSS Variables   -- 组件库主题变量
    ↕ 覆盖
SCSS 文件                    -- 全局样式、Reset、组件覆盖
```

### 7.1 TailwindCSS 配置

文件：`web/tailwind.config.js`

```js
export default {
  content: ['./index.html', './src/**/*.{vue,js,ts,jsx,tsx}'],
  important: true,          // 所有 utility 加 !important，确保覆盖 Element Plus
  darkMode: 'class',        // 通过 <html class="dark"> 切换
  theme: {
    extend: {
      backgroundColor: { main: '#F5F5F5' },
      textColor: { active: 'var(--el-color-primary)' },        // 桥接 Element Plus 主题色
      boxShadowColor: { active: 'var(--el-color-primary)' },
      borderColor: { 'table-border': 'var(--el-border-color-lighter)' }
    }
  }
}
```

关键设计：
- `important: true` 确保 TailwindCSS 的 utility class 能覆盖 Element Plus 默认样式
- 通过 `var(--el-color-primary)` 在 TailwindCSS 中引用 Element Plus 的主题色变量，实现两套体系的颜色同步
- `text-active` 类可在任何地方使用，颜色自动跟随主题色变化

PostCSS 配置（`web/postcss.config.js`）：`tailwindcss` + `autoprefixer`。

### 7.2 样式文件结构与加载顺序

**main.js 中的加载顺序**：

```js
import 'element-plus/dist/index.css'              // 1. Element Plus 基础样式
import 'element-plus/theme-chalk/dark/css-vars.css' // 2. Element Plus 暗黑 CSS 变量
import './style/element_visiable.scss'             // 3. 主样式入口（包含 TailwindCSS 和所有覆盖）
import './styles/dialog-passthrough.css'           // 4. 对话框穿透样式
```

**element_visiable.scss 内部加载**：

```scss
@use '@/style/main.scss';    // → 加载 iconfont.css + transition.scss + 全局工具类
@use '@/style/reset';        // → CSS Reset
@tailwind base;              // → Tailwind 基础层
@tailwind components;        // → Tailwind 组件层
@tailwind utilities;         // → Tailwind 工具层
// ... Element Plus 组件样式覆盖 + 暗黑模式变量
```

#### 文件职责

| 文件 | 说明 |
|------|------|
| `style/element_visiable.scss` | **主入口**：引入 TailwindCSS 指令、Element Plus 全局覆盖样式（按钮、分页、表格、菜单、Drawer、Tabs）、暗黑模式 CSS 变量覆盖 |
| `style/main.scss` | 全局工具类：`.hab-table-box`、`.hab-search-box`、`.hab-form-box`、`.hab-btn-list`、灰色/色弱模式、进度条颜色、滚动条隐藏、图标尺寸 |
| `style/reset.scss` | CSS Reset（基于 normalize.css）+ 全局字体 `'Helvetica Neue', Helvetica, 'PingFang SC', 'Microsoft YaHei', Arial, sans-serif` |
| `style/transition.scss` | 页面过渡动画定义：fade、slide、zoom |
| `style/element/index.scss` | Element Plus 颜色变量覆盖（`@forward` 方式，primary 设为 `#4d70ff`） |
| `style/iconfont.css` | 自定义 habIcon 图标字体（base64 内嵌 TTF），包含：arrow-double-left/right、fullscreen-expand/shrink、customer-service、prompt、refresh、search |
| `styles/index.scss` | Monaco Editor 样式引入 |
| `styles/dialog-passthrough.css` | 对话框背景穿透点击（`.dialog_modal` 使用 `pointer-events: none`，`.el-dialog` 保持 `pointer-events: auto`） |

### 7.3 Element Plus 暗黑模式 CSS 变量覆盖

在 `style/element_visiable.scss` 中：

```scss
html.dark {
  --el-bg-color: rgb(15, 23, 42);              // slate-900（主背景）
  --el-bg-color-overlay: rgb(40, 51, 69);       // 弹窗/覆盖层背景
  --el-bg-color-page: rgb(15, 23, 42);
  --el-fill-color-blank: rgb(15, 23, 42);
  --el-fill-color-light: rgb(15, 23, 42);
  --el-fill-color: rgb(15, 23, 42);
  --el-menu-bg-color: rgb(15, 23, 42);
  --el-menu-hover-bg-color: rgb(30, 41, 59);    // slate-800（hover 状态）
  --el-table-bg-color: rgb(15, 23, 42);
  --el-table-tr-bg-color: rgb(15, 23, 42);
  --el-table-header-bg-color: rgb(15, 23, 42);
  --el-table-row-hover-bg-color: rgb(30, 41, 59);
  --el-card-bg-color: rgb(15, 23, 42);
  --el-dialog-bg-color: rgb(30, 41, 59);
  --el-drawer-bg-color: rgb(30, 41, 59);
  --el-tabs-header-bg-color: rgb(15, 23, 42);
}
```

统一使用 TailwindCSS 的 slate 色阶，保证 Element Plus 组件与 Tailwind 布局的暗黑模式视觉一致。

### 7.4 全局工具类

在 `style/main.scss` 中定义，均使用 `@apply` 混合 TailwindCSS（自动支持暗黑模式）：

| CSS 类 | 用途 | 样式 |
|--------|------|------|
| `.hab-table-box` | 表格容器 | `p-4 bg-white dark:bg-slate-900 rounded my-2` + 表格边框 |
| `.hab-search-box` | 搜索区容器 | `p-4 bg-white dark:bg-slate-900 rounded my-2` |
| `.hab-form-box` | 表单区容器 | `p-4 bg-white dark:bg-slate-900 rounded my-2` |
| `.hab-btn-list` | 按钮列表 | `mb-3 flex items-center` |
| `.hab-customer-icon` | 自定义图标 | `w-4 h-4` |
| `.html-grey` | 灰度模式（加在 html 上） | `filter: grayscale(100%)` |
| `.html-weakenss` | 色弱模式（加在 html 上） | `filter: invert(80%)` |

### 7.5 Element Plus 组件样式覆盖

在 `style/element_visiable.scss` 中：

```scss
// 按钮
.el-button { font-weight: 400; border-radius: 2px; }

// 分页 — 激活页码使用主题色
.hab-pagination .is-active {
  @apply rounded text-white;
  background: var(--el-color-primary);
}

// 表格 — 暗黑模式背景统一 slate-900
.el-table tr th { @apply dark:bg-slate-900; }
.el-table .el-table__row td { @apply dark:bg-slate-900; }

// 垂直菜单选中项 — 主题色背景 + 白色文字
.el-menu--vertical .el-menu-item.is-active {
  background-color: var(--el-color-primary) !important;
  color: #fff !important;
}

// 激活的子菜单标题
.el-sub-menu.is-active > .el-sub-menu__title {
  color: var(--el-color-primary) !important;
}

// Drawer header — 底部边框
.el-drawer__header { @apply border-0 border-b border-solid border-gray-200; }

// 内联表单项宽度
.el-form--inline .el-form-item > .el-input,
.el-form--inline .el-select,
.el-form--inline .el-date-editor { @apply w-52; }
```

### 7.6 Element Plus 基础主题色

文件：`style/element/index.scss`

```scss
@forward 'element-plus/theme-chalk/src/common/var.scss' with (
  $colors: (
    'primary': ('base': #4d70ff),
    'success': ('base': #67c23a),
    'warning': ('base': #e6a23c),
    'danger': ('base': #f56c6c),
    'error': ('base': #f56c6c),
    'info': ('base': #909399)
  )
);
```

这是编译时的静态主题色。运行时会被 `setBodyPrimaryColor()` 的 CSS 变量动态覆盖。

---

## 八、页面过渡动画

文件：`web/src/style/transition.scss`

### 三种动画

| 名称 | 效果 | 持续时间 | 缓动函数 |
|------|------|---------|---------|
| `fade` | 透明度 + 向下位移 10px | 0.3s | ease |
| `slide` | 透明度 + 水平位移（进左-30px 出右+30px） | 0.3s | linear |
| `zoom` | 透明度 + 缩放 0.95 | 0.5s | cubic-bezier(0.4, 0, 0.2, 1) |

在 layout/index.vue 中通过 `<transition>` 组件应用：

```html
<transition mode="out-in" :name="route.meta.transitionType || config.transition_type">
```

支持路由级别覆盖：在路由 meta 中设置 `transitionType` 可针对特定页面使用不同动画。

`none` 选项不匹配任何 transition name，无动画效果。

---

## 九、响应式设计

文件：`web/src/hooks/responsive.js`

### 断点规则

```js
const WIDTH = 992  // 与 TailwindCSS 的 lg 断点一致
function queryDevice() {
  const rect = document.body.getBoundingClientRect()
  return rect.width - 1 < WIDTH  // < 992px 判定为移动端
}
```

使用 `useDebounceFn` 防抖（100ms），避免 resize 事件频繁触发。

### 响应式行为对照

| 场景 | 桌面端 (>= 992px) | 移动端 (< 992px) |
|------|-------------------|-----------------|
| 布局模式 | 按 `side_mode` 配置显示 | 强制降级为 normal（侧边栏模式） |
| 侧边栏 | 默认展开 | 自动折叠 |
| 应用名称 | 显示 | 隐藏 |
| 用户昵称 | 显示 | 隐藏 |
| Drawer 宽度 | 500px（设置）/ 800px（通用） | 100% |
| 操作列最小宽度 | 240px | 80px |

---

## 十、核心文件与全局注册

### core/config.js

```js
const config = {
  appName: 'ADMIN',        // 应用名称
  appLogo: 'logo.svg',     // Logo 路径（public 目录）
  showViteLogo: true,      // 构建时显示 Vite Logo
  logs: []                 // SVG 图标注册日志
}
```

通过 `app.config.globalProperties.$GIN_VUE_ADMIN = config` 挂载为全局属性。模板中通过 `$GIN_VUE_ADMIN.appLogo` 访问。

### core/global.js

- 注册所有 Element Plus 图标组件（`import * as ElIconModules`）
- 注册自定义 SvgIcon 组件
- 扫描 `src/assets/icons/**/*.svg` 和 `src/plugin/**/assets/icons/**/*.svg`
- 自动注册为全局组件，命名规则：`{pluginName}-{iconName}` 或 `{iconName}`
- 开发模式下在 console 输出所有注册的图标名称（方便查找复制）
- 图标名称中不允许包含空格

### core/hab.js

Vue 插件入口，`install` 方法中调用 `global.js` 的 `register()` 函数。在 main.js 中通过 `app.use(run)` 安装。

---

## 十一、其他布局功能

### Iframe 内嵌页

文件：`web/src/view/layout/iframe.vue`

用于在布局框架内嵌入外部网页。URL 通过 `route.query.url` 传入。使用独立的全屏 iframe，支持 reload 刷新。

### 水印功能

在 layout/index.vue 中使用 Element Plus 的 `el-watermark` 组件：

```html
<el-watermark
  v-if="config.show_watermark"
  :font="font"
  :z-index="9999"
  :gap="[180, 150]"
  class="absolute inset-0 pointer-events-none"
  :content="userStore.userInfo.nickName"
/>
```

水印内容为当前用户昵称，暗黑模式下颜色自动切换：
- 亮色：`rgba(0, 0, 0, .15)`
- 暗色：`rgba(255, 255, 255, .15)`

### 全屏功能

文件：`web/src/view/layout/screenfull/index.vue`

使用 `screenfull` 库实现浏览器全屏切换。图标在全屏和窗口模式间切换（`habIcon-fullscreen-expand` / `habIcon-fullscreen-shrink`）。

### 搜索/命令面板

文件：`web/src/view/layout/search/search.vue`

注意：此文件是旧版搜索组件，实际使用的是 `tools.vue` 中引入的 `CommandMenu` 组件（`@/components/commandMenu/index.vue`）。支持 Ctrl+K（Windows）/ Cmd+K（Mac）快捷键。

---

## 十二、依赖版本

| 依赖 | 版本 | 用途 |
|------|------|------|
| tailwindcss | ^3.4.10 | 工具类 CSS |
| element-plus | ^2.8.5 | UI 组件库 |
| sass | ^1.78.0 | SCSS 编译（modern-compiler API） |
| @vueuse/core | ^11.0.3 | `useDark()`、`usePreferredDark()`、`useDebounceFn()` |
| screenfull | ^6.0.2 | 全屏切换 |
| prettier-plugin-tailwindcss | ^0.6.11 | TailwindCSS class 排序 |
| vue-i18n | ^11.0.0-rc.1 | 菜单标题国际化 |

Vite SCSS 配置（`vite.config.js`）：

```js
css: {
  preprocessorOptions: {
    scss: { api: 'modern-compiler' }
  }
}
```

---

## 十三、注意事项和常见问题

### 样式优先级

1. **TailwindCSS `important: true`**：所有 Tailwind utility class 自带 `!important`。在 `<style scoped>` 中写的自定义样式如需覆盖 Tailwind，必须也使用 `!important`。

2. **Element Plus 样式覆盖**：需要使用 `::v-deep()` 穿透 scoped 样式，或在全局样式文件（如 `element_visiable.scss`）中覆盖。

3. **暗黑模式样式**：务必同时添加 `dark:` variant。全局工具类（如 `.hab-table-box`）已内置暗黑适配，直接使用即可。

### 布局开发

4. **新增页面必须支持暗黑模式**：使用 `bg-white dark:bg-slate-900`、`text-slate-700 dark:text-slate-300` 等成对 class。避免硬编码颜色值。

5. **移动端降级**：所有布局模式在移动端统一为 normal 侧边栏模式。自定义布局组件时需检查 `device` 状态。

6. **侧边栏宽度不要硬编码**：使用 `config.layout_side_width` 和 `config.layout_side_collapsed_width`，保证设置面板的调整能生效。

### 标签页

7. **标签唯一性**：由 `name + query + params` 三者共同决定。同名路由但不同参数会创建不同标签。

8. **keep-alive 缓存**：组件必须设置 `defineOptions({ name: 'XxxComponent' })` 才能被正确缓存。name 必须与路由配置中的 `name` 一致。

9. **关闭当前页**：在业务代码中使用 `emitter.emit('closeThisPage')` 而非手动操作路由。

### 主题色

10. **预设色列表修改**：在 `setting/index.vue` 的 `colors` 数组中修改。不影响运行时动态切换。

11. **Element Plus 基础主题色与运行时主题色**：`style/element/index.scss` 中通过 `@forward` 设置编译时默认色 `#4d70ff`，运行时被 `setBodyPrimaryColor()` 的 CSS 变量覆盖。两者需保持合理默认值。

### 性能

12. **页面过渡动画**：`none` 选项可完全禁用动画，适用于低端设备或用户偏好。

13. **标签页 sessionStorage 同步**：每次路由变化和标签操作都会写入 sessionStorage，标签过多时可能有性能影响。

14. **色弱/灰色模式**：通过 CSS `filter` 实现，会触发整页重绘。建议仅在需要时开启。

### 自定义扩展

15. **添加新的过渡动画**：在 `transition.scss` 中定义 `.xxx-enter-active` / `.xxx-leave-active` 等类，然后在 `setting/index.vue` 的动画选择器中添加 `<el-option>`。

16. **添加全局布局配置项**：在 `app.js` 的 `config` 中添加字段和默认值 -> 添加 toggle 方法 -> 在 `setting/index.vue` 中添加 UI 控件 -> 在布局组件中通过 `storeToRefs(appStore)` 使用。

17. **自定义 Element Plus 组件样式**：在 `element_visiable.scss` 中添加覆盖规则，可利用 Tailwind `@apply` 简化编写。
