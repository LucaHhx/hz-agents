# 前端架构与核心模块

## 1. 技术栈概要

| 类别 | 技术 | 版本 | 说明 |
|------|------|------|------|
| 框架 | Vue 3 | ^3.5.7 | 使用 Composition API (`<script setup>`) |
| 构建工具 | Vite | ^5.4.3 | 支持多环境配置 (development/dev/mini/remote/production) |
| UI 组件库 | Element Plus | ^2.8.5 | 主 UI 库，含图标包 `@element-plus/icons-vue` |
| 辅助 UI | Ant Design Vue | ^4.2.6 | 仅用于 `ConfigProvider` 提供暗色主题算法 |
| 状态管理 | Pinia | ^2.2.2 | 5 个 store 模块 |
| 路由 | Vue Router | ^4.4.3 | Hash 模式，支持动态路由 |
| CSS | TailwindCSS | ^3.4.10 | 配合 SCSS 预处理 |
| HTTP | Axios | ^1.7.7 | 封装 `request.js`，自带拦截器 |
| 国际化 | Vue I18n | ^11.0.0-rc.1 | 翻译内容从后端 API 加载 |
| 工具库 | VueUse | ^11.0.3 | `useDark`、`useStorage`、`useCookies` 等 |
| 图表 | ECharts | 5.5.1 | 配合 `vue-echarts` |
| 富文本 | WangEditor | ^5.1.23 | `@wangeditor/editor-for-vue` |
| 事件总线 | mitt | ^3.0.1 | 轻量级事件发布/订阅 |

## 2. 应用启动流程

入口文件 `src/main.js` 定义了一个 `initApp` 异步函数，按以下顺序初始化：

```
main.js
  ├─ 1. 导入样式（Element Plus CSS、暗色主题 CSS、自定义 SCSS）
  ├─ 2. createApp(App)
  ├─ 3. app.use(run)          ← core/hab.js → core/global.js：注册全局组件
  │     ├─ 注册所有 Element Plus 图标为全局组件
  │     ├─ 注册 SvgIcon 组件
  │     └─ 扫描 src/assets/icons/ 和 src/plugin/**/assets/icons/ 下所有 SVG
  ├─ 4. app.use(ElementPlus)   ← 注册 Element Plus
  ├─ 5. app.use(store)         ← Pinia 状态管理
  ├─ 6. app.use(auth)          ← v-auth 权限指令
  ├─ 7. app.use(router)        ← Vue Router
  ├─ 8. setupI18n(app)         ← 从 /api/translation/messages 加载翻译
  │     ├─ 创建 vue-i18n 实例（Composition API 模式）
  │     ├─ 配置 datetimeFormats（zh-CN / en-US）
  │     └─ 挂载 $serverDate 全局方法
  ├─ 9. setI18n(i18n)          ← 将 i18n 实例传入 request.js 供错误翻译
  ├─ 10. app.mount('#app')
  └─ 11. permission.js 路由守卫已在 import 时注册生效
```

### 根组件 App.vue

根组件做了两件事：

- **Ant Design Vue ConfigProvider**：根据 `appStore.isDark` 切换 `darkAlgorithm` / `defaultAlgorithm`，将 token 色值映射到 Element Plus CSS 变量。
- **Element Plus ConfigProvider**：根据 `appStore.config.language` 动态切换 `locale`（`zh-cn` / `en`）。

## 3. 路由系统

### 3.1 静态路由

在 `src/router/index.js` 中定义，使用 **Hash 模式** (`createWebHashHistory`)：

| 路径 | name | 说明 |
|------|------|------|
| `/` | - | 重定向到 `/login` |
| `/init` | `Init` | 系统初始化页面 |
| `/login` | `Login` | 登录页 |
| `/person` | `person` | 个人设置（keepAlive） |
| `/:catchAll(.*)` | - | 404 兜底 |

### 3.2 动态路由

动态路由由后端 API `asyncMenu()` 返回，处理流程在 `routerStore.SetAsyncRouter()` 中：

1. 调用 `asyncMenu()` 获取菜单树 `menus`。
2. 追加一个隐藏的 `Reload` 路由（用于强制刷新页面）。
3. `formatRouter()` 递归遍历菜单树：
   - 将 `btns`（按钮权限）写入 `item.meta.btns`。
   - 将 `columns`（列权限）写入 `item.meta.cols`。
   - 将 `hidden` 写入 `item.meta.hidden`。
   - 所有路由默认 `keepAlive: true`。
   - `defaultMenu === true` 的顶层路由进入 `notLayoutRouterArr`（不嵌套 layout）。
4. 构建 `baseRouter`：所有动态路由挂在 `/layout` 下（`view/layout/index.vue`）。
5. `asyncRouterHandle(baseRouter)` 将字符串 `component` 转为实际组件：
   - `view/**` 路径 → `import.meta.glob('../view/**/*.vue')` 匹配。
   - `plugin/**` 路径 → `import.meta.glob('../plugin/**/*.vue')` 匹配。
6. `KeepAliveFilter()` 收集需要缓存的路由名称。
7. 通过 `router.addRoute()` 注册到路由表。

### 3.3 权限守卫逻辑（permission.js）

**白名单**：`['Login', 'Init', 'ScanUpload']`，这些路由不需要登录即可访问。

**beforeEach 守卫完整流程**：

```
beforeEach(to, from)
  ├─ NProgress.start()
  ├─ 设置 to.meta.matched（用于面包屑等）
  ├─ handleKeepAlive(to)  ← 处理嵌套 keepAlive 组件
  ├─ 设置 document.title
  │
  ├─ if to.meta.client → 放行（客户端页面，无需鉴权）
  │
  ├─ if 白名单路由 →
  │   ├─ 若有 token 且路由未加载 → setupRouter()
  │   └─ 放行
  │
  ├─ if 有 token →
  │   ├─ if needToHome → 重定向到 /
  │   ├─ if 路由未加载 →
  │   │   ├─ setupRouter()（并行加载路由 + 用户信息）
  │   │   ├─ 成功 → 重定向到 defaultRouter 或 404
  │   │   └─ 失败 → 跳转 Login
  │   └─ if 路由已加载 →
  │       ├─ 匹配到路由 → 放行
  │       └─ 未匹配 → 404
  │
  └─ 无 token → 跳转 Login（带 redirect 参数）
```

**setupRouter 函数**：并行执行 `routerStore.SetAsyncRouter()` 和 `userStore.GetUserInfo()`，然后逐条 `router.addRoute()`。

**afterEach**：滚动主内容区到顶部，关闭 NProgress。

## 4. 状态管理（Pinia）

共 5 个 store 模块，全部使用 Composition API 风格（`setup` 语法）。

### 4.1 useAppStore (`app.js`)

应用全局配置，管理主题、布局、语言等。

| 状态 | 类型 | 说明 |
|------|------|------|
| `device` | ref | 设备类型（`mobile` / 空） |
| `isDark` | ref | 暗色模式状态（由 `useDark` 驱动） |
| `config.primaryColor` | reactive | 主题色，默认 `#3b82f6` |
| `config.darkMode` | reactive | 暗色模式策略：`auto` / `dark` / `light` |
| `config.language` | reactive | 当前语言，默认 `en-US` |
| `config.showTabs` | reactive | 是否显示标签页 |
| `config.layout_side_width` | reactive | 侧边栏展开宽度，默认 256 |
| `config.layout_side_collapsed_width` | reactive | 侧边栏折叠宽度，默认 80 |
| `config.show_watermark` | reactive | 是否显示水印 |
| `config.side_mode` | reactive | 侧边栏模式：`normal` |
| `config.transition_type` | reactive | 页面过渡动画类型：`slide` |
| `config.weakness` | reactive | 色弱模式 |
| `config.grey` | reactive | 灰色模式 |
| `config.messages` | reactive | i18n 翻译消息缓存 |
| `config.table_hight_enable` | reactive | 表格固定高度开关 |
| `config.table_hight` | reactive | 表格固定高度值，默认 588 |

watchEffect 自动响应：暗色模式跟随系统、主题色更新、色弱/灰色模式切换。

### 4.2 useUserStore (`user.js`)

用户认证与信息管理。

| 方法/状态 | 说明 |
|-----------|------|
| `userInfo` | 用户信息（uuid, nickName, headerImg, authority, language, type） |
| `token` | computed，优先 localStorage，fallback cookie |
| `LoginIn(loginInfo)` | 登录：调用 API → 设置 token → 加载路由 → 跳转 defaultRouter |
| `LoginOut()` | 登出：调用 jwt 黑名单 API → 清除存储 → 跳转登录页并 reload |
| `GetUserInfo()` | 获取用户信息并更新 store |
| `setUserInfo(val)` | 设置用户信息，同时从 `originSetting` 同步应用配置到 appStore |
| `ClearStorage()` | 清除 token、sessionStorage、localStorage 中的 originSetting |
| `NeedInit()` | 清除存储后跳转到系统初始化页 |

**登录特殊返回码**：
- `google_auth_required` (code: 2) — 需要 Google 二次验证
- `unbound_security_verification` (code: 3) — 未绑定安全验证
- `passkey_required` (code: 4) — 需要 Passkey 认证

Token 持久化使用 `@vueuse/core` 的 `useStorage`（localStorage）和 `@vueuse/integrations` 的 `useCookies`（cookie），双写保证兼容性。

### 4.3 useRouterStore (`router.js`)

动态路由与菜单管理。

| 方法/状态 | 说明 |
|-----------|------|
| `asyncRouters` | 动态路由数组 |
| `asyncRouterFlag` | 路由加载标记（递增计数器） |
| `keepAliveRouters` | 需要缓存的路由组件名列表 |
| `routeMap` | 路由名称 → 路由对象的映射表 |
| `topMenu` | 顶部菜单数组（一级菜单，不含 children） |
| `leftMenu` | 左侧菜单数组（当前选中一级菜单的子菜单） |
| `topActive` | 当前激活的顶部菜单名称（持久化到 sessionStorage） |
| `SetAsyncRouter()` | 从后端加载菜单并注册路由 |
| `setLeftMenu(name)` | 切换顶部菜单时更新左侧菜单 |

菜单结构为**两级导航**：顶部一级菜单 + 左侧二级菜单树。`watchEffect` 自动在路由变化时同步 topActive。

### 4.4 useDictionaryStore (`dictionary.js`)

字典数据缓存，避免重复请求。

| 方法/状态 | 说明 |
|-----------|------|
| `dictionaryMap` | 字典类型 → 选项列表的映射 `{ type: [{label, value, extend}] }` |
| `getDictionary(type)` | 按类型获取字典，有缓存则直接返回，否则调 `findSysDictionary` API |

配合工具函数 `utils/dictionary.js`：
- `getDict(type)` — 获取字典数据（async）
- `showDictLabel(dict, code)` — 根据 value 查找对应 label

### 4.5 useParamsStore (`params.js`)

系统参数缓存，结构与字典 store 类似。

| 方法/状态 | 说明 |
|-----------|------|
| `paramsMap` | 参数 key → value 的映射 |
| `getParams(key)` | 按 key 获取参数值，有缓存则直接返回，否则调 `getSysParam` API |

## 5. HTTP 请求封装（request.js）

基于 Axios 封装，文件位于 `src/utils/request.js`。

### 5.1 实例创建

```javascript
const service = axios.create({
  baseURL: import.meta.env.VITE_BASE_API,  // 从 .env 文件读取
  timeout: 99999
})
```

### 5.2 请求拦截器

每个请求自动：
1. **显示 Loading**：延迟 400ms 后在 `#hab-base-load-dom` 元素上展示加载动画（可通过 `config.donNotShowLoading: true` 跳过）。
2. **注入 Headers**：
   - `Content-Type: application/json`
   - `x-token`: 从 userStore 获取
   - `x-user-id`: 从 userStore.userInfo.ID 获取
3. 支持自定义 `config.loadingOption` 覆盖 Loading 配置。

### 5.3 响应拦截器

**成功响应 (HTTP 2xx)**：
- 关闭 Loading。
- 检测响应头 `new-token`，自动刷新本地 token。
- `response.data.code === 0` 或 `undefined` → 返回 `response.data`。
- 其他 code → **i18n 错误翻译**：尝试 `i18n.global.t('error.{code}.{msg}')`，若翻译键不存在（返回值等于键本身）则 fallback 到 `response.data.data` 或 `response.data.msg`，最后 ElMessage 弹出错误提示。

**网络/HTTP 错误**：
- **无 response**（网络错误）→ ElMessageBox 提示检测到请求错误。
- **401**（token 过期）→ 提示重新登录，确认后清除存储跳转登录页。
- **404** → 提示接口不存在。
- **500** → 提示服务器错误，确认后清除缓存跳转登录页。

所有错误提示文案均通过 i18n 翻译。

### 5.4 使用方式

```javascript
import service from '@/utils/request'

// 普通请求
export const getList = (data) => service({ url: '/api/xxx/list', method: 'post', data })

// 不显示 loading 的请求
export const silentGet = (data) => service({
  url: '/api/xxx/info',
  method: 'get',
  params: data,
  donNotShowLoading: true
})
```

## 6. 权限系统前端实现

### 6.1 v-auth 指令（基于角色 ID）

文件：`src/directive/auth.js`

根据当前用户的 `authorityId` 判断元素是否显示：

```html
<!-- 仅角色 ID 为 1 的用户可见 -->
<el-button v-auth="1">管理操作</el-button>

<!-- 角色 ID 为 1 或 2 的用户可见 -->
<el-button v-auth="[1, 2]">多角色可见</el-button>

<!-- 角色 ID 为 1 的用户不可见（取反） -->
<el-button v-auth.not="1">非管理员可见</el-button>
```

实现原理：在 `mounted` 钩子中，将 binding.value 与 `userInfo.authorityId` 比对，不匹配则 `el.parentNode.removeChild(el)` 直接移除 DOM 元素。

### 6.2 按钮权限（btnAuth）

文件：`src/utils/btnAuth.js`

基于后端菜单返回的 `btns` 字段，每个路由在 `meta.btns` 中存储该页面的按钮权限对象。

```javascript
import { useBtnAuth } from '@/utils/btnAuth'

// 在页面组件中使用
const btns = useBtnAuth()
// btns 即当前路由 meta.btns 的内容

// 跨路由查询按钮权限
import { useBtnAuthForRoute } from '@/utils/btnAuth'
const otherBtns = useBtnAuthForRoute('routeName')
```

`btns` 对象的 key 为按钮标识，在模板中配合 `v-if` 控制显示：

```html
<el-button v-if="btns['add']">新增</el-button>
<el-button v-if="btns['delete']">删除</el-button>
```

### 6.3 列权限（colAuth）

后端菜单返回的 `columns` 字段写入 `meta.cols`，用于控制表格列的显示/隐藏。在 `formatRouter` 中通过 `item.meta.cols = item.columns` 赋值。页面中可从路由 meta 读取列权限信息来动态渲染表格列。

## 7. 国际化实现方式

文件：`src/i18n/index.js`

### 7.1 翻译内容加载

翻译内容**不是静态 JSON 文件**，而是从后端 API `/api/translation/messages` 动态加载。返回格式：

```json
{
  "data": {
    "messages": { "zh-CN": {...}, "en-US": {...} },
    "timeZone": "Asia/Bangkok"
  }
}
```

加载后缓存到 `appStore.config.messages`。

### 7.2 vue-i18n 配置

- **模式**：Composition API（`legacy: false`）
- **默认语言**：`zh-CN`
- **回退语言**：`zh-CN`
- **静默警告**：所有翻译警告已禁用（`silentTranslationWarn`、`missingWarn`、`fallbackWarn`）
- **日期格式化**：内置 `zh-CN` 和 `en-US` 的 short / medium / long / full / date 五种日期格式，时区从后端获取。

### 7.3 全局日期方法

`$serverDate(date, format, timeZone)` 挂载在全局属性上，支持：
- 数字类型：8 位整数解析为 `YYYYMMDD`，其余视为 Unix 时间戳（秒）
- 字符串类型：直接 `new Date()`
- format 参数对应 datetimeFormats 中定义的格式名称

### 7.4 语言切换

`App.vue` 中通过 `watchEffect` 监听 `appStore.config.language`，同步更新 `vue-i18n` 的 locale 和 Element Plus 的 locale。

## 8. 前端目录约定

```
web/src/
├── api/                    # API 接口定义（按功能模块拆分文件）
│   ├── user.js             # 用户相关 API（login, getUserInfo）
│   ├── menu.js             # 菜单 API（asyncMenu）
│   ├── jwt.js              # JWT API（jsonInBlacklist）
│   ├── sysDictionary.js    # 字典 API
│   ├── sysParams.js        # 系统参数 API
│   └── ...                 # 业务模块 API
│
├── view/                   # 页面组件（按功能模块划分子目录）
│   ├── login/              # 登录页
│   ├── layout/             # 布局框架（包含侧边栏、顶栏、标签页等）
│   ├── dashboard/          # 仪表盘
│   ├── system/             # 系统管理页面
│   ├── superAdmin/         # 超级管理员页面
│   └── [业务模块]/         # 业务页面
│
├── components/             # 通用组件
│   └── svgIcon/            # SVG 图标组件
│
├── pinia/
│   ├── index.js            # Pinia 实例创建与 store 导出
│   └── modules/            # 5 个 store 模块
│
├── router/
│   └── index.js            # 静态路由定义
│
├── utils/
│   ├── request.js          # Axios 封装
│   ├── asyncRouter.js      # 动态路由组件解析
│   ├── btnAuth.js          # 按钮权限工具
│   ├── dictionary.js       # 字典工具
│   ├── bus.js              # mitt 事件总线
│   ├── page.js             # 页面标题工具
│   └── format.js           # 格式化工具（主题色等）
│
├── directive/
│   └── auth.js             # v-auth 权限指令
│
├── core/
│   ├── hab.js              # 框架初始化插件入口
│   ├── global.js           # 全局组件注册（图标等）
│   └── config.js           # 全局配置
│
├── i18n/
│   └── index.js            # 国际化初始化
│
├── assets/
│   └── icons/              # SVG 图标文件
│
├── style/                  # 全局样式（SCSS）
├── styles/                 # 额外样式（CSS）
├── hooks/                  # 自定义 composables
├── plugin/                 # 插件目录（独立功能模块，可含 assets/icons）
├── permission.js           # 路由守卫
├── main.js                 # 入口文件
├── App.vue                 # 根组件
└── pathInfo.json           # Vite 插件生成的组件路径映射
```

### 命名约定

- **API 文件**：与后端模块对应，驼峰命名（如 `sysDictionary.js`）。
- **View 目录**：按功能模块划分，目录名小写。每个页面通常是 `[模块]/[功能].vue` 或 `[模块]/index.vue`。
- **组件路径**：动态路由中 `component` 字段为相对于 `src/` 的路径字符串（如 `view/system/user/user.vue`），由 `asyncRouterHandle` 自动解析。

## 9. 新增业务页面步骤指南

### 第 1 步：创建 API 文件

在 `src/api/` 下新建文件，封装后端接口：

```javascript
// src/api/myModule.js
import service from '@/utils/request'

export const getMyModuleList = (data) => {
  return service({
    url: '/api/myModule/getMyModuleList',
    method: 'post',
    data
  })
}

export const createMyModule = (data) => {
  return service({
    url: '/api/myModule/createMyModule',
    method: 'post',
    data
  })
}
```

### 第 2 步：创建页面组件

在 `src/view/` 下按模块创建目录和 Vue 文件：

```
src/view/myModule/
  └── myModule.vue
```

组件使用 `<script setup>` 语法，通过 `useBtnAuth()` 获取按钮权限：

```vue
<template>
  <div>
    <el-button v-if="btns['add']" @click="handleAdd">{{ $t('common.add') }}</el-button>
    <!-- 表格、表单等 -->
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { getMyModuleList } from '@/api/myModule'
import { useBtnAuth } from '@/utils/btnAuth'

const btns = useBtnAuth()
const tableData = ref([])

const getList = async () => {
  const res = await getMyModuleList({ page: 1, pageSize: 10 })
  if (res.code === 0) {
    tableData.value = res.data.list
  }
}
getList()
</script>
```

### 第 3 步：后端配置菜单

在后端管理界面（系统管理 → 菜单管理）中添加菜单项：
- **路由 name**：唯一标识，如 `myModule`
- **路由 path**：如 `myModule`
- **文件路径 (component)**：`view/myModule/myModule.vue`
- **按钮权限 (btns)**：配置该页面可用的操作按钮
- **列权限 (columns)**：配置该页面可见的表格列

菜单保存后，用户刷新页面即可通过动态路由访问新页面，**无需修改前端路由配置文件**。

### 第 4 步：字典数据（可选）

如页面涉及下拉选项等枚举值，通过字典系统获取：

```javascript
import { getDict } from '@/utils/dictionary'

const statusOptions = ref([])
const initDict = async () => {
  statusOptions.value = await getDict('myModuleStatus')
}
initDict()
```

### 第 5 步：国际化（可选）

翻译内容在后端管理，通过 `useI18n()` 的 `t()` 函数使用：

```javascript
import { useI18n } from 'vue-i18n'
const { t } = useI18n()
// 模板中：{{ $t('myModule.title') }}
```

## 10. 开发命令

所有命令在 `web/` 目录下执行：

| 命令 | 说明 | 对应 .env 文件 |
|------|------|----------------|
| `npm run serve` | 开发模式启动（默认） | `.env.development` |
| `npm run dev` | 开发模式启动（dev 环境） | `.env.dev` |
| `npm run mini` | 开发模式启动（mini 环境） | `.env.mini` |
| `npm run remote` | 开发模式启动（远程环境） | `.env.remote` |
| `npm run build` | 生产构建 | `.env.production` |
| `npm run preview` | 预览生产构建结果 | - |

### 环境变量（.env 文件）

关键变量：
- `VITE_BASE_API`：API 请求前缀（如 `/api`）
- `VITE_BASE_PATH`：后端服务地址
- `VITE_SERVER_PORT`：后端服务端口
- `VITE_CLI_PORT`：前端开发服务器端口
- `VITE_EDITOR`：DevTools 编辑器配置
- `VITE_POSITION`：DevTools 开关（`open` 启用）
- `VITE_DEFAULT_LOCALE`：默认语言

### Vite 代理配置

开发模式下，`VITE_BASE_API` 路径自动代理到 `VITE_BASE_PATH:VITE_SERVER_PORT`，并去除前缀。例如前端请求 `/api/user/login` 会被代理到 `http://localhost:8888/user/login`。

### 构建产物

- 输出目录：`dist/`
- 静态资源带 hash 文件名（格式：`087AC4D233B64EB0[name].[hash].[ext]`）
- 生产构建会移除所有 `console` 和 `debugger` 语句
- 不生成 sourcemap
