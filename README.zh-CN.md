# TS Phone

TS Phone 是 TSPi Pi App Server Host 的 Flutter 客户端。本仓库不再包含共享
Host、worker supervisor、REST/SSE broker 或本地 bridge。一个 Host 管理安装
目录下的多个工作区，Pi App Server 独占会话目录、对话历史、模型状态和工作区锁。

## 运行架构

```text
TS Phone -- 出站 WSS --> TSPi Relay <-- 出站 WSS -- TSPi Host
                                                    |
                                              Pi App Server
                                                    |
                                            工作区 / 本地终端
```

使用 TSPi 打开工作区；需要时会自动启动安装级 Host：

```bash
./TSPi --workspace reaction-a
```

在该安装中运行 `TSPi phone pair`，然后在 App 中输入输出的 TSPi Relay URL 和 8 位
配对码。App 使用一次性配对码换取本设备独立、可撤销的授权。手机通过
`tspi-link.v1` WebSocket 子协议承载 Pi protocol v8，通过
`tspi.workspace-directory` 浏览或创建项目，并使用绑定的 `workspaceId` 创建会话。

## 仓库结构

- `apps/mobile`：Flutter Android/iOS 应用。
- `apps/mobile/lib/data/tspi_link_pairing.dart`：一次性设备配对。
- `apps/mobile/lib/data/pi_app_server_client.dart`：TSPi Link 传输、Pi v8 帧和 Chord 服务客户端。
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

设备 token 只用于 TSPi Link WebSocket，由移动平台的安全存储保护，并且不会在连接
界面显示。App Server 的会话状态保留在服务器工作区；手机只保存 UI 偏好和最近
选择的会话。

详见 [docs/architecture.md](docs/architecture.md) 和
[docs/deployment.md](docs/deployment.md)。
