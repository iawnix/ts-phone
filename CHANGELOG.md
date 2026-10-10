# Changelog

Release versions follow `MAJOR.MINOR.PATCH+BUILD`. Unreleased source is not an
installable GitHub release. See [versioning](docs/versioning.md).

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
