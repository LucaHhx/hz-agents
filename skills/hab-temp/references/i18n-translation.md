# 国际化翻译系统参考文档

## 1. 架构总览

系统采用前后端分离的国际化架构：

- **后端**：翻译内容以 JSON 文件形式存储在 `server/translation/` 目录，通过 `TranslationApi` 提供 REST API 管理翻译文件
- **前端**：基于 `vue-i18n`（Composition API 模式），应用启动时从后端 `/api/translation/messages` 接口加载所有翻译内容
- **管理界面**：位于 `web/src/view/systemTools/translation/`，提供可视化的翻译编辑、语言包管理功能

核心数据流：
```
后端 JSON 文件 → TranslationApi.GetMessages() → 前端 axios 请求 → vue-i18n messages → 组件中 $t() / useI18n()
```

## 2. 后端翻译文件组织

### 目录结构

```
server/translation/
  zh-CN/                    # 中文（基准语言）
    common.json             # 通用文本（按钮、状态等）
    login.json              # 登录页面
    menu.json               # 菜单名称
    error.json              # 错误消息（按错误码分组）
    system.json             # 系统管理
    user.json               # 用户管理
    settings.json           # 设置
    superAdmin.json         # 超级管理员
    autoCode.json           # 自动化代码
    installPlugin.json      # 插件安装
    about.json              # 关于页面
    apis.json               # API 管理
    enum.json               # 枚举值
    merchant.json           # 商户管理
    business/               # 业务模块翻译子目录
      order.json
      apiTestItem.json
      sysDataFilter.json
      sysTableColumns.json
  en-US/                    # 英文
    (与 zh-CN 同结构，但可能缺少部分文件/键)
  sync.js                   # 翻译同步检查脚本
```

### JSON 文件格式

翻译文件为标准 JSON，支持平铺和嵌套两种格式：

**平铺格式**（如 `login.json`）：
```json
{
    "login": "登录",
    "username": "请输入用户名",
    "password": "请输入密码",
    "captchaRule": "请输入{length}位验证码"
}
```

**嵌套格式**（如 `common.json` 中的 `request` 部分）：
```json
{
    "add": "添加",
    "request": {
        "apiError": "接口报错",
        "error401": "错误码: 401 错误信息:",
        "error404Detail": "错误码 404：此类错误多为接口未注册..."
    }
}
```

**错误码格式**（`error.json`）：按错误码分组，键为错误码数字：
```json
{
    "0": "操作成功",
    "1000": {
        "invalid_password": "密码错误",
        "user_not_found": "用户不存在,或密码错误"
    },
    "1002": {
        "create": "创建失败",
        "delete": "删除失败"
    }
}
```

### 翻译同步检查脚本

`sync.js` 是一个 Node.js 脚本，用于对比 zh-CN 和 en-US 之间缺失的翻译键。运行方式：
```bash
cd server/translation && node sync.js
```
输出格式为 `文件路径 | 键名 | 中文值`。

## 3. 前端 i18n 配置和使用方式

### 初始化配置

入口文件 `web/src/i18n/index.js` 中通过 `setupI18n()` 完成初始化：

1. 通过 `axios.get('/api/translation/messages')` 从后端加载翻译内容和时区
2. 将翻译消息存入 pinia store（`appStore.setMessages()`）
3. 使用 `createI18n()` 创建 i18n 实例

关键配置参数：
- `legacy: false` — 使用 Composition API 模式
- `locale: 'zh-CN'` — 默认语言
- `fallbackLocale: 'zh-CN'` — 回退语言
- `silentTranslationWarn: true` — 禁用翻译缺失警告
- `datetimeFormats` — 配置了 zh-CN 和 en-US 的日期时间格式（short/medium/long/full/date），时区从后端获取

### 日期格式化

i18n 实例扩展了全局 `$serverDate` 方法，支持：
- Unix 时间戳（秒）
- 8 位数字日期（如 `20240101`）
- 字符串日期

使用方式：`$serverDate(timestamp, 'long')`

### GetMessages 接口数据结构

后端 `GetMessages` 接口返回的数据格式：
```json
{
    "messages": {
        "zh-CN": {
            "common": { "add": "添加", ... },
            "login": { "login": "登录", ... },
            "business": {
                "order": { ... },
                "apiTestItem": { ... }
            }
        },
        "en-US": { ... }
    },
    "timeZone": "Asia/Bangkok"
}
```

`business/` 子目录下的文件会被合并到 `business` 键下，其他文件以文件名（去掉 `.json`）作为键。

## 4. 翻译管理界面功能

管理界面位于 `web/src/view/systemTools/translation/index.vue`，提供以下功能：

### 左侧面板 - 文件树
- 以树形结构展示所有语言包及其下属的 JSON 文件
- 支持展开/折叠，点击叶子节点加载文件内容
- 每个语言节点提供操作按钮：
  - **删除**（zh-CN 和 en-US 不可删除）
  - **下载**：将语言包所有文件打包为 zip 下载
  - **上传**：上传 zip 文件覆盖现有翻译

### 右侧面板 - JSON 编辑器
- textarea 编辑器，支持直接编辑 JSON 内容
- **保存**：验证 JSON 格式后提交到后端
- **撤回**：重新从后端加载原始内容
- 支持 Tab/Shift+Tab 缩进操作

### 新增语言
- 通过对话框选择源语言并输入目标语言代码（如 `ja-JP`）
- 调用 `copyLanguage` 接口复制整个语言包目录

## 5. 如何添加新语言

### 方法一：通过管理界面
1. 打开翻译管理页面
2. 点击左上角"新增"按钮
3. 选择源语言（如 `zh-CN`）
4. 输入目标语言代码（如 `ja-JP`、`ko-KR`）
5. 系统会复制源语言的所有文件到新语言目录
6. 逐个文件编辑翻译内容

### 方法二：手动添加
1. 在 `server/translation/` 下创建新目录（如 `ja-JP/`）
2. 复制 `zh-CN/` 下所有 JSON 文件到新目录
3. 翻译各文件内容
4. 重启服务或重新加载页面即可生效

### 注意事项
- 语言代码应遵循 BCP 47 标准（如 `zh-CN`、`en-US`、`ja-JP`）
- 如需日期格式化支持，需要在 `i18n/index.js` 的 `datetimeFormats` 中添加对应配置
- `zh-CN` 是基准语言，完整性检查以它为基准

## 6. 如何添加业务翻译

### 添加新的翻译文件
1. 在 `server/translation/zh-CN/` 下创建 JSON 文件（如 `myModule.json`）
2. 在 `server/translation/en-US/` 下创建同名文件
3. 前端通过 `$t('myModule.keyName')` 使用

### 添加业务子目录翻译
1. 在 `server/translation/zh-CN/business/` 下创建文件（如 `product.json`）
2. 前端通过 `$t('business.product.keyName')` 使用

### 翻译键命名规范
- 使用 camelCase 命名
- 按功能模块分文件
- 支持带参数的翻译：`"exportProgressText": "正在导出第 {current}/{total} 页"`

## 7. 错误消息翻译机制

`error.json` 采用错误码分组的结构，用于将后端返回的错误码和错误键翻译为用户可读的消息。

结构示例：
```json
{
    "0": "操作成功",
    "1000": {
        "invalid_password": "密码错误",
        "user_disabled": "用户已被禁用"
    },
    "1001": {
        "invalid_params": "无效的参数",
        "no_permission": "没有权限"
    },
    "1002": {
        "create": "创建失败",
        "delete": "删除失败",
        "update": "更新失败"
    }
}
```

错误码分类：
- `0` — 操作成功
- `1000` — 用户相关错误（密码、权限、Google Auth）
- `1001` — 通用业务错误（参数、数据、权限）
- `1002` — CRUD 操作失败
- `1051-1054` — 验证码和权限相关
- `7` — 权限不足

前端 `common.json` 中的 `request` 对象处理 HTTP 层面的错误翻译：
```json
{
    "request": {
        "error401": "错误码: 401 错误信息:",
        "error404Detail": "错误码 404：此类错误多为接口未注册...",
        "error500": "错误码 500：此类错误内容常见于后台panic..."
    }
}
```

## 8. 模板中使用翻译的方式

### Options API / Template 中使用 `$t`

```vue
<template>
  <!-- 简单翻译 -->
  <span>{{ $t('common.add') }}</span>

  <!-- 带参数翻译 -->
  <span>{{ $t('login.captchaRule', { length: 6 }) }}</span>

  <!-- 属性绑定 -->
  <el-input :placeholder="$t('common.pleaseEnter')" />

  <!-- 嵌套键 -->
  <span>{{ $t('common.request.apiError') }}</span>
</template>
```

### Composition API 中使用 `useI18n`

```vue
<script setup>
import { useI18n } from 'vue-i18n'

const { t, locale } = useI18n()

// 翻译
const message = t('common.success')

// 切换语言
locale.value = 'en-US'
</script>
```

### 日期格式化

```vue
<template>
  <!-- 使用全局 $serverDate -->
  <span>{{ $serverDate(row.createdAt, 'long') }}</span>
  <span>{{ $serverDate(row.date, 'short') }}</span>
</template>
```

格式选项：`short`（年月日）、`medium`（+时分）、`long`（+秒）、`full`（完整格式）、`date`（仅日期）。

## 9. API 接口一览

前端 API 封装位于 `web/src/api/system/translation.js`，主要接口：

| 接口 | 方法 | 说明 |
|------|------|------|
| `/translation/tree` | GET | 获取翻译文件树结构 |
| `/translation/file` | GET | 获取单个文件内容 |
| `/translation/update` | POST | 更新翻译内容 |
| `/translation/copy` | POST | 复制语言包 |
| `/translation/batch` | POST | 批量更新翻译 |
| `/translation/compare` | POST | 对比两个语言的翻译差异 |
| `/translation/check` | GET | 检查翻译完整性 |
| `/translation/export-language` | POST | 导出语言包（zip） |
| `/translation/delete-language` | POST | 删除语言包 |
| `/translation/upload-language` | POST | 上传语言包（zip） |
| `/api/translation/messages` | GET | 获取所有翻译消息（前端初始化用） |

## 10. 注意事项

1. **zh-CN 是基准语言**，不可删除。完整性检查（`CheckIntegrity`）以 zh-CN 为基准对比其他语言的缺失键、多余键和空值
2. **翻译文件必须是合法 JSON**，后端在保存时会验证格式。保存时会自动使用 4 空格缩进格式化
3. **前端翻译在应用启动时一次性加载**，修改翻译文件后需要刷新页面才能看到效果
4. **business 子目录特殊处理**：`business/` 下的文件会被合并到 `business` 命名空间下，而非顶层
5. **时区配置**：前端日期格式化的时区来自后端 `HAB_CONFIG.System.TimeZone` 配置
6. **上传语言包时只会覆盖已存在的文件**，不会创建新文件（`UploadLanguage` 中的逻辑）
7. **翻译支持参数插值**，使用 `{paramName}` 语法，在调用 `$t()` 时传入对应参数对象
8. **配置路径**：翻译文件目录通过 `global.HAB_CONFIG.System.TranslationDir` 配置
