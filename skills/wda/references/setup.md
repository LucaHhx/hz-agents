# WDA 安装与启动指南

## 方式一：通过 Appium 安装（推荐）

### 1. 安装依赖

```bash
# 安装 Node.js (如已有可跳过)
brew install node

# 安装 Appium
npm install -g appium

# 安装 XCUITest 驱动 (会自动下载 WDA)
appium driver install xcuitest
```

### 2. 编译 WDA

```bash
# 自动编译
appium driver run xcuitest build-wda

# 或手动用 Xcode 编译
cd ~/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent
xcodebuild -project WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build-for-testing
```

### 3. 启动 WDA (模拟器)

```bash
# 通过 xcodebuild 直接启动
xcodebuild test \
  -project ~/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -allowProvisioningUpdates
```

WDA 启动后监听 `http://localhost:8100`。

### 4. 验证

```bash
curl http://localhost:8100/status
```

## 方式二：通过 Xcode 手动编译

### 1. 获取 WDA 源码

```bash
git clone https://github.com/appium/WebDriverAgent.git
cd WebDriverAgent
```

### 2. Xcode 配置

1. 用 Xcode 打开 `WebDriverAgent.xcodeproj`
2. 选择 **WebDriverAgentRunner** target
3. 在 General → Signing 中选择你的 Development Team
4. 如果是真机，需要修改 Bundle Identifier 为唯一值（如 `com.yourname.WebDriverAgentRunner`）

### 3. 编译并运行

在 Xcode 中选择目标设备，点击 Product → Test（或 Cmd+U）。

## 方式三：通过 tidevice (真机，免 Xcode 运行)

```bash
pip3 install tidevice

# 列出设备
tidevice list

# 启动已安装的 WDA (需要先通过 Xcode 安装一次)
tidevice -u <UDID> wdaproxy -B com.yourname.WebDriverAgentRunner.xctrunner --port 8100
```

## 真机额外要求

1. **Apple Developer 账号**（免费账号即可用于开发测试）
2. **开启开发者模式**：设置 → 隐私与安全性 → 开发者模式 → 开启并重启
3. **信任开发者证书**：设置 → 通用 → VPN 与设备管理 → 信任
4. **Xcode 签名配置**：为 WebDriverAgentLib 和 WebDriverAgentRunner 都配置签名

## 端口转发（真机）

真机上 WDA 不直接暴露 localhost，需要端口转发：

```bash
# 使用 iproxy (libimobiledevice)
brew install libimobiledevice
iproxy 8100 8100

# 或使用 tidevice
tidevice -u <UDID> relay 8100 8100
```

## 常见问题

| 问题 | 解决 |
|------|------|
| `curl: (7) Failed to connect` | WDA 未启动或端口不对 |
| Xcode 签名失败 | 检查 Development Team 和 Bundle ID |
| 真机连不上 | 检查端口转发是否运行 |
| 编译报错 provisioning | 登录 Apple Developer 账号，勾选 Automatically manage signing |
| WDA 启动后很快崩溃 | iOS 版本与 WDA 版本不匹配，更新 WDA |
