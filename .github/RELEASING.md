# MeloX-Overtone Release Guide / 弦外发版规则

[English](#english) | [简体中文](#简体中文)

## English

### iOS signing

Xcode Run and `bash build_ios_unsigned.sh` use the personal app ID `com.aritxonly.MeloX`. The app and widget share `group.com.aritxonly.MeloX`. When signing the unsigned IPA yourself, enable that group in both profiles.

For TestFlight, select the MeloX scheme in Xcode and choose Product → Archive. Release uses Deadliner's team (`6Z4232N2L9`) and pins the three App Store profile UUIDs. Install those profiles and their matching Apple Distribution identities on the signing Mac. In Organizer choose Distribute App → App Store Connect. The identifiers are:

- App: `top.aritxonly.overtone`
- Lyrics widget: `top.aritxonly.overtone.lyricswidget`
- Watch app: `top.aritxonly.overtone.watchkitapp`
- App Group for the app and widget: `group.top.aritxonly.overtone`

```sh
python3 Tools/archive_testflight.py App.mobileprovision Lyrics.mobileprovision Watch.mobileprovision
```

As an alternative to Product → Archive, the command above matches the files to their targets and archives with their team and profile UUIDs. Open the resulting archive in Organizer to distribute it through App Store Connect.

### Release Notes

`RELEASE_NOTES.md` always contains both platform sections:

- `iOS + Apple Watch`: a non-empty section builds and publishes the IPA.
- `macOS`: a non-empty section builds and publishes separate Apple silicon and Intel DMGs.

Every platform section must include both `### 简体中文` and `### English`. Translations must contain the same number of entries in the same order. CI rejects missing language sections or mismatched entry counts.

Branch, pull-request, and `main` builds select artifacts from the non-empty platform sections. If both platform sections contain entries, CI builds both sets of artifacts.

The build generates a schema-version-3 `ReleaseNotes.json` containing `localizedEntries` for `zh-Hans` and `en`. The apps select one array from their active language. GitHub Release and Telegram consume the bilingual `ReleaseNotes.md` artifact.

### Tags and Versions

- iOS + Apple Watch uses `v<upstream version>.<fork revision>`, for example `v1.4.1.1`. Set the three-part marketing version and integer build number on the app, Watch app and widget.
- macOS: `v<major>.<minor>.<patch>_mac`, for example `v0.1.0_mac`.

To release both platforms together, point both tags at the same commit and push them together. Each tag creates an independent GitHub Release and, when the repository variable `ENABLE_TELEGRAM` is `true`, a bilingual Telegram message.

The macOS Release does not replace the repository's Latest release. Latest remains assigned to mobile for compatibility with older iOS clients that still request `/releases/latest`.

GitHub Actions produces `MeloX-Overtone-macOS-Apple-Silicon.dmg` and `MeloX-Overtone-macOS-Intel.dmg` as unsigned builds. The GitHub Release body and website Release area retain Gatekeeper instructions. The platform download menu labels these builds as unsigned without embedding the `xattr` command in the menu itself.

macOS DMGs distributed through the cloud drive are built locally with `Tools/MacRelease/build_macos_release.py`. Apple silicon (`arm64`) and Intel (`x86_64`) are built, signed, and notarized separately. The website may label these downloads as notarized only after the tool completes Developer ID signing, Apple notarization, ticket stapling, and Gatekeeper verification for both DMGs.

## 简体中文

### iOS 签名

Xcode 本地运行和 `bash build_ios_unsigned.sh` 均使用个人主包名 `com.aritxonly.MeloX`。主 App 和歌词组件共用 `group.com.aritxonly.MeloX`。给 unsigned IPA 自签时，请在这两个 target 的签名配置中启用该组。

在 Xcode 选择 MeloX scheme，点击 Product → Archive 即可使用 Release 配置。该配置绑定 Deadliner 团队（`6Z4232N2L9`）的三份 App Store 描述文件 UUID。主 App 为 `top.aritxonly.overtone`，歌词组件为 `top.aritxonly.overtone.lyricswidget`，Watch 为 `top.aritxonly.overtone.watchkitapp`。主 App 和歌词组件均需绑定 `group.top.aritxonly.overtone`。

在签名所用的 Mac 上将描述文件导入 Xcode，确认钥匙串中有各描述文件对应的 Apple Distribution 证书和私钥。也可以用命令行归档：

```sh
python3 Tools/archive_testflight.py App.mobileprovision Lyrics.mobileprovision Watch.mobileprovision
```

脚本按包名匹配三个 target，并使用描述文件里的团队和 UUID 归档。归档完成后，可在 Xcode Organizer 中选择 App Store Connect 分发。

### 更新日志

`RELEASE_NOTES.md` 固定包含两个平台区块：

- `iOS + Apple Watch`：非空时构建并发布 IPA。
- `macOS`：非空时分别构建并发布 Apple Silicon 与 Intel DMG。

每个平台区块必须同时包含 `### 简体中文` 与 `### English`，中英文条目数量及顺序必须一一对应。缺少任一语言或条目数量不一致时，CI 会直接失败。

普通分支、Pull Request 与 `main` 构建会根据非空区块选择产物。两个平台区块都有内容时，会分别构建两份产物。

构建过程会生成 schema version 3 的 `ReleaseNotes.json`，其中 `localizedEntries` 分别保存 `zh-Hans` 与 `en` 条目。App 根据当前语言选择对应数组；GitHub Release 与 Telegram 则使用双语 `ReleaseNotes.md` 产物。

### 标签与版本

- iOS + Apple Watch 使用 `v<上游版本>.<衍生修订号>`，例如 `v1.4.1.1`。主 App、Watch 和歌词组件使用相同的三段营销版本和整数构建号。
- macOS：`v<major>.<minor>.<patch>_mac`，例如 `v0.1.0_mac`。

两端同时发版时，将两个标签指向同一个 Commit 并一起推送。每个标签会独立创建 GitHub Release，仓库变量 `ENABLE_TELEGRAM` 为 `true` 时还会发送双语 Telegram 发版消息。

macOS Release 不会替换仓库的 Latest；Latest 始终保留给移动端，以兼容仍请求 `/releases/latest` 的旧版 iOS 客户端。

GitHub Actions 生成 `MeloX-Overtone-macOS-Apple-Silicon.dmg` 和 `MeloX-Overtone-macOS-Intel.dmg`，两者仅作为未签名构建发布。GitHub Release 正文和官网 Release 区域保留 Gatekeeper 处理说明；“选择平台下载”下拉菜单只标注“未签名”，不附带 `xattr` 文案。

网盘中的 macOS DMG 使用 `Tools/MacRelease/build_macos_release.py` 在本地生成。Apple Silicon（`arm64`）与 Intel（`x86_64`）分别构建、签名和公证。只有该工具完成两份 DMG 的 Developer ID 签名、Apple 公证、票据装订和 Gatekeeper 验证后，官网网盘入口才标注“已公证”。
