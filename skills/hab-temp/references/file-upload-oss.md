# 文件上传与多云存储

本文档详细说明 hz-admin-base 的文件上传架构、多云存储适配、前端上传组件和媒体库系统。

## 1. 文件上传架构概览

```
前端组件层                          后端 API                        存储层
+------------------+          +---------------------+        +-----------------+
| selectImage.vue  |  POST    | /fileUploadAndDown  |        | Local           |
|   ├ common.vue   | -------> |  load/upload        | -----> | Aliyun OSS      |
|   ├ image.vue    |          |                     |        | Qiniu           |
|   ├ cropper.vue  |          | ?noSave=1 可选参数   |        | Tencent COS     |
|   └ QR-code.vue  |          +---------------------+        | Huawei OBS      |
| selectFile.vue   |                  |                      | AWS S3          |
+------------------+           upload.NewOss()                | MinIO           |
                               工厂按 oss-type 选择            | Cloudflare R2   |
                                      |                      +-----------------+
                               +-------------+
                               | upload.OSS  |
                               | (interface) |
                               +-------------+
```

核心设计思想：通过 `OSS` interface 抽象上传和删除操作，使用工厂模式按配置切换存储后端，业务代码无需关心具体存储类型。

## 2. OSS 接口抽象

**文件**: `server/utils/upload/upload.go`

```go
// OSS 对象存储接口
type OSS interface {
    UploadFile(file *multipart.FileHeader) (string, string, error)
    DeleteFile(key string) error
}
```

- `UploadFile` 返回值：`(fileUrl, key, error)` — fileUrl 是可访问的完整 URL，key 是存储路径标识（用于删除）
- `DeleteFile` 参数：`key` 即 UploadFile 返回的第二个值

### 工厂函数 NewOss()

```go
func NewOss() OSS {
    switch global.HAB_CONFIG.System.OssType {
    case "local":          return &Local{}
    case "qiniu":          return &Qiniu{}
    case "tencent-cos":    return &TencentCOS{}
    case "aliyun-oss":     return &AliyunOSS{}
    case "huawei-obs":     return HuaWeiObs
    case "aws-s3":         return &AwsS3{}
    case "cloudflare-r2":  return &CloudflareR2{}
    case "minio":          return minioClient  // 含初始化逻辑，失败 panic
    default:               return &Local{}
    }
}
```

未配置或配置无效时默认使用本地存储。MinIO 在工厂函数中直接初始化客户端（`GetMinio()`），初始化失败会 panic。

## 3. 支持的云存储类型

| oss-type 值 | 存储类型 | 实现文件 | 配置结构体 | SDK 依赖 |
|-------------|---------|---------|-----------|----------|
| `local` | 本地文件系统 | `local.go` | `config.Local` | 无（标准库） |
| `aliyun-oss` | 阿里云 OSS | `aliyun_oss.go` | `config.AliyunOSS` | `aliyun/aliyun-oss-go-sdk` |
| `qiniu` | 七牛云 | `qiniu.go` | `config.Qiniu` | `qiniu/go-sdk/v7` |
| `tencent-cos` | 腾讯云 COS | `tencent_cos.go` | `config.TencentCOS` | `tencentyun/cos-go-sdk-v5` |
| `huawei-obs` | 华为云 OBS | `obs.go` | `config.HuaWeiObs` | `huaweicloud/huaweicloud-sdk-go-obs` |
| `aws-s3` | AWS S3 | `aws_s3.go` | `config.AwsS3` | `aws/aws-sdk-go` |
| `minio` | MinIO | `minio_oss.go` | `config.Minio` | `minio/minio-go/v7` |
| `cloudflare-r2` | Cloudflare R2 | `cloudflare_r2.go` | `config.CloudflareR2` | `aws/aws-sdk-go`（S3 兼容） |

所有实现文件路径前缀：`server/utils/upload/`

配置结构体路径前缀：`server/config/oss_*.go`

总配置结构体在 `server/config/config.go` 中挂载：

```go
type Server struct {
    // ...
    Local        Local        `mapstructure:"local" yaml:"local"`
    Qiniu        Qiniu        `mapstructure:"qiniu" yaml:"qiniu"`
    AliyunOSS    AliyunOSS    `mapstructure:"aliyun-oss" yaml:"aliyun-oss"`
    HuaWeiObs    HuaWeiObs    `mapstructure:"hua-wei-obs" yaml:"hua-wei-obs"`
    TencentCOS   TencentCOS   `mapstructure:"tencent-cos" yaml:"tencent-cos"`
    AwsS3        AwsS3        `mapstructure:"aws-s3" yaml:"aws-s3"`
    CloudflareR2 CloudflareR2 `mapstructure:"cloudflare-r2" yaml:"cloudflare-r2"`
    Minio        Minio        `mapstructure:"minio" yaml:"minio"`
}
```

## 4. 各云存储配置项详解

### 4.1 本地存储 (local)

```yaml
local:
  path: uploads/file         # 文件访问路径（URL 中的路径）
  store-path: uploads/file   # 文件实际存储路径（磁盘路径）
```

**配置结构体** (`config/oss_local.go`)：

```go
type Local struct {
    Path      string `mapstructure:"path" yaml:"path"`
    StorePath string `mapstructure:"store-path" yaml:"store-path"`
}
```

**默认值**（`config/defaults.go`）：未配置 `oss-type` 时自动降级为 local。

**上传逻辑**：
- 文件名加密：原文件名 MD5 + `_` + 时间戳 + 原扩展名，如 `a1b2c3d4_20060102150405.jpg`
- 自动创建存储目录（`os.MkdirAll`）
- 通过 `io.Copy` 将上传文件流写入磁盘

**删除逻辑**：
- 空 key 检查
- 路径遍历攻击防护：拒绝包含 `..` 和 `\/:*?"<>|` 等特殊字符的 key
- 检查文件是否存在
- 使用 `sync.Mutex` 防止并发删除冲突

### 4.2 阿里云 OSS (aliyun-oss)

```yaml
aliyun-oss:
  endpoint: yourEndpoint              # OSS 服务端点
  access-key-id: yourAccessKeyId      # AccessKey ID
  access-key-secret: yourAccessKeySecret  # AccessKey Secret
  bucket-name: yourBucketName         # Bucket 名称
  bucket-url: yourBucketUrl           # Bucket 访问域名
  base-path: yourBasePath             # 文件存储基础路径
```

**配置结构体** (`config/oss_aliyun.go`)：

```go
type AliyunOSS struct {
    Endpoint        string `mapstructure:"endpoint" yaml:"endpoint"`
    AccessKeyId     string `mapstructure:"access-key-id" yaml:"access-key-id"`
    AccessKeySecret string `mapstructure:"access-key-secret" yaml:"access-key-secret"`
    BucketName      string `mapstructure:"bucket-name" yaml:"bucket-name"`
    BucketUrl       string `mapstructure:"bucket-url" yaml:"bucket-url"`
    BasePath        string `mapstructure:"base-path" yaml:"base-path"`
}
```

**文件存储路径**：`{base-path}/uploads/{YYYY-MM-DD}/{原文件名}`

**返回 URL**：`{bucket-url}/{完整路径}`

**实现细节**：每次上传都创建新的 `oss.Client` 和 `Bucket` 实例（通过 `NewBucket()` 辅助函数），使用 `bucket.PutObject` 上传文件流。

### 4.3 七牛云 (qiniu)

```yaml
qiniu:
  zone: ZoneHuadong         # 存储区域
  bucket: yourBucket         # 空间名称
  img-path: yourImgPath      # CDN 加速域名
  access-key: yourAccessKey  # AK
  secret-key: yourSecretKey  # SK
  use-https: false           # 是否使用 HTTPS
  use-cdn-domains: false     # 上传是否使用 CDN 加速
```

**配置结构体** (`config/oss_qiniu.go`)：

```go
type Qiniu struct {
    Zone          string `mapstructure:"zone" yaml:"zone"`
    Bucket        string `mapstructure:"bucket" yaml:"bucket"`
    ImgPath       string `mapstructure:"img-path" yaml:"img-path"`
    AccessKey     string `mapstructure:"access-key" yaml:"access-key"`
    SecretKey     string `mapstructure:"secret-key" yaml:"secret-key"`
    UseHTTPS      bool   `mapstructure:"use-https" yaml:"use-https"`
    UseCdnDomains bool   `mapstructure:"use-cdn-domains" yaml:"use-cdn-domains"`
}
```

**支持的 Zone 值**：
- `ZoneHuadong` — 华东
- `ZoneHuabei` — 华北
- `ZoneHuanan` — 华南
- `ZoneBeimei` — 北美
- `ZoneXinjiapo` — 新加坡

**文件名格式**：`{unix时间戳}{原文件名}`，如 `1709280000photo.jpg`

**返回 URL**：`{img-path}/{key}`

**实现细节**：使用 `qbox.NewMac` + `storage.FormUploader` 进行表单上传，通过 `PutPolicy.UploadToken` 生成上传凭证。

### 4.4 腾讯云 COS (tencent-cos)

```yaml
tencent-cos:
  bucket: yourBucket         # Bucket 名称
  region: ap-beijing         # 地域
  secret-id: yourSecretId    # SecretId
  secret-key: yourSecretKey  # SecretKey
  base-url: https://xxx.cos.ap-beijing.myqcloud.com  # 访问域名
  path-prefix: yourPrefix    # 路径前缀
```

**配置结构体** (`config/oss_tencent.go`)：

```go
type TencentCOS struct {
    Bucket     string `mapstructure:"bucket" yaml:"bucket"`
    Region     string `mapstructure:"region" yaml:"region"`
    SecretID   string `mapstructure:"secret-id" yaml:"secret-id"`
    SecretKey  string `mapstructure:"secret-key" yaml:"secret-key"`
    BaseURL    string `mapstructure:"base-url" yaml:"base-url"`
    PathPrefix string `mapstructure:"path-prefix" yaml:"path-prefix"`
}
```

**COS 客户端 URL 自动拼接**：`https://{bucket}.cos.{region}.myqcloud.com`

**文件存储路径**：`{path-prefix}/{unix时间戳}{原文件名}`

**返回 URL**：`{base-url}/{path-prefix}/{fileKey}`

**注意**：`UploadFile` 中上传失败会 `panic` 而非返回 error，这是已知的代码问题。

### 4.5 华为云 OBS (huawei-obs)

```yaml
huawei-obs:
  path: yourPath             # 文件访问路径前缀
  bucket: yourBucket         # Bucket 名称
  endpoint: yourEndpoint     # OBS 服务端点
  access-key: yourAccessKey  # AK
  secret-key: yourSecretKey  # SK
```

**配置结构体** (`config/oss_huawei.go`)：

```go
type HuaWeiObs struct {
    Path      string `mapstructure:"path" yaml:"path"`
    Bucket    string `mapstructure:"bucket" yaml:"bucket"`
    Endpoint  string `mapstructure:"endpoint" yaml:"endpoint"`
    AccessKey string `mapstructure:"access-key" yaml:"access-key"`
    SecretKey string `mapstructure:"secret-key" yaml:"secret-key"`
}
```

**特殊行为**：
- 使用 **原始文件名** 上传（不做加密或时间戳处理）
- 设置了 Content-Type 为文件原始类型（`file.Header.Get("content-type")`）
- 使用全局单例 `HuaWeiObs`（`var HuaWeiObs = new(Obs)`）
- 每次操作都重新创建 `obs.ObsClient`

**返回路径**：`{path}/{filename}`

### 4.6 AWS S3 (aws-s3)

```yaml
aws-s3:
  bucket: yourBucket              # Bucket 名称
  region: us-east-1               # 区域
  endpoint: ""                    # 自定义端点（可兼容 MinIO）
  secret-id: yourSecretId         # Access Key ID
  secret-key: yourSecretKey       # Secret Access Key
  base-url: https://xxx           # 访问域名
  path-prefix: yourPrefix         # 路径前缀
  s3-force-path-style: false      # 强制路径风格（MinIO 兼容需设为 true）
  disable-ssl: false              # 禁用 SSL
```

**配置结构体** (`config/oss_aws.go`)：

```go
type AwsS3 struct {
    Bucket           string `mapstructure:"bucket" yaml:"bucket"`
    Region           string `mapstructure:"region" yaml:"region"`
    Endpoint         string `mapstructure:"endpoint" yaml:"endpoint"`
    SecretID         string `mapstructure:"secret-id" yaml:"secret-id"`
    SecretKey        string `mapstructure:"secret-key" yaml:"secret-key"`
    BaseURL          string `mapstructure:"base-url" yaml:"base-url"`
    PathPrefix       string `mapstructure:"path-prefix" yaml:"path-prefix"`
    S3ForcePathStyle bool   `mapstructure:"s3-force-path-style" yaml:"s3-force-path-style"`
    DisableSSL       bool   `mapstructure:"disable-ssl" yaml:"disable-ssl"`
}
```

**实现细节**：
- 使用 `s3manager.NewUploader` 进行上传，SDK 支持大文件自动分片
- 删除后调用 `svc.WaitUntilObjectNotExists` 等待对象确认删除
- `s3-force-path-style` 和 `endpoint` 配置可用于兼容 MinIO 等 S3 兼容存储，提供另一种 MinIO 接入方式

**文件存储路径**：`{path-prefix}/{unix时间戳}{原文件名}`

**返回 URL**：`{base-url}/{path-prefix}/{fileKey}`

### 4.7 MinIO (minio)

```yaml
minio:
  endpoint: localhost:9000         # MinIO 服务地址
  access-key-id: yourAccessKeyId   # Access Key
  access-key-secret: yourSecret    # Secret Key
  bucket-name: yourBucket          # Bucket 名称
  use-ssl: false                   # 是否使用 SSL
  base-path: ""                    # 存储基础路径（空则使用 "uploads"）
  bucket-url: http://localhost:9000/yourBucket  # 访问 URL
```

**配置结构体** (`config/oss_minio.go`)：

```go
type Minio struct {
    Endpoint        string `mapstructure:"endpoint" yaml:"endpoint"`
    AccessKeyId     string `mapstructure:"access-key-id" yaml:"access-key-id"`
    AccessKeySecret string `mapstructure:"access-key-secret" yaml:"access-key-secret"`
    BucketName      string `mapstructure:"bucket-name" yaml:"bucket-name"`
    UseSSL          bool   `mapstructure:"use-ssl" yaml:"use-ssl"`
    BasePath        string `mapstructure:"base-path" yaml:"base-path"`
    BucketUrl       string `mapstructure:"bucket-url" yaml:"bucket-url"`
}
```

**特殊行为**：
- **初始化失败会 panic** — 强制要求 MinIO 服务可用
- 初始化时自动创建 Bucket（`MakeBucket`，已存在则忽略）
- 使用全局单例 `MinioClient`（`var MinioClient *Minio`），避免重复初始化
- 文件名 MD5 加密：`MD5(原文件名去扩展名) + 原扩展名`
- 存储路径：`{base-path}/{YYYY-MM-DD}/{md5filename.ext}`（base-path 为空时默认 `uploads`）
- 上传超时设置为 10 分钟（`context.WithTimeout`）
- `PutObject` 对大文件自动切换为分片上传
- Content-Type 统一设为 `application/octet-stream`

**返回 URL**：`{bucket-url}/{key}`

### 4.8 Cloudflare R2 (cloudflare-r2)

```yaml
cloudflare-r2:
  bucket: yourBucket                     # Bucket 名称
  base-url: https://xxx                  # 公开访问域名
  path: uploads                          # 存储路径前缀
  account-id: yourAccountId              # Cloudflare Account ID
  access-key-id: yourAccessKeyId         # R2 Access Key ID
  secret-access-key: yourSecretAccessKey # R2 Secret Access Key
```

**配置结构体** (`config/oss_cloudflare.go`)：

```go
type CloudflareR2 struct {
    Bucket          string `mapstructure:"bucket" yaml:"bucket"`
    BaseURL         string `mapstructure:"base-url" yaml:"base-url"`
    Path            string `mapstructure:"path" yaml:"path"`
    AccountID       string `mapstructure:"account-id" yaml:"account-id"`
    AccessKeyID     string `mapstructure:"access-key-id" yaml:"access-key-id"`
    SecretAccessKey string `mapstructure:"secret-access-key" yaml:"secret-access-key"`
}
```

**实现细节**：
- 底层使用 AWS SDK（S3 兼容协议）
- Endpoint 自动拼接：`{account-id}.r2.cloudflarestorage.com`
- Region 固定为 `auto`
- 文件名格式：`{unix时间戳}_{原文件名}`
- 使用 `s3manager.NewUploader`，支持大文件自动分片
- 删除后调用 `WaitUntilObjectNotExists` 确认删除

**返回 URL**：`{base-url}/{path}/{fileKey}`

## 5. 切换存储类型

在 `config.yaml`（或 `config.local.yaml`）中修改 `system.oss-type` 字段即可切换：

```yaml
system:
  oss-type: local  # 可选值: local, aliyun-oss, qiniu, tencent-cos, huawei-obs, aws-s3, minio, cloudflare-r2
```

同时需要填写对应存储类型的配置节。切换后无需修改任何业务代码，`NewOss()` 工厂函数会自动选择对应实现。

**默认值行为**（`config/defaults.go`）：

```go
func (c *System) setDefaults() {
    if c.OssType == "" {
        c.OssType = "local"
    }
}
```

## 6. 前端上传组件

前端提供四种上传组件，均位于 `web/src/components/upload/` 目录。所有组件上传地址统一为 `{baseUrl}/fileUploadAndDownload/upload`。

### 6.1 普通上传 — common.vue

**组件名**: `UploadCommon`

- 支持多文件上传（`multiple`）
- 上传前校验：
  - 仅允许图片（jpg/png/svg/webp）和视频（mp4/webm）
  - 图片大小限制 500KB（未压缩）
  - 视频大小限制 5MB
- 上传时携带 `classId` 作为附加数据

| Props | 类型 | 默认值 | 说明 |
|-------|------|--------|------|
| `classId` | Number | 0 | 文件分类 ID |

| Events | 说明 |
|--------|------|
| `on-success` | 上传成功，参数为 `data.file.url` |

### 6.2 压缩上传 — image.vue

**组件名**: `UploadImage`

- 仅支持 jpg/png 格式
- 文件超过 `fileSize` 阈值时自动执行前端压缩
- 使用 `ImageCompress` 工具类（`@/utils/image`）进行压缩
- 单文件上传（`multiple: false`）

| Props | 类型 | 默认值 | 说明 |
|-------|------|--------|------|
| `imageUrl` | String | `''` | 当前图片 URL |
| `fileSize` | Number | 2048 | 压缩阈值（KB），超出后执行压缩 |
| `maxWH` | Number | 1920 | 图片长宽上限 |
| `classId` | Number | 0 | 文件分类 ID |

| Events | 说明 |
|--------|------|
| `on-success` | 上传成功，参数为 `data.file.url` |

### 6.3 裁剪上传 — cropper.vue

**组件名**: `CropperImage`

- 使用 `vue-cropper` 库实现图片裁剪
- 手动上传模式（`auto-upload: false`），选择文件后打开裁剪对话框
- 支持旋转（左/右 90 度）和缩放操作
- 预设裁剪比例：1:1, 16:9, 9:16, 4:3, 自由比例
- 裁剪后输出为 JPEG 格式，文件名为 `{时间戳}.jpg`
- 文件大小限制 8MB
- 裁剪对话框宽 1200px，包含左侧编辑区和右侧预览区

| Props | 类型 | 默认值 | 说明 |
|-------|------|--------|------|
| `classId` | Number | 0 | 文件分类 ID |

| Events | 说明 |
|--------|------|
| `on-success` | 上传成功，参数为 `data.url` |

### 6.4 扫码上传 — QR-code.vue

**组件名**: `QRCodeUpload`

- 生成包含上传页面 URL 的二维码，用户扫码后在手机端上传
- 二维码 URL 格式：`{当前域名}/#/scanUpload?id={classId}&token={userToken}&t={timestamp}`
- 使用 `vue-qr` 库生成二维码
- 二维码带 logo（项目 logo.svg）
- 点击"完成上传"手动关闭弹窗，触发 `on-success` 事件

| Props | 类型 | 默认值 | 说明 |
|-------|------|--------|------|
| `classId` | Number | 0 | 文件分类 ID |

| Events | 说明 |
|--------|------|
| `on-success` | 点击完成上传后触发，参数为空字符串 |

### 6.5 通用文件上传 — selectFile.vue

**文件**: `web/src/components/selectFile/selectFile.vue`

**组件名**: `UploadCommon`（注意：与 common.vue 同名）

- 上传地址带 `?noSave=1` 参数，表示上传后不保存到媒体库
- 支持多文件上传
- 使用 `v-model:file-list` 管理文件列表
- 支持文件数量限制（`limit` prop）和文件类型限制（`accept` prop）
- 使用 `defineModel` 双向绑定文件列表

| Props | 类型 | 默认值 | 说明 |
|-------|------|--------|------|
| `limit` | Number | 3 | 最大上传文件数 |
| `accept` | String | `''` | 允许的文件类型 |

## 7. 媒体库组件 — selectImage.vue

**文件**: `web/src/components/selectImage/selectImage.vue`

这是一个完整的媒体库管理组件，以 Drawer 抽屉形式展示，整合了所有上传组件和文件管理功能。

**核心功能**：
1. **文件浏览**：分页展示已上传文件，支持图片/视频预览
2. **关键词搜索**：按文件名或备注搜索
3. **分类管理**：左侧树形分类导航，支持添加/编辑/删除分类
4. **多种上传方式**：同时提供普通上传、压缩上传、裁剪上传、扫码上传四种方式
5. **文件操作**：删除文件、编辑文件名/备注
6. **单选/多选模式**：通过 `multiple` prop 控制

| Props | 类型 | 默认值 | 说明 |
|-------|------|--------|------|
| `multiple` | Boolean | false | 是否多选模式 |
| `fileType` | String | `''` | 限制文件类型（`image` 或 `video`） |
| `maxUpdateCount` | Number | 0 | 多选最大数量（0=不限） |
| `rounded` | Boolean | false | 是否圆角显示 |

**使用方式**（双向绑定）：

```vue
<!-- 单选 -->
<selectImage v-model="imageUrl" />

<!-- 多选 -->
<selectImage v-model="imageList" :multiple="true" :max-update-count="5" />
```

**依赖的 API**：
- `getFileList` — 分页获取文件列表
- `deleteFile` — 删除文件
- `editFileName` — 编辑文件名
- `getCategoryList` / `addCategory` / `deleteCategory` — 分类管理

## 8. 上传相关 API 接口

**文件**: `web/src/api/fileUploadAndDownload.js`

| 函数名 | 方法 | 路径 | 说明 |
|--------|------|------|------|
| `uploadFile` | POST | `/fileUploadAndDownload/upload` | 上传文件（JS 调用） |
| `getFileList` | POST | `/fileUploadAndDownload/getFileList` | 分页获取文件列表 |
| `deleteFile` | POST | `/fileUploadAndDownload/deleteFile` | 删除文件（传 id） |
| `editFileName` | POST | `/fileUploadAndDownload/editFileName` | 编辑文件名或备注 |
| `importURL` | POST | `/fileUploadAndDownload/importURL` | 导入外部 URL |

**上传接口的两种调用方式**：

1. **el-upload 组件直接调用**（common.vue / image.vue / cropper.vue）：通过 `:action` 属性指定 URL，携带 `classId` 作为 `:data`，成功响应中 `data.file.url` 为文件访问地址
2. **selectFile.vue**：URL 附加 `?noSave=1` 查询参数，上传文件但不写入媒体库记录

**Casbin 权限**（`server/model/system/request/sys_casbin.go`）：上传接口已预置在默认 Casbin 策略中：`{Path: "/fileUploadAndDownload/upload", Method: "POST"}`

## 9. 大文件与分片上传

当前代码中未实现显式的前端断点续传功能。但以下存储类型内置了分片上传支持：

- **MinIO**: `PutObject` 方法对大文件自动切换为分片上传（SDK 内置行为），上传超时 10 分钟
- **AWS S3**: 使用 `s3manager.NewUploader`，SDK 自动处理大文件分片
- **Cloudflare R2**: 底层使用 AWS SDK，同样支持自动分片

项目中还包含断点续传工具函数（`server/utils/breakpoint_continue.go`），提供 `CheckMd5` 等辅助方法。

如需前端断点续传（用户可暂停/继续），需额外实现分片上传 API 和前端控制逻辑。

## 10. 本地存储的静态文件服务

在 `initialize/router.go` 中配置了本地文件的 HTTP 访问：

```go
if global.HAB_CONFIG.Local.StorePath != "" {
    Router.StaticFS(global.HAB_CONFIG.Local.StorePath,
        justFilesFilesystem{http.Dir(global.HAB_CONFIG.Local.StorePath)})
}
```

`justFilesFilesystem` 包装器确保只能访问文件，不能列目录。

## 11. 注意事项和常见问题

### 安全相关

1. **本地存储路径遍历防护**: `Local.DeleteFile` 会检查 key 中的 `..` 和特殊字符（`\/:*?"<>|`），防止路径遍历攻击
2. **文件名加密**: 本地存储和 MinIO 使用 MD5 加密原始文件名，避免文件名冲突和中文路径问题
3. **并发安全**: 本地存储删除操作使用 `sync.Mutex` 保证并发安全
4. **目录列表禁用**: `justFilesFilesystem` 确保静态文件服务不会暴露目录结构

### 配置相关

5. **默认降级**: 未配置 `oss-type` 或配置无效值时，自动降级为本地存储
6. **MinIO 强制可用**: MinIO 初始化失败会 panic，确保配置了 MinIO 时服务必须可用。如果只是想试用，建议先使用 `local`
7. **AWS S3 兼容**: `aws-s3` 配置中的 `endpoint` 和 `s3-force-path-style` 可用于对接 MinIO 等 S3 兼容存储，提供另一种 MinIO 接入方式

### 已知代码问题

8. **腾讯云 COS panic**: `TencentCOS.UploadFile` 中上传失败会调用 `panic(err)` 而非返回 error，生产环境需注意
9. **华为云 OBS 文件名冲突**: 华为云 OBS 使用原始文件名，不做任何加密或时间戳处理，同名文件会被覆盖
10. **Content-Type 不一致**: 仅华为云 OBS 设置了正确的 Content-Type，MinIO 统一设为 `application/octet-stream`，其他实现由 SDK 自动处理

### 性能相关

11. **前端压缩**: 使用压缩上传组件（`image.vue`）可在前端压缩图片，减少网络传输和存储空间占用
12. **MinIO 单例**: MinIO 客户端使用全局单例模式，避免重复建立连接
13. **上传超时**: MinIO 上传超时为 10 分钟，大文件上传需注意网络稳定性
14. **阿里云非单例**: 阿里云 OSS 每次上传都创建新的 Client 和 Bucket 实例，高并发场景可能需要优化

### 开发建议

15. **新增存储类型的步骤**:
    1. 在 `server/config/` 下新建 `oss_xxx.go`，定义配置结构体
    2. 在 `server/config/config.go` 的 `Server` 结构体中添加字段
    3. 在 `server/utils/upload/` 下新建实现文件，实现 `OSS` interface 的 `UploadFile` 和 `DeleteFile`
    4. 在 `server/utils/upload/upload.go` 的 `NewOss()` switch 中添加 case
    5. 在 `config.yaml` 中添加对应配置节

16. **文件大小限制**: 前端组件中的文件大小限制（500KB/5MB/8MB）目前为硬编码，代码中有 `@todo` 注释标记需要支持项目级配置
17. **上传路径规范**: 各存储实现的路径格式不完全一致（有的按日期分目录、有的不分，有的 MD5 加密文件名、有的保留原名），团队可根据需要统一
18. **noSave 参数**: `selectFile.vue` 使用 `?noSave=1` 上传文件但不保存到媒体库，适用于临时文件上传场景（如 Excel 导入）
