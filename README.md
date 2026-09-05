# rclone-android

在 Android 上使用 [rclone](https://rclone.org/) 的挂载与文件管理器。有 Root 时可以把网盘挂成手机目录，供其他 App 直接打开；无 Root 时用内置文件管理器浏览、下载、上传。

本程序以 **GNU GPL v3.0** 发布，见 [LICENSE](LICENSE)。第三方组件保留各自许可证，见 [THIRD_PARTY](THIRD_PARTY.md)。

## 安装

到 [Releases](https://github.com/sw1313/rclone-android/releases) 下载 APK。当前通用包含 arm64 / armeabi-v7a / x86_64，体积较大。

需要：

- Android 8.0（API 26）及以上
- 真实挂载：已 Root，并授权本应用
- Magisk 用户请把 **挂载命名空间** 设为 **全局**，然后重启，否则其他 App 看不到挂载目录

首次打开请授予：通知、所有文件访问、定位（用来读 WiFi 名称）。小米等设备建议把本应用省电策略设为「无限制」，并允许自启动。

## 功能

- 添加 WebDAV / SFTP / FTP / S3 / alias；Google Drive / OneDrive / Dropbox 可通过导入 `rclone.conf` 配置
- 导入、导出 `rclone.conf`
- 常用 rclone 挂载参数（VFS 缓存、transfers、带宽限制等）
- 首页开关：按实际 `/proc/mounts` 显示是否已挂载
- 按 **当前** WiFi / VPN（如 Tailscale）状态自动挂载或卸载，开机后也会核对，不依赖「刚刚连上」那一下
- 开机自启前台服务（是否挂载仍看规则）
- 网断了也可以进应用，用懒卸载关掉挂载，避免卡死
- 无 Root 时使用内置文件管理器

## 从源码构建

1. 安装 [Flutter](https://flutter.dev)（3.12+）和 Android SDK。
2. 下载官方 Android 二进制到 `jniLibs`（Android 10+ 不能执行应用数据目录里的文件）：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\fetch_binaries.ps1
```

3. 连接设备后：

```powershell
flutter pub get
flutter run
```

rclone 与 fusermount 体积较大，默认不进 Git。构建前必须先跑下载脚本。

## Root 与 Magisk

真实挂载需要同时满足：

1. 设备已 Root，并授权本应用
2. Magisk 挂载命名空间为全局
3. 内核提供 `/dev/fuse`

部分机型上 `fusermount` 可能不兼容。强制关闭本应用**不会**自动卸盘：rclone 由 Root 在后台拉起，和 App 进程不是同一个。网不通时打开应用关掉对应开关即可。

## 许可证

Copyright (C) 2026 sw1313

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

完整文本见 [LICENSE](LICENSE)。

本仓库**不是** rclone 官方项目。rclone 本身是 MIT 许可证，由 Nick Craig-Wood 与贡献者开发：<https://github.com/rclone/rclone>。

随 APK 分发的 `librclone.so` 来自 rclone 的 Android 构建，仍适用 rclone 的 MIT 许可证。`libfusermount.so` 来自社区 Magisk 模块中的静态 fusermount，其上游 FUSE/libfuse 多为 GPL-2.0。详见 [THIRD_PARTY.md](THIRD_PARTY.md)。

## 免责声明

使用 Root、FUSE 挂载和第三方网盘有数据损坏或丢失的风险。作者不对使用本软件造成的任何损失负责。
