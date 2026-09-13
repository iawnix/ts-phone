<p align="center">
  <img src="apps/mobile/assets/branding/ts-phone-mark.png" alt="TS Phone 标志" width="104">
</p>

# TS Phone

[English](README.md)

TS Phone 是 [TSPi](https://github.com/iawnix/TSPi) 的移动端组件。它通过经过认证的 Host 服务，把手机连接到 TSPi 工作区、Pi 会话和研究活动。

本仓库包含 Flutter Android 客户端、TypeScript Host broker、Phone 协议定义，以及 TSPi 组件安装器使用的发布工具。

## 功能

- 浏览项目、会话、分支和已保存的会话历史。
- 创建、重命名、归档、恢复和删除项目与会话。
- 通过 SSE 查看消息、工具调用、研究活动、错误和运行状态。
- 手机和终端通过同一个工作区队列发送消息。
- 为新消息和排队消息选择模型，并查看 Bridge 报告的当前模型。
- 支持中英文界面、浅色和深色主题、大字体及减少动画。
- 在终端、浏览器和手机之间继续同一个会话。

## 架构

```text
Flutter 应用
    |
    | HTTPS + SSE
    v
反向代理
    |
    | 回环 HTTP
    v
TS Phone broker
    |                 |
    | 启动 Worker      | 经过认证的 Unix socket
    v                 v
TSPi/Pi 进程 <-> TSPi Bridge
```

TSPi 保存科学状态和 Pi 会话文件。Phone broker 负责认证、项目与会话元数据、实时事件传递、请求队列，以及 TSPi Worker 的生命周期。Pi JSONL 保存会话历史，broker 保存待处理请求和投递回执。

多个客户端可以同时查看一个项目。消息按到达顺序执行，每个工作区同时运行一个 Agent 回合；不同工作区可以并行运行。

## 安装

TSPi 安装器从 GitHub 部署 Phone broker 并配置服务。Android 客户端作为签名后的 GitHub Release 产物发布。请从
[iawnix/ts-phone/releases](https://github.com/iawnix/ts-phone/releases) 下载对应版本，在当前 Android 手机上安装 `arm64-v8a` APK。

Host 安装需要 Node.js 和 npm。Flutter 与 Android SDK 仅用于移动端开发和维护者发布构建。

完整的 Host 安装流程见 TSPi [安装指南](https://github.com/iawnix/TSPi/blob/main/docs/INSTALLATION.md)。APK 版本、摘要、组件归档和发布验证见[产物说明](docs/artifacts.md)。

## 从源码运行 broker

在仓库根目录安装依赖：

```bash
git clone https://github.com/iawnix/ts-phone.git
cd ts-phone
npm ci
```

配置 Host 路径并启动 broker：

```bash
export TS_PHONE_WORKSPACES=/absolute/path/to/tspi/workspaces
export TS_PHONE_TSPI=/absolute/path/to/tspi/TSPi
export TS_PHONE_STATE_DIR=/absolute/path/to/ts-phone-dev/state
export TS_PHONE_BRIDGE_SOCKET=/absolute/path/to/ts-phone-dev/run/bridge.sock
export TS_PHONE_BRIDGE_SECRET_FILE=/absolute/path/to/ts-phone-dev/state/bridge.secret
npm run dev
```

首次启动时，broker 会在配置的状态目录创建 API 和 Bridge 凭据。使用以下命令检查服务并读取本地 API token：

```bash
curl http://127.0.0.1:22113/healthz
TS_PHONE_STATE_DIR=/absolute/path/to/ts-phone-dev/state npm run ctl -- token
```

手机远程访问时，在回环 broker 前配置 HTTPS 反向代理，然后在应用中填写 URL 和 API token。Host 与 TSPi 进程应使用同一个 Unix 用户运行，以便访问 Bridge socket。

已安装的 TSPi 默认使用 Host 会话终端；`--phone` 是连接同一服务的别名。工作区和会话命令见 TSPi [终端指南](https://github.com/iawnix/TSPi/blob/main/docs/TERMINAL.md)。

## 从源码运行 Android 客户端

```bash
cd apps/mobile
flutter pub get
flutter devices
flutter run -d DEVICE_ID
```

在应用中填写 broker 的 HTTPS URL 和 API token。正式 Android 用户应直接安装 GitHub Release 中的签名 APK。

## 开发检查

在仓库根目录运行 broker 和发布检查：

```bash
npm run typecheck
npm test
npm run test:release
npm run build
TS_PHONE_SMOKE_PORT=23113 npm run smoke
```

在 `apps/mobile` 中运行移动端检查：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

分层迭代命令可以缩短反馈时间：

```bash
npm run iterate:dev
npm run iterate:candidate
npm run iterate:release
```

`candidate` 构建本地 arm64 APK。`release` 构建三种 ABI 的 APK、AAB、源码证明和经过验证的 TS Phone 组件归档。

## Android 发布

`TS Phone Android Release` 工作流响应类似 `ts-phone-v0.18.3+48` 的 tag，也可以手动选择 release tag。它会把签名 APK、AAB、源码证明和组件归档发布到 GitHub Release 页面。

维护者按照[产物说明](docs/artifacts.md)配置签名 Secret，然后推送与 `apps/mobile/pubspec.yaml` 中移动端版本一致的 tag。

## 安全

API token 可以控制所配置的 TSPi 安装，包括项目和会话管理、启动 Worker、发送提示词、生命周期操作和删除。请将它作为私密凭据保存，并对 Host 之外的连接使用 HTTPS。

会话投影可能包含可见文本、工具参数和工具结果。请勿把凭据放入会话、截图、日志或源码。完整信任模型见[安全说明](docs/security.md)。

## 平台状态

| 组件 | 版本 / 支持情况 |
| --- | --- |
| Host | 0.9.1；API v4、Events v3、Bridge v3、`terminal.attach` |
| Android | App 0.18.3+48；Android 7.0 或更高版本 |
| TSPi | 0.15.0；终端连接、精确会话 Worker 和生命周期控制 |
| iOS | 包含 Flutter 源码；发布构建需要 macOS 和 Apple 签名 |

## 文档

- [架构](docs/architecture.md)
- [安全](docs/security.md)
- [部署](docs/deployment.md)
- [恢复](docs/recovery.md)
- [构建产物](docs/artifacts.md)
