# TS Phone

TS Phone 是 Pi App Server 的 Flutter 客户端。本仓库不再包含共享 Host、
worker supervisor、REST/SSE broker 或本地 bridge。每个工作区运行一个 Pi
App Server，由它独占会话目录、对话历史、模型状态和工作区锁。

## 运行架构

```text
                         Pi Radius
                             |
                         WebSocket
                             |
TS Phone（Flutter） ---- Pi App Server ---- 本地 TSPi 终端
                             |
                           工作区
```

使用 TSPi 为每个工作区启动 App Server：

```bash
./TSPi --app-server --workspace reaction-a
```

本地终端自动连接该工作区的 App Server：

```bash
./TSPi --workspace reaction-a
```

手机通过 Pi Radius 连接同一个 App Server。在 App 的连接页面配置 Radius
网关、App Server UUID 和 bearer token。手机使用
`pi-session-relay.client.v1` WebSocket 子协议和 Pi protocol v8，不再连接
TS Phone 服务。

## 仓库结构

- `apps/mobile`：Flutter Android/iOS 应用。
- `apps/mobile/lib/data/pi_app_server_client.dart`：Pi v8 帧和 Chord 服务客户端。
- `apps/mobile/lib/data/app_server_gateway.dart`：原生会话、历史和模型目录投影。
- `apps/mobile/tool/build_release_android.sh`：带源码证明的签名 APK/AAB 构建脚本。
- `apps/mobile/tool/mobile-build-attestation.py`：可复现源码与构建产物证明工具。

本仓库有意不再包含 Node 服务端或 TS Phone 协议包；App Server 实现在 TSPi
包中。

## 开发

安装 Flutter 3.44（或兼容的 stable 版本），然后运行：

```bash
cd apps/mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

根目录脚本执行相同检查：

```bash
./tool/iterate.sh dev
```

`candidate` 构建本地 arm64 APK，`release` 构建签名 Android 发布集。每个产物
都嵌入源码快照，发布文件只位于 `dist/android-current`。

## 安全边界

Bearer token 只用于 Radius WebSocket，由移动平台的安全存储保护，绝不会发送给
本地进程。App Server 的会话状态保留在服务器工作区；手机只保存 UI 偏好和最近
选择的会话。

详见 [docs/architecture.md](docs/architecture.md) 和
[docs/deployment.md](docs/deployment.md)。
