# Changelog

Release versions follow `MAJOR.MINOR.PATCH+BUILD`. Unreleased source is not an
installable GitHub release. See [versioning](docs/versioning.md).

## 0.19.0+61

### ResearchAgent compatibility / 兼容性

- Targets ResearchAgent 0.18.0's `research-agent-host/2` and
  `research-agent-link.v1`, with `rad_` device credentials.
- **Re-pair after upgrading from the old TSPi protocol.** Run
  `research-agent phone pair` on the server and enter the new code in the app.
  Old `tspi-host/2`, `tspi-link.v1` and `tspd_` credentials are not supported.
- 升级旧版后需要重新配对，不能修改旧 token 的前缀来迁移。

### Changes / 更新

- Align model selection, Monitor views and enable/disable responses with
  ResearchAgent. Improve reconnection and preserve uncertain message identities.
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

## 0.18.3+48

Previous GitHub release using the legacy TSPi integration. It is not compatible
with the current ResearchAgent protocol identity. Intermediate 0.18.4–0.18.9
versions existed in source/local builds and were not GitHub releases.
