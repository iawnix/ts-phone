# Changelog

Release versions follow `MAJOR.MINOR.PATCH+BUILD`. Unreleased source is not an
installable GitHub release. See [versioning](docs/versioning.md).

## Unreleased

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
  本次源码更新尚未发布安装包，latest 下载仍可能采用旧品牌。

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
