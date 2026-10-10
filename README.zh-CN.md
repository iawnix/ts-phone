# CoRHub

<img src="apps/mobile/assets/branding/corhub-mark.png" alt="CoRHub 螃蟹标志" width="144">

[English](README.md) · [下载 Android](https://github.com/iawnix/corhub/releases/latest) · [更新记录](CHANGELOG.md)

CoRHub 是 [CoRAgent](https://github.com/iawnix/coragent) 的 Android/iOS
Flutter 客户端。在手机上访问与终端相同的研究工作区和会话、发送消息、切换模型、
查看工具输出和管理任务监控。任务执行与持久化会话历史保留在 CoRAgent 服务端。

产品名称统一为：客户端 **CoRHub**，科研智能体 **CoRAgent**。本源码配套 CoRAgent 0.19 的不兼容身份切换，服务端和客户端需要一起更新，所有设备重新配对。

## 安装和连接

1. 从 GitHub 最新 Release 下载 **arm64-v8a release APK**，适用于大多数 Android
   手机。发布页还提供 armeabi-v7a / x86_64 APK、用于商店分发的 AAB、源码摘要证明
   和 `SHA256SUMS`。
2. 安装 CoRAgent，通过可信 HTTPS Link Relay 启用 Phone access。在服务端运行：

   ```bash
   coragent --workspace reaction-a
   coragent phone pair
   ```

3. 在 App 中输入 Relay URL、8 位配对码和设备名。配对码五分钟内有效，只能使用一次。

当前客户端面向 CoRAgent **0.19.0**，使用 `coragent-host/2` 和
`coragent-link.v1`。从旧版协议升级时，必须更新 App 并**重新配对**；旧
`rad_` 凭据不能复用。兼容性由接口合同决定，不要求手机与服务端版本号相同。
每个 Release 的说明会标注对应的服务端要求。

目前发布 Android 安装包。iOS 保留源码，需要在 macOS 上使用 Apple 签名团队和
provisioning profile 构建，暂不提供签名 iOS 下载。

## Monitor 与文件

从聊天标题栏打开 Monitor。任务与 Jobs 分别控制：暂停/恢复 Task Controller；
结束任务时明确选择保留 Jobs 或请求取消；也可单独请求取消一个 Job。
详情页收纳研究摘要和执行记录，Job 成功不代表研究任务完成。
需要服务端提供按会话限定的 `monitor/overview`、`monitor/task/*`、
`monitor/job/*` 等接口，以及 UserTask v2 / Research Snapshot v3；
不再使用旧的监控启用/禁用接口。

输入框 **+** 打开材料目录。支持文本、CSV/TSV、PNG/JPEG，以及原生基础
XYZ、MOL/SDF V2000、PDB、笛卡尔坐标 mmCIF 预览。结构查看保留文件原始坐标，
支持旋转、缩放和两原子测距，只展示首个模型/记录（备选位置 A）。每个文件
上限 8 MiB，结构上限 5,000 原子；推断连线不代表键级。目前不渲染分数坐标 CIF、
MOL V3000 或 PDF。文本/表格预览限 200,000 字符 / 200 行、30 列。

加入草稿时，Host 会校验文件版本并固定内容快照；输入框只显示可查看详情、
可移除的文件标签。发送仍走已有文本消息与 outbox，提交文件引用，不传文件字节。
需要配套 Host 的 `files/list`、`files/stat`、`files/read`、`files/pin` 能力；
旧 Host 会显示不可用。查看与测量不会调用模型。本次不包含上传或 Web 界面。

## 架构

```text
CoRHub -- WSS --> CoRAgent Link Relay <-- WSS -- CoRAgent Host
                                                       |
                                                  Pi Harness
                                                       |
                                                   工作区 / 终端
```

手机通过 Host API 使用工作区、会话、模型和监控。设备授权保存在平台安全存储中，
模型凭据、执行与会话存储由服务端负责。断线重连获取完整快照；手动重试保留原消息
ID。请使用可信 Relay：WSS 加密各段连接，但 Relay 可以读取转发流量。

## 开发

固定使用 Flutter **3.44.0**、Python **3.10+** 和已提交的 `pubspec.lock`。
Android 发布还需要 JDK 17、Android SDK 36。

```bash
python3 tool/version.py check
./tool/iterate.sh dev
```

该入口在私有源码副本中检查版本、运行发布工具测试、Dart 格式检查、Flutter 静态
分析和独立手机测试。先按[开发说明](docs/development.md)配置 SDK 与缓存路径。
真实 Host/Pi 联调使用单独的 CoRAgent 本地测试入口；自动化测试不代表实机验收。

## 仓库和版本发布

| 路径 | 职责 |
| --- | --- |
| `apps/mobile/lib/` | Flutter 界面、Host 客户端和本地设置 |
| `apps/mobile/test/` | 界面/单元测试，以及显式运行的 Host 联调 |
| `apps/mobile/tool/` | Android 签名、构建验证和源码摘要证明 |
| `tool/` | 版本管理与开发检查 |
| `.github/workflows/` | PR 检查与标签触发的 Android 发布 |
| `docs/` | 架构、开发、版本、部署与恢复说明 |

`apps/mobile/pubspec.yaml` 是**唯一版本来源**。准备发布时运行：

```bash
python3 tool/version.py set 0.19.1+63   # 示例：下一次兼容修复
# 补充对应 CHANGELOG.md 条目，验证并提交。
python3 tool/version.py tag
```

构建号始终递增，标签格式为 `corhub-v<version>+<build>`，正式附件不可覆盖。
详见[版本管理](docs/versioning.md)和[发布操作](docs/deployment.md)。本仓库只维护
手机客户端，CoRAgent Host 和 Link Relay 在服务端仓库维护。

其它文档：[架构](docs/architecture.md)、[发布产物](docs/artifacts.md)、
[安全](docs/security.md)、[恢复](docs/recovery.md)、[开发约定](AGENTS.md)。
