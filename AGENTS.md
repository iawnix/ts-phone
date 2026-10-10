# CoRHub 开发约定

## 项目边界

- 本仓库只维护 Flutter 手机客户端、客户端测试和移动发布工具。CoRAgent Host、Link Relay、Pi runtime 属于 `iawnix/coragent`，不要重新引入 Node 服务端或另一套会话数据库。
- 当前接口是 `coragent-host/2`、`coragent-link.v1` 和 `cad_` 设备令牌。协议变更必须核对两端合同；旧令牌不能通过替换前缀迁移。
- CoRAgent/Pi 拥有会话、执行、模型凭据和监控状态。手机只保存连接身份、界面偏好及有限的展示状态。
- 发送失败后的手动重试必须保留消息身份，不能自动重复提交变更请求。

## 开发与验证

- 开始前检查 `git status`，保留用户已有修改。分支使用 `codex/` 或有明确用途的名称。
- Flutter 固定为 `3.44.0`，提交应用的 `pubspec.lock`；Android 构建使用 JDK 17、Android SDK 36 / build-tools 36.0.0。本机已有软件在 `/home/iaw/soft`。
- 使用 `python3 tool/version.py check` 和 `./tool/iterate.sh dev`。后者在私有源码副本中执行 Python 发布工具测试、Dart 格式检查、Flutter analyze 和独立手机测试。
- 跨仓库真实 Host/Pi 联调通过服务端的 `tools/test/runner.py phone` 执行，见 `docs/development.md`。独立手机测试不能冒充 Host 联调，自动联调不能冒充 Android/iOS 实机验收。
- 普通测试只使用本地确定性模型、假凭据；真实模型或远程测试涉及外发时必须取得明确授权。
- 本机测试安装、SDK 副本、缓存、临时文件、日志、数据库和证据统一放在 `/home/iaw/project/TSPi/local_debug/`。不再使用 `/home/iaw/debug/tspi-test-env`。测试结束必须停止并删除测试开启的服务；不能影响用户现有服务。
- `local_debug/` 是私有目录，禁止提交 Git、纳入 npm/wheel/release/容器产物、上传 Actions artifacts/外部缓存/网盘/遥测/issue/PR 附件或外部模型。共享前必须取得对具体脱敏材料的明确授权。CI 使用独立 runner 的临时测试目录，也不上传测试目录或日志。

## 版本与发布

- `apps/mobile/pubspec.yaml` 的 `version: MAJOR.MINOR.PATCH+BUILD` 是唯一版本来源。禁止恢复独立的根目录 VERSION 或 npm 版本。
- 使用 `python3 tool/version.py set X.Y.Z+N` 同步修改版本和生成的 `lib/app_identity.dart`，不要手工修改生成文件。
- BUILD 每次发布必须递增，不能随 major/minor 重置。当前 Flutter split APK 使用 ABI 偏移；BUILD 暂限 1..999，超限前先设计兼容的 versionCode 迁移。
- 0.x 阶段不兼容的 Host 协议切换提升 minor；兼容修复提升 patch。日常提交不必改版本；准备发布时统一更新。
- 发布前更新 `CHANGELOG.md`，记录兼容性、迁移步骤、验证范围和限制。README 中不要维护另一份“最新版本”数字，使用 GitHub latest release 链接。
- 新 tag 必须是 `corhub-vX.Y.Z+N`；旧 `ts-phone-v*` 标签保留并参与构建号校验。新标签指向通过检查的干净提交。禁止移动/覆盖已发布 tag、替换正式附件或把旧包改名冒充新构建。失败后重跑同一 tag 只允许完成尚未发布的 draft。
- 正式构建由 GitHub Actions 从 tag 源码完成，包含三种 ABI 的签名 APK、AAB、源码摘要证明与 SHA256SUMS；本机私有测试产物不得上传。
- 不生成或替换生产签名身份。已有 Android 包名 `xyz.iawnix.ts_phone` 和生产证书必须保持；签名私钥与密码只能来自受保护目录/GitHub secrets，禁止输出或提交。
- 只有用户授权发布时才推送发布 tag、正式发布或修改仓库设置。一般代码工作可准备分支和 PR。

## 文档与界面

- 产品文案统一使用 CoRHub（客户端）和 CoRAgent（科研智能体）；配对、聊天作者、生成状态、错误提示和诊断页面都适用。保留真实协议、包标识、签名、安全存储、历史标签、命令及路径的准确值，不对这些技术标识做品牌替换。
- `README.md` / `README.zh-CN.md` 同步维护，文档命令使用 `coragent`，正文统一使用 CoRAgent，服务端实际仓库链接和命令按当前实现保留。
- 界面文案同时维护英文、中文 ARB 并生成本地化文件；保持可访问性、键盘、窄屏/宽屏与大字号行为。
- 不把开发路径、协议调试细节或凭据放进面向普通用户的界面。修改文档中的服务/存储说明时核对当前服务端实现。

- CoRHub 安装身份保留 `TS_PHONE_*` 环境变量/GitHub secrets、签名文件和别名、Android/iOS 包标识和安全存储命名空间。CoRAgent 0.19 切换为 `coragent-host/2`、`coragent-link.v1` 和 `cad_`；不保留旧协议，升级后重新配对。品牌 SVG 及生成方式见 `apps/mobile/assets/branding/README.md`。
