# TS Phone

TS Phone 是 TSPi Host 的 Flutter 客户端。Host 将工作区内的请求转交普通 Pi 会话，
Pi 负责执行和 JSONL 历史。手机展示同一会话，并提供任务监控的状态和启停入口。

## 运行架构

```text
TS Phone -- 出站 WSS --> TSPi Relay <-- 出站 WSS -- TSPi Host
                                                    |
                                              Pi 会话 bridge
                                                    |
                                            工作区 / 本地终端
```

使用 TSPi 打开工作区；需要时会自动启动安装级 Host：

```bash
./TSPi --workspace reaction-a
```

在该安装中运行 `TSPi phone pair`，然后在 App 中输入输出的 TSPi Relay URL 和 8 位
配对码。App 使用一次性配对码换取本设备独立、可撤销的授权。手机通过
`tspi-link.v1` WebSocket 子协议承载 `tspi-host/1` UTF-8 NDJSON。
会话操作始终包含工作区和会话 ID。断线后重新 attach 获取完整快照；投递不确定的
消息重试复用原消息 ID，避免新建一次输入。

## 仓库结构

- `apps/mobile`：Flutter Android/iOS 应用。
- `apps/mobile/lib/data/tspi_link_pairing.dart`：一次性设备配对。
- `apps/mobile/lib/data/host_rpc_client.dart`：通过 TSPi Link 使用 Host JSON RPC。
- `apps/mobile/lib/data/host_gateway.dart`：会话、模型、监控接口适配。
- `apps/mobile/lib/features/monitors/monitor_page.dart`：项目任务监控列表和启停。
- 原 Pi v8/Chord adapter 保留用于兼容测试，应用默认使用 `HostGateway`。
- `apps/mobile/tool/build_release_android.sh`：带源码证明的签名 APK/AAB 构建脚本。
- `apps/mobile/tool/mobile-build-attestation.py`：可复现源码与构建产物证明工具。

本仓库有意不再包含 Node 服务端或 TS Phone 协议包；Host 实现在 TSPi
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
