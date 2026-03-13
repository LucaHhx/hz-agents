# API 管理 / 字典 / 系统参数 参考文档

本文档覆盖 hz-admin-base 中三个基础设施模块：API 管理、字典系统、系统参数。

---

## 一、API 管理功能

### 1.1 数据模型

API 管理涉及两个模型，均定义在 `server/model/system/sys_api.go`：

**SysApi** — 已注册的 API 记录：

| 字段 | 类型 | 说明 |
|------|------|------|
| Path | string | API 路径，如 `/user/getUserList` |
| Description | string | API 中文描述 |
| ApiGroup | string | API 分组名称 |
| Method | string | HTTP 方法：POST(默认) / GET / PUT / DELETE |

表名：`sys_apis`，唯一约束为 `path + method` 组合。

**SysIgnoreApi** — 忽略列表（同步时跳过的 API）：

| 字段 | 类型 | 说明 |
|------|------|------|
| Path | string | API 路径 |
| Method | string | HTTP 方法 |
| Flag | bool | 是否忽略（仅运行时使用，gorm:"-" 不入库） |

表名：`sys_ignore_apis`。

### 1.2 API 同步机制

系统在启动时将所有路由注册信息缓存到 `global.HAB_ROUTERS`。同步流程（`SyncApi`）：

1. 从数据库读取已有的 `sys_apis` 记录和 `sys_ignore_apis` 忽略列表
2. 遍历内存中的 `HAB_ROUTERS`，排除在忽略列表中的路由，得到 cacheApis
3. 对比 cacheApis 与数据库 apis：
   - 内存中有、数据库中无 → 放入 `newApis`（待新增）
   - 数据库中有、内存中无 → 放入 `deleteApis`（待删除）
4. 返回 `newApis`、`deleteApis`、`ignoreApis` 三个数组给前端预览
5. 用户确认后调用 `EnterSyncApi`，在事务中批量新增和删除

### 1.3 确认同步（EnterSyncApi）

`EnterSyncApi` 在一个数据库事务中完成：
- 批量创建 `newApis`
- 逐条删除 `deleteApis`，并同步清理对应的 Casbin 权限规则

### 1.4 API 忽略列表

通过 `IgnoreApi` 方法管理：
- `Flag = true`：将该 API 加入忽略表（`sys_ignore_apis` 表插入记录）
- `Flag = false`：从忽略表中移除（物理删除，使用 `Unscoped`）

被忽略的 API 在同步时不会出现在 newApis 中。

### 1.5 CRUD 操作

| 操作 | 路由 | 方法 | 说明 |
|------|------|------|------|
| 创建 | `/api/createApi` | POST | 检查 path+method 唯一性 |
| 删除 | `/api/deleteApi` | POST | 同时清理 Casbin 规则 |
| 批量删除 | `/api/deleteApisByIds` | DELETE | 事务内逐条清理 Casbin |
| 更新 | `/api/updateApi` | POST | 同步更新 Casbin 中的旧路径 |
| 分页查询 | `/api/getApiList` | POST | 支持 path/description/method/apiGroup 筛选 |
| 获取全部 | `/api/getAllApis` | POST | 不分页，受 Casbin 严格鉴权过滤 |
| 按 ID 查询 | `/api/getApiById` | POST | — |
| 获取分组 | `/api/getApiGroups` | GET | 返回 groups 列表和 apiGroupMap |
| 同步预览 | `/api/syncApi` | GET | 返回 newApis/deleteApis/ignoreApis |
| 确认同步 | `/api/enterSyncApi` | POST | 执行同步入库 |
| 忽略 API | `/api/ignoreApi` | POST | 管理忽略列表 |
| 刷新 Casbin | `/api/freshCasbin` | GET | 重新加载 Casbin 策略缓存 |

### 1.6 API 与 Casbin 权限的关系

API 管理和 Casbin 权限深度耦合：

1. **删除 API 时**：调用 `CasbinServiceApp.ClearCasbin(1, path, method)` 清除所有角色对该 API 的访问权限
2. **更新 API 时**：调用 `CasbinServiceApp.UpdateCasbinApi(oldPath, newPath, oldMethod, newMethod)` 将 Casbin 中引用旧路径的规则更新为新路径
3. **获取全部 API 时**：如果启用了 `UseStrictAuth` 且当前角色有父角色，则用 `GetPolicyPathByAuthorityId` 过滤出当前角色有权限的 API 子集
4. **批量同步删除时**：逐条清理被删除 API 的 Casbin 规则

> 关键点：Casbin 的 policy 格式为 `(authorityId, path, method)`，v1 位置是 path，v2 位置是 method。`ClearCasbin(1, path, method)` 表示从 v1 开始匹配。

### 1.7 前端 API 调用

前端 API 封装在 `web/src/api/api.js`，所有方法均通过 `service`（axios 封装）发起请求：

```javascript
import { getApiList, createApi, updateApi, deleteApi, deleteApisByIds,
         getAllApis, syncApi, enterSyncApi, ignoreApi, getApiGroups,
         freshCasbin, getApiById, setAuthApi } from '@/api/api'
```

---

## 二、字典系统

### 2.1 概述

字典系统采用两级结构：**字典（SysDictionary）** + **字典详情（SysDictionaryDetail）**。

- 字典定义一个类型（如 "性别"、"状态"），字典详情定义该类型下的具体选项
- 通过 `SysDictionaryID` 外键关联
- 前端通过 Pinia store 缓存字典数据，避免重复请求

### 2.2 字典模型 — SysDictionary

定义在 `server/model/system/sys_dictionary.go`，表名 `sys_dictionaries`：

| 字段 | 类型 | 说明 | 示例 |
|------|------|------|------|
| Name | string | 字典名称（中文） | "性别" |
| Type | string | 字典类型标识（英文，唯一） | "sex" |
| Status | *bool | 启用状态（指针类型，支持 false） | true |
| Desc | string | 描述 | "用户性别选项" |
| SysDictionaryDetails | []SysDictionaryDetail | 关联的字典详情列表 | — |

唯一约束：`Type` 字段不允许重复，创建和更新时均做校验。

### 2.3 字典详情模型 — SysDictionaryDetail

定义在 `server/model/system/sys_dictionary_detail.go`，表名 `sys_dictionary_details`：

| 字段 | 类型 | 说明 | 示例 |
|------|------|------|------|
| Label | string | 展示值（前端显示文本） | "男" |
| Value | string | 字典值（存储到业务表的值） | "1" |
| Extend | string | 扩展值（附加数据） | "male" |
| Status | *bool | 启用状态 | true |
| Sort | int | 排序标记（升序） | 1 |
| SysDictionaryID | int | 关联的字典 ID（外键） | 5 |

### 2.4 后端字典服务

**DictionaryService**（`server/service/system/sys_dictionary.go`）：

| 方法 | 说明 |
|------|------|
| `CreateSysDictionary` | 创建字典，校验 Type 唯一 |
| `DeleteSysDictionary` | 删除字典，同时级联删除所有字典详情 |
| `UpdateSysDictionary` | 更新字典，如果 Type 变更需校验唯一 |
| `GetSysDictionary(Type, Id, status)` | 按 Type 或 ID 获取单条字典，Preload 详情（仅 status=true、按 sort 排序） |
| `GetSysDictionaryInfoList` | 获取全部字典列表（不分页） |

**DictionaryDetailService**（`server/service/system/sys_dictionary_detail.go`）：

| 方法 | 说明 |
|------|------|
| `CreateSysDictionaryDetail` | 创建字典详情 |
| `DeleteSysDictionaryDetail` | 删除字典详情 |
| `UpdateSysDictionaryDetail` | 更新字典详情（使用 Save 全量更新） |
| `GetSysDictionaryDetail(id)` | 按 ID 获取单条详情 |
| `GetSysDictionaryDetailInfoList` | 分页获取详情列表，支持 label/value/status/sysDictionaryID 筛选 |
| `GetDictionaryList(dictionaryID)` | 按字典 ID 获取全部详情（不分页） |
| `GetDictionaryListByType(type)` | 按字典 Type 获取全部详情（JOIN 查询） |
| `GetDictionaryInfoByValue(dictionaryID, value)` | 按字典 ID + value 获取单条详情 |
| `GetDictionaryInfoByTypeValue(type, value)` | 按字典 Type + value 获取单条详情（JOIN 查询） |

### 2.5 前端字典 API

封装在 `web/src/api/sysDictionary.js`：

| 函数 | 路由 | 方法 | 说明 |
|------|------|------|------|
| `createSysDictionary` | `/sysDictionary/createSysDictionary` | POST | 创建字典 |
| `deleteSysDictionary` | `/sysDictionary/deleteSysDictionary` | DELETE | 删除字典 |
| `updateSysDictionary` | `/sysDictionary/updateSysDictionary` | PUT | 更新字典 |
| `findSysDictionary` | `/sysDictionary/findSysDictionary` | GET | 查询单条（params 传参） |
| `getSysDictionaryList` | `/sysDictionary/getSysDictionaryList` | GET | 获取字典列表 |

### 2.6 前端字典使用方式

#### useDictionaryStore（Pinia）

定义在 `web/src/pinia/modules/dictionary.js`：

```javascript
export const useDictionaryStore = defineStore('dictionary', () => {
  const dictionaryMap = ref({})   // 缓存：{ type: [{label, value, extend}, ...] }

  const getDictionary = async (type) => {
    // 1. 如果缓存中已有该 type 的数据，直接返回
    if (dictionaryMap.value[type] && dictionaryMap.value[type].length) {
      return dictionaryMap.value[type]
    }
    // 2. 否则调用 findSysDictionary API，将结果缓存
    const res = await findSysDictionary({ type })
    // 从 res.data.resysDictionary.sysDictionaryDetails 提取 label/value/extend
  }
})
```

缓存策略：按 type 键缓存，首次请求后不再重复调用接口（页面生命周期内有效）。

#### getDict 工具函数

定义在 `web/src/utils/dictionary.js`：

```javascript
// 使用示例：getDict('sex').then(res => console.log(res))
// 或：const res = await getDict('sex')
export const getDict = async (type) => {
  const dictionaryStore = useDictionaryStore()
  await dictionaryStore.getDictionary(type)
  return dictionaryStore.dictionaryMap[type]
}
```

#### showDictLabel 展示方法

```javascript
// 将字典值转为展示文本
// dict: 字典详情数组, code: 当前值
// showDictLabel(sexDict, '1') → "男"
export const showDictLabel = (dict, code, keyCode = 'value', valueCode = 'label') => {
  // 遍历 dict 构建 {value: label} 映射，返回 code 对应的 label
}
```

### 2.7 如何新增字典类型

**步骤 1：后台管理界面创建字典**

在字典管理页面新增一条字典记录：
- Name: "审核状态"
- Type: "audit_status"（唯一标识，后续代码中使用此值）
- Status: true
- Desc: "业务审核状态"

**步骤 2：添加字典详情**

在该字典下添加详情条目：

| Label | Value | Sort |
|-------|-------|------|
| 待审核 | 0 | 1 |
| 已通过 | 1 | 2 |
| 已驳回 | 2 | 3 |

**步骤 3：前端使用**

```javascript
import { getDict, showDictLabel } from '@/utils/dictionary'

// 获取字典数据
const auditStatusDict = await getDict('audit_status')
// 结果: [{label: '待审核', value: '0'}, {label: '已通过', value: '1'}, ...]

// 在模板中显示文本
const statusText = showDictLabel(auditStatusDict, record.status)
```

**步骤 4：后端使用**

```go
// 按类型获取字典详情列表
details, err := DictionaryDetailServiceApp.GetDictionaryListByType("audit_status")

// 按类型+值获取单条
detail, err := DictionaryDetailServiceApp.GetDictionaryInfoByTypeValue("audit_status", "1")
fmt.Println(detail.Label) // "已通过"
```

---

## 三、系统参数管理

### 3.1 数据模型

定义在 `server/model/system/sys_params.go`，表名 `sys_params`：

| 字段 | 类型 | JSON Key | 说明 | 示例 |
|------|------|----------|------|------|
| Name | string | name | 参数名称（中文描述） | "系统名称" |
| Key | string | key | 参数键（唯一标识） | "sys_name" |
| Value | string | value | 参数值 | "HZ Admin" |
| Desc | string | desc | 参数说明 | "系统显示名称" |

与字典的区别：参数是简单的 Key-Value 键值对，适用于单个配置值；字典是一组选项列表，适用于下拉框、枚举等场景。

### 3.2 后端参数服务

定义在 `server/service/system/sys_params.go`：

| 方法 | 说明 |
|------|------|
| `CreateSysParams(sysParams)` | 创建参数 |
| `DeleteSysParams(ID)` | 按 ID 删除 |
| `DeleteSysParamsByIds(IDs)` | 批量删除 |
| `UpdateSysParams(sysParams)` | 按 ID 更新参数 |
| `GetSysParams(ID)` | 按 ID 获取单条 |
| `GetSysParamsInfoList(info)` | 分页列表，支持 name/key/创建时间范围筛选 |
| `GetSysParam(key)` | **按 key 获取参数**（前端和业务代码最常用） |

`GetSysParam` 是最关键的方法，通过参数的 key 查询完整记录：

```go
func (sysParamsService *SysParamsService) GetSysParam(key string) (param system.SysParams, err error) {
    err = global.HAB_DB.Where(system.SysParams{Key: key}).First(&param).Error
    return
}
```

### 3.3 前端参数 API

封装在 `web/src/api/sysParams.js`：

| 函数 | 路由 | 方法 | 说明 |
|------|------|------|------|
| `createSysParams` | `/sysParams/createSysParams` | POST | 创建 |
| `deleteSysParams` | `/sysParams/deleteSysParams` | DELETE | 删除 |
| `deleteSysParamsByIds` | `/sysParams/deleteSysParamsByIds` | DELETE | 批量删除 |
| `updateSysParams` | `/sysParams/updateSysParams` | PUT | 更新 |
| `findSysParams` | `/sysParams/findSysParams` | GET | 按 ID 查询 |
| `getSysParamsList` | `/sysParams/getSysParamsList` | GET | 分页列表 |
| `getSysParam` | `/sysParams/getSysParam` | GET | **按 key 查询**（不需要鉴权） |

注意 `getSysParam` 是不需要鉴权的公开接口，适合在未登录场景下获取系统配置。

### 3.4 前端参数使用方式 — useParamsStore

定义在 `web/src/pinia/modules/params.js`：

```javascript
export const useParamsStore = defineStore('params', () => {
  const paramsMap = ref({})    // 缓存：{ key: value }

  const getParams = async (key) => {
    // 1. 缓存命中则直接返回
    if (paramsMap.value[key] && paramsMap.value[key].length) {
      return paramsMap.value[key]
    }
    // 2. 否则调用 getSysParam API，缓存 key → value
    const res = await getSysParam({ key })
    if (res.code === 0) {
      paramsRes[key] = res.data.value
      setParamsMap(paramsRes)
      return paramsMap.value[key]
    }
  }
})
```

使用方式：

```javascript
import { useParamsStore } from '@/pinia/modules/params'

const paramsStore = useParamsStore()
const sysName = await paramsStore.getParams('sys_name')
```

缓存策略与字典 store 一致：首次获取后缓存在 `paramsMap` 中，页面生命周期内不再重复请求。

### 3.5 如何新增系统参数

**步骤 1：后台管理界面创建参数**

在参数管理页面新增：
- Name: "文件大小限制"
- Key: "file_max_size"
- Value: "10485760"
- Desc: "上传文件的最大字节数，默认 10MB"

**步骤 2：后端代码中引用**

```go
// 通过 key 获取参数值
param, err := SysParamsServiceApp.GetSysParam("file_max_size")
if err != nil {
    // 使用默认值
    maxSize = 10485760
} else {
    maxSize, _ = strconv.Atoi(param.Value)
}
```

**步骤 3：前端代码中引用**

```javascript
import { useParamsStore } from '@/pinia/modules/params'

const paramsStore = useParamsStore()
const maxSize = await paramsStore.getParams('file_max_size')
// maxSize 为字符串 "10485760"，需要时自行转换类型
```

---

## 四、字典 vs 参数 选择指南

| 特征 | 字典（Dictionary） | 参数（Params） |
|------|-------------------|---------------|
| 数据结构 | 二级结构：字典 → 多个详情项 | 简单 Key-Value |
| 适用场景 | 下拉框选项、枚举值、状态码映射 | 单个配置值、开关、阈值 |
| 前端缓存 | useDictionaryStore，按 type 缓存 | useParamsStore，按 key 缓存 |
| 获取方式 | `getDict('type')` 返回数组 | `getParams('key')` 返回字符串 |
| 鉴权 | 需要登录 | `getSysParam` 不需要鉴权 |
| 典型示例 | 性别、审核状态、部门类型 | 系统名称、文件大小限制、默认页大小 |

---

## 五、常见问题

### Q: 字典的 Status 字段为什么是 `*bool` 指针类型？

因为 Go 中 `bool` 类型的零值是 `false`。如果使用值类型，GORM 在 Updates 时会忽略 `false` 值（被视为零值）。使用指针类型可以区分 "未设置" 和 "设置为 false"。

### Q: 字典详情的 Extend 字段有什么用？

Extend 是扩展值字段，可以存储额外信息。比如字典 "颜色" 中，Value 为 "1"，Label 为 "红色"，Extend 可以存 "#FF0000" 色值。前端获取字典时会同时获得 label、value、extend 三个字段。

### Q: API 同步后为什么有些路由没有出现？

检查是否在忽略列表中。被添加到 `sys_ignore_apis` 的路由在同步时会被跳过。

### Q: 参数的 key 命名有什么规范？

建议使用小写字母 + 下划线的 snake_case 格式，如 `sys_name`、`file_max_size`、`default_page_size`。前缀可以用模块名区分，如 `mail_smtp_host`、`oss_bucket_name`。
