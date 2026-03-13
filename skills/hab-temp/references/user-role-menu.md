# 用户/角色/菜单管理 -- 完整参考文档

> 源码基线: hz-admin-base 项目
> 后端: Go (Gin + GORM)
> 前端: Vue 3 + Element Plus

---

## 1. 数据模型总览

### 1.1 核心表与关联关系

```
sys_users              用户表
sys_authorities        角色表
sys_base_menus         菜单表
sys_user_authority     用户-角色 多对多关联表
sys_authority_menus    角色-菜单 多对多关联表
sys_data_authority_id  角色-数据权限 多对多关联表 (角色可查看哪些角色的数据)
sys_base_menu_btns     菜单按钮定义表
sys_authority_btns     角色-按钮权限关联表
sys_table_columns      表格列定义表
sys_authority_cols     角色-列权限关联表
casbin_rule            Casbin RBAC 策略表
sys_bind_sessions      安全绑定临时会话表
jwt_blacklists         JWT 黑名单表
```

**ER 关系图 (简化)**:
```
SysUser ──many2many──> SysAuthority ──many2many──> SysBaseMenu
   │                       │                          │
   │ authority_id (当前角色) │ parent_id (角色树)       │ parent_id (菜单树)
   │                       │                          │
   │                       ├── DataAuthorityId         ├── SysBaseMenuBtn
   │                       ├── SysAuthorityBtn         ├── SysBaseMenuParameter
   │                       └── SysAuthorityCol         └── SysTableColumns
```

### 1.2 SysUser -- 用户模型

源码: `server/model/system/sys_user.go`，表名: `sys_users`

| 字段 | 类型 | JSON | 说明 |
|------|------|------|------|
| ID | uint | `ID` | 主键，自增 |
| UUID | uuid.UUID | `uuid` | 用户唯一标识，注册时自动生成 |
| Username | string | `userName` | 登录用户名，唯一索引 |
| Password | string | `-` (不输出) | bcrypt 加密存储 |
| NickName | string | `nickName` | 昵称，默认"系统用户" |
| HeaderImg | string | `headerImg` | 头像 URL |
| AuthorityId | uint | `authorityId` | **当前激活角色 ID**，默认 888 |
| Authority | SysAuthority | `authority` | 当前角色对象 (foreignKey: AuthorityId) |
| Authorities | []SysAuthority | `authorities` | 用户拥有的**所有角色** (many2many) |
| Phone | string | `phone` | 手机号 |
| Email | string | `email` | 邮箱 |
| Enable | int | `enable` | 1=正常, 2=冻结 |
| Type | enum.SysUserType | `type` | 0=管理员, 1=普通用户, 2=商户 |
| Parameter | string | `parameter` | 用户参数 (用于商户等扩展场景) |
| Language | string | `language` | 语言偏好，默认 zh-CN |
| GoogleAuthSecret | string | `-` (不输出) | TOTP 密钥 |
| Passkey | string | `passkey` | WebAuthn 凭证 ID (生产环境) |
| TestPasskey | string | `testPasskey` | WebAuthn 凭证 ID (本地开发环境) |
| OriginSetting | JSONMap | `originSetting` | 用户个性化配置 (JSON) |
| SideMode | string | `sideMode` | 侧边栏主题，默认 dark |
| ActiveColor | string | `activeColor` | 活跃颜色，默认 #1890ff |
| BaseColor | string | `baseColor` | 基础颜色，默认 #fff |

**关键设计点**:
- `AuthorityId` 是用户**当前激活**的角色；`Authorities` 是用户**拥有的所有**角色
- 用户可以在已分配的角色之间切换（`SetUserAuthority`），切换时会校验该角色是否在 `sys_user_authority` 中
- Password 字段使用 `json:"-"` 标签，永远不会序列化到前端
- `SysUser` 实现了 `Login` 接口，提供 `GetUsername/GetNickname/GetUUID/GetUserId/GetAuthorityId/GetType/GetParameter/GetUserInfo` 方法，用于统一 Token 签发

### 1.3 SysAuthority -- 角色模型

源码: `server/model/system/sys_authority.go`，表名: `sys_authorities`

| 字段 | 类型 | JSON | 说明 |
|------|------|------|------|
| AuthorityId | uint | `authorityId` | 角色 ID，**主键**，非自增，由创建者指定 |
| AuthorityName | string | `authorityName` | 角色名称 |
| ParentId | *uint | `parentId` | 父角色 ID，顶级角色为 0 |
| DataAuthorityId | []*SysAuthority | `dataAuthorityId` | 数据权限 -- 该角色可查看哪些角色的数据 |
| Children | []SysAuthority | `children` | 子角色列表 (gorm:"-"，程序递归组装) |
| SysBaseMenus | []SysBaseMenu | `menus` | 角色关联的菜单 (many2many: sys_authority_menus) |
| Users | []SysUser | `-` | 使用该角色的用户 (many2many，JSON 不输出) |
| DefaultRouter | string | `defaultRouter` | 默认首页路由 name，默认 "userInfo" |

**关键设计点**:
- **角色是树形结构**，通过 `ParentId` 构建父子关系
- 当配置 `UseStrictAuth = true` 时，启用严格树形角色控制：
  - 顶级角色 (ParentId=0) 可管理自身及所有子角色
  - 非顶级角色只能管理自己的子角色
  - 新建角色的 ParentId 强制设为当前操作者的 AuthorityId
- `DataAuthorityId` 是**数据权限**，决定该角色能看到哪些角色下的数据
- 删除角色前会检查：是否有用户正在使用、是否有子角色

### 1.4 SysBaseMenu -- 菜单模型

源码: `server/model/system/sys_base_menu.go`，表名: `sys_base_menus`

| 字段 | 类型 | JSON | 说明 |
|------|------|------|------|
| ID | uint | `ID` | 主键 |
| ParentId | uint | `parentId` | 父菜单 ID，0 表示顶级 |
| Path | string | `path` | 路由 path |
| Name | string | `name` | 路由 name，**全局唯一** |
| Hidden | bool | `hidden` | 是否在菜单列表中隐藏 |
| Component | string | `component` | 前端组件路径，如 `view/superAdmin/user/user.vue` |
| Sort | int | `sort` | 排序标记，数字越小越靠前 |
| Meta.Title | string | `title` | 菜单显示名称 |
| Meta.Icon | string | `icon` | 菜单图标 |
| Meta.KeepAlive | bool | `keepAlive` | 是否缓存组件 |
| Meta.DefaultMenu | bool | `defaultMenu` | 是否基础路由 |
| Meta.ActiveName | string | `activeName` | 高亮菜单 name (隐藏菜单需要高亮父菜单时用) |
| Meta.CloseTab | bool | `closeTab` | 自动关闭 Tab |
| Meta.TransitionType | string | `transitionType` | 路由切换动画 |
| Children | []SysBaseMenu | `children` | 子菜单 (gorm:"-"，程序组装) |
| Parameters | []SysBaseMenuParameter | `parameters` | 路由参数 |
| MenuBtn | []SysBaseMenuBtn | `menuBtn` | 菜单内的按钮定义 |
| TableColumns | []SysTableColumns | `tableColumns` | 表格列定义 |

**SysBaseMenuParameter -- 路由参数**:

| 字段 | 说明 |
|------|------|
| Type | `params` 或 `query` |
| Key | 参数名 |
| Value | 参数值 |

**SysBaseMenuBtn -- 按钮定义**:

源码: `server/model/system/sys_menu_btn.go`

| 字段 | 说明 |
|------|------|
| Name | 按钮标识 key，如 `add`, `edit`, `delete` |
| Desc | 按钮描述 |
| SysBaseMenuID | 所属菜单 ID |

### 1.5 关联表

**SysUserAuthority** -- 用户-角色关联:

源码: `server/model/system/sys_user_authority.go`，表名: `sys_user_authority`

| 字段 | 数据库列名 |
|------|-----------|
| SysUserId | `sys_user_id` |
| SysAuthorityAuthorityId | `sys_authority_authority_id` |

**SysAuthorityMenu** -- 角色-菜单关联:

源码: `server/model/system/sys_authority_menu.go`，表名: `sys_authority_menus`

| 字段 | 数据库列名 |
|------|-----------|
| MenuId | `sys_base_menu_id` |
| AuthorityId | `sys_authority_authority_id` |

**SysAuthorityBtn** -- 角色-按钮权限:

源码: `server/model/system/sys_authority_btn.go`

| 字段 | 说明 |
|------|------|
| AuthorityId | 角色 ID |
| SysMenuID | 菜单 ID |
| SysBaseMenuBtnID | 按钮 ID |
| SysBaseMenuBtn | 按钮详情 (关联) |

**SysAuthorityCol** -- 角色-列权限:

源码: `server/model/system/sys_authority_col.go`

| 字段 | 说明 |
|------|------|
| AuthorityId | 角色 ID |
| SysMenuID | 菜单 ID |
| SysTableColumnsID | 列 ID |
| SysTableColumns | 列详情 (关联) |

**SysMenu** -- 前端动态路由菜单 (运行时组装，非独立表):

源码: `server/model/system/sys_authority_menu.go`

```go
type SysMenu struct {
    SysBaseMenu                                // 嵌入基础菜单
    MenuId      uint                           // 菜单 ID
    AuthorityId uint                           // 角色 ID
    Children    []SysMenu                      // 子菜单
    Parameters  []SysBaseMenuParameter         // 路由参数
    Btns        map[string]uint                // 按钮权限 {"add": 888, "edit": 888}
    Columns     map[string]uint                // 列权限 {"name": 888, "phone": 888}
}
```

---

## 2. 用户管理

### 2.1 API 路由表

源码: `server/router/system/sys_user.go`

| 方法 | 路径 | 功能 | 操作记录 | 前端 API |
|------|------|------|:---:|------|
| POST | `/user/admin_register` | 管理员注册(新建)用户 | Y | `register(data)` |
| POST | `/user/getUserList` | 分页获取用户列表 | N | `getUserList(data)` |
| GET | `/user/getUserInfo` | 获取当前登录用户信息 | N | `getUserInfo()` |
| PUT | `/user/setUserInfo` | 管理员设置用户信息 | Y | `setUserInfo(data)` |
| PUT | `/user/setSelfInfo` | 用户设置自身信息 | Y | `setSelfInfo(data)` |
| PUT | `/user/setSelfSetting` | 用户设置界面配置 | Y | `setSelfSetting(data)` |
| POST | `/user/changePassword` | 用户修改密码 | Y | `changePassword(data)` |
| POST | `/user/resetPassword` | 管理员重置用户密码 | Y | `resetPassword(data)` |
| DELETE | `/user/deleteUser` | 删除用户 | Y | `deleteUser(data)` |
| POST | `/user/setUserAuthority` | 切换当前激活角色 | Y | `setUserAuthority(data)` |
| POST | `/user/setUserAuthorities` | 设置用户的角色列表 | Y | `setUserAuthorities(data)` |
| POST | `/user/unbindSecurity` | 解绑安全验证 | Y | `unbindSecurity(data)` |
| POST | `/user/resetGoogleAuth` | 重置 TOTP 验证器 | Y | `resetGoogleAuth()` |
| GET | `/user/getGoogleAuthQR` | 获取 TOTP 二维码 | Y | `getGoogleAuthQR()` |

前端 API 文件: `web/src/api/user.js`

### 2.2 注册用户

**请求结构** (`request/sys_user.go -> Register`):
```go
type Register struct {
    Username     string           `json:"userName"`
    Password     string           `json:"passWord"`
    NickName     string           `json:"nickName"`
    HeaderImg    string           `json:"headerImg"`
    AuthorityId  uint             `json:"authorityId"`     // 默认角色
    AuthorityIds []uint           `json:"authorityIds"`    // 所有角色
    Enable       int              `json:"enable"`
    Phone        string           `json:"phone"`
    Email        string           `json:"email"`
    Type         enum.SysUserType `json:"type"`
    Parameter    string           `json:"parameter"`
}
```

**后端流程** (service `Register`):
1. 检查用户名是否已存在
2. 密码 bcrypt 加密，生成 UUID
3. 创建用户记录（含 Authorities 多对多关联）

**API 层额外逻辑**:
- 如果当前操作者不是管理员 (`type != 0`)，强制将新用户的 type 和 parameter 设为操作者自己的值（多租户隔离）
- 使用 `utils.RegisterVerify` 校验必填字段

**前端调用示例**:
```js
import { register } from '@/api/user'
register({
  userName: 'newuser',
  passWord: '123456',
  nickName: '新用户',
  authorityId: 888,
  authorityIds: [888, 999],
  enable: 1
})
```

### 2.3 获取用户列表

**请求结构** (`request/sys_user.go -> GetUserList`):
```go
type GetUserList struct {
    common.PageInfo              // Page, PageSize
    Username string `json:"username"`
    NickName string `json:"nickName"`
    Phone    string `json:"phone"`
    Email    string `json:"email"`
}
```

**后端流程** (service `GetUserInfoList`):
1. 支持模糊搜索: nickName LIKE, phone LIKE, username LIKE, email LIKE
2. **非管理员隔离**: 如果操作者 type != 0，只能看到同 type 且同 parameter 的用户，并排除自身
3. Preload `Authorities` 和 `Authority`
4. 返回分页结果

### 2.4 修改用户信息

**请求结构** (`request/sys_user.go -> ChangeUserInfo`):
```go
type ChangeUserInfo struct {
    ID           uint
    NickName     string
    Phone        string
    AuthorityIds []uint    // 角色 ID 列表
    Email        string
    HeaderImg    string
    SideMode     string
    Enable       int       // 1=正常, 2=冻结
    Language     string
    Type         enum.SysUserType
    Parameter    string
}
```

**后端流程** (API `SetUserInfo`):
1. 如果提供了 `authorityIds`，先调用 `SetUserAuthorities` 更新用户角色
2. 然后调用 service `SetUserInfo` 更新基本信息
3. service 使用 `Select` + `Updates(map)` 明确指定更新字段，避免零值覆盖

**前端需要做**:
- 编辑用户表单中包含角色多选（`authorityIds`）
- 冻结/解冻用户通过 `enable` 字段控制
- 冻结用户无法登录（登录接口会检查 `user.Enable != 1`）

### 2.5 密码管理

**修改密码** (API `changePassword`):

请求结构:
```go
type ChangePasswordReq struct {
    ID          uint   `json:"-"`            // 从 JWT 提取，防止越权
    Password    string `json:"password"`     // 原密码
    NewPassword string `json:"newPassword"`  // 新密码
}
```

后端: bcrypt 校验旧密码 -> bcrypt 加密新密码 -> 保存

**重置密码** (API `resetPassword`):
- 管理员操作，只需传 user ID
- **固定重置为 `123456`** (bcrypt 加密存储)
- 注意: 不能自己重置自己的密码（前端应用逻辑控制）

### 2.6 删除用户

**后端流程** (事务):
1. 校验不能删除自己 (`jwtId == reqId.ID` 时返回 `ErrDeleteSelfNotAllowed`)
2. 软删除用户记录 (`sys_users`)
3. 删除用户-角色关联记录 (`sys_user_authority`)

### 2.7 角色切换与分配

**切换当前角色** (API `setUserAuthority`):

请求:
```go
type SetUserAuth struct {
    AuthorityId uint `json:"authorityId"`
}
```

后端流程:
1. 校验该用户确实拥有目标角色 (查 `sys_user_authority`)
2. 查询目标角色的菜单列表
3. 校验目标角色的 `DefaultRouter` 对应的菜单存在于该角色的菜单列表中
4. 如果 DefaultRouter 对应菜单不存在，返回 "找不到默认路由,无法切换本角色"
5. 更新 `sys_users.authority_id`
6. **重新签发 JWT** -- 返回 `new-token` 和 `new-expires-at` response header

**设置用户角色列表** (API `setUserAuthorities`):

请求:
```go
type SetUserAuthorities struct {
    ID           uint
    AuthorityIds []uint `json:"authorityIds"`
}
```

后端流程 (事务):
1. 查询用户是否存在
2. 删除旧的 `sys_user_authority` 记录
3. 校验每个目标角色 ID 的合法性 (`CheckAuthorityIDAuth`)
4. 批量插入新的关联记录
5. 将 `authority_id` 设为 `authorityIds[0]`（第一个角色为默认激活角色）

---

## 3. 角色管理

### 3.1 API 路由表

源码: `server/router/system/sys_authority.go`

| 方法 | 路径 | 功能 | 操作记录 | 前端 API |
|------|------|------|:---:|------|
| POST | `/authority/createAuthority` | 创建角色 | Y | `createAuthority(data)` |
| POST | `/authority/deleteAuthority` | 删除角色 | Y | `deleteAuthority(data)` |
| PUT | `/authority/updateAuthority` | 更新角色 | Y | `updateAuthority(data)` |
| POST | `/authority/copyAuthority` | 复制角色 | Y | `copyAuthority(data)` |
| POST | `/authority/getAuthorityList` | 获取角色列表 (树形) | N | `getAuthorityList(data)` |
| POST | `/authority/setDataAuthority` | 设置数据权限 | Y | `setDataAuthority(data)` |

前端 API 文件: `web/src/api/authority.js`

### 3.2 创建角色

**后端流程** (service `CreateAuthority`, 事务):
1. 接收: authorityId (手动输入), authorityName, parentId
2. API 层强制将 `parentId` 设为当前操作者的 authorityId (严格模式下)
3. 创建角色记录
4. 分配默认菜单 -- `DefaultMenu()` 返回 ID=53 的 "用户信息" 页面
5. 权限初始化:
   - **管理员创建**: 使用 `DefaultCasbin()` 分配 9 条默认 API 权限
   - **非管理员创建**: 复制父角色的 Casbin 策略 + 列权限
6. API 层创建成功后调用 `CasbinServiceApp.FreshCasbin()` 刷新缓存

**默认 Casbin 策略** (`request/sys_casbin.go -> DefaultCasbin()`):
```
POST /menu/getMenu
POST /jwt/jsonInBlacklist
POST /base/login
POST /user/changePassword
POST /user/setUserAuthority
GET  /user/getUserInfo
PUT  /user/setSelfInfo
POST /fileUploadAndDownload/upload
GET  /sysDictionary/findSysDictionary
```

**默认菜单** (`request/sys_menu.go -> DefaultMenu()`):
```go
SysBaseMenu{ID: 53, Path: "userInfo", Name: "userInfo", Component: "view/person/person.vue", Title: "用户信息"}
```

### 3.3 复制角色

**后端流程** (service `CopyAuthority`):
1. 接收: oldAuthorityId (源角色), authority (新角色信息)
2. **ParentId 强制设为当前操作者的 authorityId**
3. 从源角色复制:
   - 菜单权限 (查 `sys_authority_menus` -> 创建新关联)
   - 按钮权限 (`sys_authority_btns`)
   - 列权限 (`sys_authority_cols`)
   - Casbin API 策略

### 3.4 删除角色

**后端校验** (service `DeleteAuthority`):
1. 角色必须存在
2. 角色下**没有用户**在使用 (两重检查: many2many Users 关联 + 直接查 `sys_users.authority_id`)
3. 角色下**没有子角色** (查 `parent_id = ?`)

**事务清理**:
1. Preload SysBaseMenus 和 DataAuthorityId
2. 硬删除角色记录 (`Unscoped().Delete`)
3. 清除菜单关联 (`Association("SysBaseMenus").Delete`)
4. 清除数据权限关联 (`Association("DataAuthorityId").Delete`)
5. 删除用户-角色关联 (`sys_user_authority`)
6. 删除按钮权限 (`sys_authority_btns`)
7. 删除 Casbin 策略 (`RemoveFilteredPolicy`)
8. API 层调用 `FreshCasbin()` 刷新缓存

### 3.5 获取角色列表

**后端逻辑** (service `GetAuthorityInfoList`):

- **严格模式 (`UseStrictAuth=true`)**:
  - 顶级角色 (ParentId=0): 返回自己(含子角色递归)
  - 非顶级角色: 只返回自己的子角色(递归)
- **非严格模式**: 返回所有 ParentId=0 的顶级角色 + 递归子角色
- 每个角色 Preload `DataAuthorityId`
- 递归调用 `findChildrenAuthority` 组装树形结构

### 3.6 设置数据权限

**作用**: 控制某角色可以查看哪些其他角色的数据

**后端流程** (service `SetDataAuthority`):
1. 接收: authorityId + dataAuthorityId (SysAuthority 数组)
2. 校验所有涉及的角色 ID 在操作者权限范围内
3. 使用 GORM `Association("DataAuthorityId").Replace()` 全量替换

**前端调用示例**:
```js
import { setDataAuthority } from '@/api/authority'
setDataAuthority({
  authorityId: 888,
  dataAuthorityId: [
    { authorityId: 888 },
    { authorityId: 999 }
  ]
})
```

### 3.7 更新角色

**后端流程** (service `UpdateAuthority`):
1. 查询旧角色记录
2. 使用 GORM `Updates` 更新 (authorityName, defaultRouter 等)
3. 注意: AuthorityId 作为主键不可更新

---

## 4. 菜单管理

### 4.1 API 路由表

源码: `server/router/system/sys_menu.go`

| 方法 | 路径 | 功能 | 操作记录 | 前端 API |
|------|------|------|:---:|------|
| POST | `/menu/addBaseMenu` | 新增菜单 | Y | `addBaseMenu(data)` |
| POST | `/menu/deleteBaseMenu` | 删除菜单 | Y | `deleteBaseMenu(data)` |
| POST | `/menu/updateBaseMenu` | 更新菜单 | Y | `updateBaseMenu(data)` |
| POST | `/menu/getMenu` | 获取当前用户的动态路由菜单树 | N | `asyncMenu()` |
| POST | `/menu/getMenuList` | 获取完整菜单列表 (管理用) | N | `getMenuList(data)` |
| POST | `/menu/getBaseMenuTree` | 获取基础菜单树 | N | `getBaseMenuTree()` |
| POST | `/menu/getBaseMenuById` | 根据 ID 获取单个菜单 | N | `getBaseMenuById(data)` |
| POST | `/menu/addMenuAuthority` | 设置角色-菜单关联 | Y | `addMenuAuthority(data)` |
| POST | `/menu/getMenuAuthority` | 获取指定角色的菜单 | N | `getMenuAuthority(data)` |

前端 API 文件: `web/src/api/menu.js`

### 4.2 新增菜单

**后端流程** (service `AddBaseMenu`):
1. **name 全局唯一**校验 -- 查询是否存在同名菜单
2. 创建菜单记录 (GORM 自动创建 Parameters 和 MenuBtn 子表记录)

**前端需要传递**:
```js
import { addBaseMenu } from '@/api/menu'
addBaseMenu({
  parentId: 0,           // 父菜单 ID，0=顶级
  path: 'userManage',
  name: 'userManage',    // 全局唯一
  component: 'view/superAdmin/user/user.vue',
  sort: 1,
  hidden: false,
  meta: {
    title: '用户管理',
    icon: 'user',
    keepAlive: false,
    defaultMenu: false,
    closeTab: false
  },
  parameters: [],        // 路由参数
  menuBtn: [             // 按钮定义
    { name: 'add', desc: '新增' },
    { name: 'edit', desc: '编辑' },
    { name: 'delete', desc: '删除' }
  ]
})
```

### 4.3 更新菜单

**后端流程** (service `UpdateBaseMenu`, 事务):
1. 如果修改了 `name`，检查新 name 不与其他菜单冲突 (`id <> ? AND name = ?`)
2. 删除旧的 Parameters (`Unscoped().Delete`)
3. 删除旧的 MenuBtn (`Unscoped().Delete`)
4. 创建新的 Parameters 和 MenuBtn
5. 更新菜单主记录 -- 使用 `map[string]interface{}` 手动构建更新字段，确保 bool 类型零值 (如 `keepAlive=false`) 能正确更新

可更新字段: keepAlive, closeTab, defaultMenu, parentId, path, name, hidden, component, title, activeName, icon, sort

### 4.4 删除菜单

**后端校验** (service `DeleteBaseMenu`):
1. 不能有子菜单 -- 查询 `parent_id = id` 是否有记录
2. 不能有角色将该菜单设为默认首页 -- 查询 `sys_authorities.default_router = menu.Name`

**事务清理**:
1. 删除菜单记录 (`sys_base_menus`)
2. 删除路由参数 (`sys_base_menu_parameters`)
3. 删除按钮定义 (`sys_base_menu_btns`)
4. 删除角色-按钮权限 (`sys_authority_btns WHERE sys_menu_id = ?`)
5. 删除角色-菜单关联 (`sys_authority_menus WHERE sys_base_menu_id = ?`)

### 4.5 获取动态路由菜单 (GetMenu / GetMenuTree)

**用途**: 前端登录后获取当前用户有权限的菜单，用于构建侧边栏和动态路由

**后端流程** (service `GetMenuTree -> getMenuTreeMap`):
1. 根据 `authorityId` 查询 `sys_authority_menus` 获取菜单 ID 列表
2. 查询 `sys_base_menus` 记录 (ORDER BY sort)，Preload `Parameters`
3. 查询 `sys_authority_btns` 构建按钮权限 map: `btnMap[menuID][btnName] = authorityId`
4. 查询 `sys_authority_cols` 构建列权限 map: `colMap[menuID][colJsonName] = authorityId`
5. 组装 SysMenu 对象，设置 Btns 和 Columns 字段
6. 按 ParentId 分组，递归构建树形结构 (ParentId=0 为根节点)

**返回数据示例**:
```json
{
  "menus": [
    {
      "ID": 1,
      "path": "admin",
      "name": "superAdmin",
      "component": "view/superAdmin/index.vue",
      "meta": { "title": "超级管理员", "icon": "user" },
      "menuId": 1,
      "btns": {},
      "columns": {},
      "children": [
        {
          "ID": 3,
          "path": "user",
          "name": "user",
          "component": "view/superAdmin/user/user.vue",
          "meta": { "title": "用户管理", "icon": "coordinate" },
          "menuId": 3,
          "btns": { "add": 888, "edit": 888, "delete": 888 },
          "columns": { "userName": 888, "phone": 888 },
          "children": []
        }
      ]
    }
  ]
}
```

### 4.6 获取菜单列表 (GetInfoList / GetMenuList)

**用途**: 菜单管理页面展示全量菜单树

**后端流程** (service `GetInfoList -> getBaseMenuTreeMap`):
1. 获取当前角色的父角色 ID
2. 严格模式 + 非顶级角色: 只返回该角色已分配的菜单
3. 非严格模式/顶级角色: 返回所有菜单
4. Preload `TableColumns`, `MenuBtn`, `Parameters`
5. 非管理员用户: 过滤 MenuBtn 和 TableColumns，只保留该角色有权限的
6. 按 ParentId 分组，递归构建树形结构

### 4.7 设置角色-菜单关联 (AddMenuAuthority)

**后端流程** (API `AddMenuAuthority`):
1. 接收: menus (SysBaseMenu 数组), authorityId (目标角色 ID)
2. **按钮与菜单分离**: ID >= 15023 视为按钮，< 15023 视为菜单
3. 按钮按所属菜单 (parentId) 分组，逐组调用 `SetAuthorityBtn`
4. 按钮的实际 ID = 传入 ID - 15023
5. 菜单部分调用 `AddMenuAuthority`:
   - 校验操作者权限 (`CheckAuthorityIDAuth`)
   - 严格模式下: 校验不能分配操作者自己没有的菜单
   - 调用 `SetMenuAuthority` 通过 `Association("SysBaseMenus").Replace()` 全量替换

**前端调用示例**:
```js
import { addMenuAuthority } from '@/api/menu'
addMenuAuthority({
  authorityId: 888,
  menus: [
    { ID: 1 },                            // 菜单
    { ID: 3 },                            // 菜单
    { ID: 15024, parentId: 3 },           // 按钮 (实际按钮 ID = 15024 - 15023 = 1)
    { ID: 15025, parentId: 3 },           // 按钮 (实际按钮 ID = 2)
  ]
})
```

### 4.8 获取指定角色的菜单 (GetMenuAuthority)

**用途**: 角色权限分配页面，显示该角色当前已分配的菜单

**后端流程**: 查询 `sys_authority_menus` -> 获取菜单 ID 列表 -> 查询菜单记录 -> 组装 SysMenu 返回

---

## 5. 三者关联关系详解

### 5.1 权限控制链路

```
用户登录
  -> JWT 包含: userId, uuid, authorityId
  -> 请求到达
     -> Casbin 中间件: 检查 authorityId 是否有权访问该 API (path + method)
     -> 业务逻辑: 使用 authorityId 获取菜单/按钮/列权限
```

### 5.2 五层权限模型

| 层级 | 控制对象 | 存储位置 | 控制端 |
|------|----------|----------|--------|
| API 权限 | 后端接口 (path + method) | `casbin_rule` 表 | 后端拦截 |
| 菜单权限 | 前端路由/页面 | `sys_authority_menus` | 前端路由 |
| 按钮权限 | 页面内按钮 | `sys_authority_btns` | 前端 UI |
| 列权限 | 表格列显隐 | `sys_authority_cols` | 前端 UI |
| 数据权限 | 可查看的数据范围 | `sys_data_authority_id` | 后端查询 |

### 5.3 典型工作流: 创建新功能页面

1. **后端**: 编写 API handler, service, router
2. **后端**: 在 Casbin 中为需要的角色添加 API 策略
3. **前端**: 创建 Vue 组件
4. **菜单管理**: 在菜单管理页面添加新菜单（指定 path, name, component, 按钮定义）
5. **角色管理**: 在角色权限分配页面为目标角色勾选该菜单和按钮
6. **用户管理**: 确认用户拥有对应角色

---

## 6. 认证系统

### 6.1 登录模式

系统支持三种登录模式 (`config.System.LoginMode`):

| 模式 | 图片验证码 | 密码 | 安全角色检查 | 适用场景 |
|------|:---:|:---:|:---:|------|
| `simple` | 不需要 | 需要 | 不检查 | 开发/内网 |
| `captcha` | **需要** | 需要 | 不检查 | 常规部署 |
| `strict` | **需要** | 需要 | 需要角色含"账户状态" | 高安全要求 |

### 6.2 认证 API (/auth/*)

前端 API 文件: `web/src/api/auth.js`

| 路径 | 方法 | 功能 | 前端函数 |
|------|------|------|----------|
| `/auth/login-mode` | GET | 获取登录模式 (公开) | `getLoginMode()` |
| `/auth/password/login` | POST | 密码登录 | `passwordLogin(data)` |
| `/auth/security-state` | POST | 查询安全绑定状态 | `securityState(data)` |
| `/auth/password/verify` | POST | 密码预验证 (绑定流程) | `passwordVerify(data)` |
| `/auth/totp/login` | POST | TOTP 登录 | `totpLogin(data)` |
| `/auth/totp/bind/init` | POST | 初始化 TOTP 绑定 | `totpBindInit()` |
| `/auth/totp/bind/verify` | POST | 验证 TOTP 绑定 | `totpBindVerify(data)` |
| `/auth/passkey/assertion/options` | POST | Passkey 登录选项 | `passkeyAssertionOptions(data)` |
| `/auth/passkey/assertion/verify` | POST | Passkey 登录验证 | `passkeyAssertionVerify(data)` |
| `/auth/passkey/attestation/options` | POST | Passkey 绑定选项 | `passkeyAttestationOptions(data)` |
| `/auth/passkey/attestation/verify` | POST | Passkey 绑定验证 | `passkeyAttestationVerify(data)` |

### 6.3 JWT Token 签发 (TokenNext)

登录成功后调用 `TokenNext`:
1. 调用 `utils.LoginToken` 生成 JWT Token (包含 userId, uuid, authorityId)
2. 如果启用多点登录控制 (`UseMultipoint`):
   - 检查 Redis 中是否已有该用户的 token
   - 如果有，将旧 token 加入黑名单 (`jwt_blacklists`)
   - 存储新 token 到 Redis
3. 设置 token cookie
4. 返回: `{ user, token, expiresAt }`

### 6.4 登录后数据加载流程

```
前端登录成功 -> 获取 Token
    -> GET /user/getUserInfo -> 获取用户信息 + 角色列表
    -> POST /menu/getMenu -> 获取当前角色菜单 (含 btns/columns)
    -> 构建动态路由 -> 跳转到角色的 DefaultRouter
```

---

## 7. 前端职责与后端职责

### 7.1 前端该做什么

**用户管理页面**:
- 用户列表: 调用 `getUserList`，支持分页 + 搜索（用户名/昵称/手机/邮箱）
- 新建用户: 表单含用户名、密码、昵称、头像、手机、邮箱、角色多选、是否启用
- 编辑用户: 调用 `setUserInfo`，可修改基本信息 + 角色分配 (`authorityIds`) + 冻结/解冻
- 重置密码: 调用 `resetPassword`，弹窗确认（告知重置为 123456）
- 删除用户: 调用 `deleteUser`，弹窗确认
- 角色切换: 在顶部栏显示当前角色，下拉选择已分配的角色，调用 `setUserAuthority`，切换后刷新菜单

**角色管理页面**:
- 角色列表: 树形表格展示，调用 `getAuthorityList`
- 新建角色: 表单含角色 ID（手动输入，需唯一）、角色名、默认首页路由
- 复制角色: 从已有角色复制全部权限
- 编辑角色: 修改角色名、默认路由
- 删除角色: 前端应给出提示 "有子角色/有用户使用时不可删除"
- 菜单权限分配: 弹窗中显示菜单树 + 按钮勾选，调用 `addMenuAuthority`
- API 权限分配: 调用 Casbin 相关接口 (`web/src/api/casbin.js`)
- 数据权限: 弹窗中多选可见角色，调用 `setDataAuthority`

**菜单管理页面**:
- 菜单列表: 树形表格，调用 `getMenuList`
- 新增/编辑菜单: 表单含 path, name, component, 排序, 图标, 标题, hidden, keepAlive, 按钮定义
- 删除菜单: 调用 `deleteBaseMenu`

**按钮权限控制 (前端实现)**:
- 从 `getMenu` 返回的 `btns` 字段获取权限
- 使用 `v-if` 或自定义指令控制按钮显隐
- 示例: `v-if="route.meta.btns?.['add']"`

**列权限控制 (前端实现)**:
- 从 `getMenu` 返回的 `columns` 字段获取权限
- 动态过滤 table columns 配置

### 7.2 后端该做什么

**数据验证**:
- 用户名唯一性
- 密码 bcrypt 加密/校验
- 菜单 name 唯一性
- 角色 ID 唯一性
- 删除前的关联检查（子菜单、子角色、用户引用）

**权限控制**:
- Casbin 中间件: API 级别权限拦截
- 用户类型隔离: 非管理员只能看到同类型用户
- 严格模式: 非顶级角色只能管理子角色/子菜单
- 角色合法性校验: `CheckAuthorityIDAuth`
- 切换角色时的 DefaultRouter 校验

**事务保证**:
- 删除用户: 同时删除用户-角色关联
- 删除角色: 同时清理菜单/按钮/Casbin/用户关联
- 删除菜单: 同时清理参数/按钮/角色关联
- 设置用户角色: 先删后建
- 更新菜单: 先删旧参数和按钮，再建新的

---

## 8. 注意事项和常见问题

### 8.1 角色 ID 是手动指定的

与自增 ID 不同，`SysAuthority.AuthorityId` 由创建者输入。需要注意:
- 前端必须提示用户输入唯一的角色 ID
- 后端如果 ID 已存在会报错 (`ErrRoleExistence`)
- 复制角色时 `AuthorityId` 被设为 0，需要确认数据库是否有自增机制

### 8.2 密码重置为固定值

`ResetPassword` 将密码重置为 `123456`。建议:
- 前端重置后弹窗提醒用户立即修改密码
- 或改为生成随机密码并展示给管理员

### 8.3 菜单 Name 必须全局唯一

菜单的 `name` 字段对应前端路由的 `name`，创建和更新时都有唯一性校验。如果冲突会返回 "存在重复name，请修改name" 或 "存在相同name修改失败"。

### 8.4 按钮权限的 ID 偏移量

在 `AddMenuAuthority` 中，按钮和菜单通过 `ID >= 15023` 来区分:
- ID < 15023: 视为菜单
- ID >= 15023: 视为按钮，实际按钮 ID = 传入 ID - 15023

这是一个硬编码的约定，前端构建权限树时必须遵守。

### 8.5 Casbin 策略必须刷新

创建/删除角色后需要调用 `FreshCasbin()` 刷新内存中的策略缓存，否则新权限不会生效。API 层已经在 `CreateAuthority` 和 `DeleteAuthority` 之后做了刷新。

### 8.6 DefaultRouter 校验逻辑

- 每个角色有 `defaultRouter` 字段，默认值 `userInfo`
- 切换角色时会校验该角色的菜单中是否包含 `defaultRouter` 对应的 name
- 如果不包含，`UserAuthorityDefaultRouter` 会将其设为 `404`
- 删除菜单时会检查是否有角色将其设为 defaultRouter，有则拒绝删除

### 8.7 用户类型隔离 (多租户)

`SysUser.Type` 和 `Parameter` 用于多租户隔离:
- 管理员 (type=0) 可以看到所有用户
- 其他类型只能看到同 type + 同 parameter 的用户
- 注册用户时，非管理员创建的用户会继承操作者的 type 和 parameter
- 创建角色时，非管理员创建的角色会复制父角色的 Casbin 策略和列权限

### 8.8 多角色与当前角色

- 用户可以拥有多个角色 (`Authorities` / `sys_user_authority`)
- 但同一时刻只有一个**激活角色** (`AuthorityId`)
- JWT 中只包含当前激活角色的 `authorityId`
- 切换角色需要重新签发 JWT（后端返回 `new-token` header）
- 前端切换角色后必须重新获取菜单和刷新路由

### 8.9 软删除 vs 硬删除

- `SysUser`: GORM 软删除 (`DeletedAt` 字段)，删除后数据仍在数据库
- `SysAuthority`: 使用 `Unscoped().Delete()` 执行**物理删除**
- `SysBaseMenu`: 普通 `Delete`，受 GORM 默认行为控制

### 8.10 严格树形模式 (`UseStrictAuth`)

该配置项改变多处行为:

| 场景 | 非严格模式 | 严格模式 |
|------|-----------|---------|
| 创建角色 | ParentId 可选 | ParentId 强制为操作者的 authorityId |
| 获取角色列表 | 返回所有顶级角色+子角色 | 顶级角色返回自身+子角色；非顶级只返回子角色 |
| 获取菜单列表 | 返回所有菜单 | 非顶级角色只返回已分配的菜单 |
| 分配菜单权限 | 无限制 | 不能分配操作者没有的菜单 ("请勿跨级操作") |

### 8.11 本地开发环境 Passkey 处理

系统通过检测 `Request.Host` 包含 `127.0.0.1` 或 `localhost` 来判断是否为本地环境:
- 本地环境使用 `TestPasskey` 字段
- 生产环境使用 `Passkey` 字段
- 这允许同一用户在不同环境绑定不同的 Passkey

### 8.12 前端 API 文件映射

| 功能模块 | 前端 API 文件 |
|----------|--------------|
| 用户管理 | `web/src/api/user.js` |
| 角色管理 | `web/src/api/authority.js` |
| 菜单管理 | `web/src/api/menu.js` |
| 认证登录 | `web/src/api/auth.js` |
| Casbin API 权限 | `web/src/api/casbin.js` |
| 按钮权限 | `web/src/api/authorityBtn.js` |
| 列权限 | `web/src/api/authorityCol.js` |

### 8.13 前端权限仅为 UI 控制

`btns` 和 `columns` 只影响前端显示，实际的 API 访问安全由后端 Casbin 中间件保证。**后端和前端权限必须同步配置** -- 如果前端隐藏了按钮但后端 Casbin 没有拦截对应 API，用户仍然可以通过直接调用 API 绕过限制。

### 8.14 CheckAuthorityIDAuth 当前被跳过

源码中 `CheckAuthorityIDAuth` 函数开头有 `if true { return nil }`，即**当前跳过了角色合法性校验**。这是一个待修复项，开启后会校验操作者是否有权管理目标角色 ID。
