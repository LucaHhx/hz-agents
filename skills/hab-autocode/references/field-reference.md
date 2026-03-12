# AutoCode 字段参考

## AutoCode 结构体字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| package | string | 是 | 包名，需先通过 createPackage 创建 |
| tableName | string | 是 | 数据库表名 |
| structName | string | 是 | Go 结构体名称 (首字母大写) |
| packageName | string | 是 | 文件名 (小写) |
| abbreviation | string | 是 | 简称 (小写，用于路由前缀) |
| humpPackageName | string | 是 | 驼峰文件名 (通常等于 packageName) |
| description | string | 是 | 中文描述 |
| businessDB | string | 否 | 业务数据库名 (多库时使用) |
| gvaModel | bool | 否 | 是否使用默认 Model (ID, CreatedAt 等) |
| autoMigrate | bool | 否 | 是否自动迁移建表 |
| autoCreateApiToSql | bool | 否 | 是否自动注册 API |
| autoCreateMenuToSql | bool | 否 | 是否自动创建菜单 |
| autoCreateBtnAuth | bool | 否 | 是否自动创建按钮权限 |
| onlyTemplate | bool | 否 | 是否只生成模板文件 (不注入 gorm/router) |
| generateServer | bool | 否 | 是否生成后端代码 |
| generateWeb | bool | 否 | 是否生成前端代码 |

## AutoCodeField 字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| fieldName | string | 是 | Go 字段名 (首字母大写) |
| fieldDesc | string | 是 | 中文描述 |
| fieldType | string | 是 | Go 类型: string, int, float64, bool, time.Time, json, array, picture, file, richtext, video, enum |
| fieldJson | string | 是 | JSON 序列化名 (小驼峰) |
| dataType | string | 是 | 数据库类型: varchar, int, bigint, decimal, text, datetime, tinyint |
| dataTypeLong | string | 是 | 数据库类型长度: "255", "10,2", "20" 等 |
| comment | string | 否 | 数据库字段注释 |
| columnName | string | 是 | 数据库列名 (下划线命名) |
| fieldSearchType | string | 否 | 搜索条件: "=", "!=", ">", "<", ">=", "<=", "LIKE", "BETWEEN" |
| form | bool | 否 | 前端新建/编辑表单显示 |
| table | bool | 否 | 前端表格列显示 |
| desc | bool | 否 | 前端详情显示 |
| require | bool | 否 | 是否必填 |
| defaultValue | string | 否 | 默认值 |
| sort | bool | 否 | 是否支持排序 |
| primaryKey | bool | 否 | 是否主键 (gvaModel=false 时需要) |
| fieldIndexType | string | 否 | 索引类型 |

## AutoFunc 字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| package | string | 是 | 包名 |
| structName | string | 是 | 结构体名 |
| packageName | string | 是 | 文件名 |
| humpPackageName | string | 是 | 驼峰文件名 |
| abbreviation | string | 是 | 简称 |
| funcName | string | 是 | 方法名 (首字母大写) |
| router | string | 是 | 路由路径 (小驼峰) |
| method | string | 是 | HTTP 方法: GET, POST, PUT, DELETE |
| description | string | 否 | 描述 |
| funcDesc | string | 否 | 方法介绍 |
| isAuth | bool | 否 | 是否需要鉴权路由 |
| isPreview | bool | 否 | true 时只预览不注入 |
| isAi | bool | 否 | AI 模式 (可自定义代码) |
| apiFunc | string | 否 | 自定义 API handler 代码 (isAi=true 时) |
| serverFunc | string | 否 | 自定义 service 代码 (isAi=true 时) |
| jsFunc | string | 否 | 自定义前端 JS 代码 (isAi=true 时) |
