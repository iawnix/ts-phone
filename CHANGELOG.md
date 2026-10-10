# Changelog

Release versions follow `MAJOR.MINOR.PATCH+BUILD`. Unreleased source is not an
installable GitHub release. See [versioning](docs/versioning.md).

## 0.20.0+64

- **简约任务监控**：在原聊天界面打开 Monitor，支持 Task Controller 暂停、恢复、
  取消；Jobs 独立控制。研究详情与执行记录收进二级页面。
- **文件与结构预览**：浏览工作区材料，查看文本、CSV/TSV、PNG/JPEG，以及基础
  XYZ、MOL/SDF V2000、PDB、笛卡尔坐标 mmCIF。支持旋转、缩放、选原子和测距。
  文件以可展开的紧凑标签加入草稿，发送和重试沿用原有 outbox。
- **服务端要求**：更新 CoRAgent main 到本次 `files/*` 接口合入后的版本。
  需要 UserTask v2、Research Snapshot v3 与新的 Monitor、files 能力；
  仅版本号为 0.19.0 的旧安装不保证包含这些接口。
- **升级提示**：本版使用 `coragent-host/2`、`coragent-link.v1` 和 `cad_` 凭据。
  从 CoRHub 0.19.1+63 或更早版本升级时，同步更新 Host/Relay，并通过
  `coragent phone pair` 重新配对。保留原 Android 包名与生产签名，支持覆盖安装。
- **范围与限制**：预览限 8 MiB / 5,000 原子，展示首个模型/记录（备选位置 A）；
  推断连线不代表键级。暂不渲染 PDF、MOL V3000 或分数坐标 CIF，不包含上传。
  文本和表格预览限 200,000 字符、200 行 / 30 列。
- **验证**：客户端版本、格式、静态分析与 23 个 Flutter 测试文件通过；
  本地确定性真实 Host/Pi 联调及服务端专项测试通过，测试服务已清理。
  APK/AAB 由 GitHub Actions 从标签构建、签名并校验。未进行 Android/iOS 实机验收。
- Compact Monitor uses canonical session-scoped task and Job controls, preserves
  uncertain request identities and does not equate Job success with task completion.
  The new Host material APIs provide versioned file snapshots; no file bytes are
  embedded in chat. Legacy monitor enable/disable methods are removed.

## 0.19.1+63

### CoRHub rebrand / 品牌更新

- Use CoRHub for the client and CoRAgent for the research agent throughout
  English/Chinese UI and documentation, including pairing, assistant attribution,
  generation/disconnection states, diagnostics and recovery instructions.
- Use **CoRHub** as the client product name and move repository links to `iawnix/corhub`.
  Update English/Chinese screens, Android/iOS display names and the client name
  sent to CoRAgent Host.
- Adopt the refined teal/blue crab and golden ring. Versioned SVG masters now
  generate in-app, small-size, monochrome, Android and iOS artwork.
- New releases use `corhub-vMAJOR.MINOR.PATCH+BUILD` and `corhub-` artifact names.
  Version checks still include all legacy `ts-phone-v*` tags. Existing tags and
  published assets remain immutable; a new release must increase the build.
- Preserve Android/iOS application identifiers, signing identity, secure storage,
  saved pairing and Host/Link contracts. Existing installations can upgrade
  without a brand-related re-pairing or data migration.
- 应用与仓库更名为 CoRHub，采用优化后的螃蟹图标；保留现有安装身份和配对数据。
  从 0.19.0+62 升级无需因本次品牌更新重新配对。

### Installation and validation / 安装与验证

- Most Android phones should install the **arm64-v8a APK**. The release also
  includes armeabi-v7a / x86_64 APKs, an AAB, source attestations and SHA256SUMS.
- Continues to use `research-agent-host/2`, `research-agent-link.v1` and `rad_`
  device credentials with server version 0.18.0. Upgrading from the legacy
  protocol still requires re-pairing as described in the previous release.
- Independent client and release-tool checks cover this update. Official
  binaries are built and verified from the release tag by GitHub Actions using
  the existing production signer. Physical-device acceptance and a new Host/Pi
  interoperability run are not claimed for this branding release.
- 大多数 Android 手机请选择 arm64-v8a APK。保留原有签名，可覆盖安装升级；
  本次未进行 Android/iOS 实机验收，不提供签名 iOS 下载。

## 0.19.0+62

### CoRAgent compatibility / 兼容性

- Targets CoRAgent 0.18.0's `research-agent-host/2` and
  `research-agent-link.v1`, with `rad_` device credentials.
- **Re-pair after upgrading from the legacy protocol.** Run
  `research-agent phone pair` on the server and enter the new code in the app.
  Old `tspi-host/2`, `tspi-link.v1` and `tspd_` credentials are not supported.
- 升级旧版后需要重新配对，不能修改旧 token 的前缀来迁移。

### Changes / 更新

- Align model selection, Monitor views and enable/disable responses with
  CoRAgent. Improve reconnection and preserve uncertain message identities.
- Simplify chat and session navigation, project selection and model controls;
  remove the retired Pi v8 client and obsolete phone approval interface.
- Use one application version source, enforce increasing build numbers and
  matching release tags, and remove obsolete Node/package version metadata.
- Refresh bilingual setup/development documentation. Publish signed Android
  APKs/AAB, source attestations and SHA-256 checksums as one release.

### Installation and validation / 安装与验证

- For most Android phones, download the **arm64-v8a APK**. Other assets are
  armeabi-v7a, x86_64, and the AAB intended for store distribution.
- Independent Flutter tests and release-tool tests run in CI. Local deterministic
  Host/Pi interoperability is a separate check; neither replaces physical-device
  acceptance. An installed Android/iOS device test is not claimed for this release.
- iOS source is included; no signed iOS binary is published.

## 0.19.0+61

No binaries were published: the Android SDK setup requested the retired `tools`
package. Superseded by build 62; the original tag is retained unchanged.

## 0.18.3+48

Previous GitHub release using the legacy integration. It is not compatible
with the current CoRAgent protocol identity. Intermediate 0.18.4–0.18.9
versions existed in source/local builds and were not GitHub releases.
