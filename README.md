# rclone-android

在 Android 上使用 [rclone](https://rclone.org/) 的挂载与文件管理器。有 Root 时可以把网盘挂成手机目录，供其他 App 直接打开；无 Root 时用内置文件管理器浏览、下载、上传。

本程序以 **GNU GPL v3.0** 发布，见 [LICENSE](LICENSE)。第三方组件保留各自许可证，见 [THIRD_PARTY](THIRD_PARTY.md)。

## 安装

到 [Releases](https://github.com/sw1313/rclone-android/releases/latest) 下载 APK。当前版本 **v1.0.7**，通用包含 arm64 / armeabi-v7a / x86_64，体积较大。覆盖安装即可，不必卸载。

需要：

- Android 8.0（API 26）及以上
- 真实挂载：已 Root，并授权本应用
- Magisk 用户请把 **挂载命名空间** 设为 **全局**，然后重启，否则其他 App 看不到挂载目录

首次打开请授予「所有文件访问」。通知用来显示挂载状态，以及下载/上传进度（类似浏览器下载）。不必开省电「无限制」、自启动或定位。

## 功能

- 添加 WebDAV / SFTP / FTP / S3 / alias；Google Drive / OneDrive / Dropbox 可通过导入 `rclone.conf` 配置
- 添加远程时可先用当前表单参数测试连接，不必先保存
- 导入、导出 `rclone.conf`
- 常用 rclone 挂载参数（VFS 缓存、transfers、带宽限制等）
- 首页开关：按实际 `/proc/mounts` 显示是否已挂载
- 自动规则：
  - 仅 WiFi / 仅 VPN：按**当前**是否连着判断，开机后也会核对
  - **前提状态 + 触发器**：例如家里 WiFi 已经断开后，再开/关 VPN（如 Tailscale 的 `tun0`）才挂上或卸掉，不靠「两边碰巧同时满足」
- 开机自启 / 看门狗：有 Root 时写入 Magisk 模块「rclone 挂载看门狗」。挂载和卸载由模块进程完成，不依赖 App 保活。可在 Magisk 模块列表里删除；卸载本应用后模块也会自行消失
- 系统返回不会退出应用：文件页先回上级，其他页先回挂载页，首页退到后台
- 网断了也可以进应用，用懒卸载关掉挂载，避免卡死
- 无 Root 时使用内置文件管理器；只有传输文件时才用通知栏进度条保活，平时不常驻后台

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

部分机型上 `fusermount` 可能不兼容。小米 / HyperOS 会冻结或杀掉 App 进程（包括用 `su` 从应用里拉起的 rclone）。因此真实挂载改由 Magisk 模块看门狗负责：rclone 跑在模块自己的进程里，强制关闭本应用不会卸盘。网不通时打开应用关掉对应开关即可。

看门狗按**网络事件**工作，不是定时轮询：

- App 在时：用系统 `NetworkCallback` 收 WiFi / VPN 变化，再通知模块执行
- App 被冻或被杀时：模块用 `inotifyd` 监听 `/data/misc/net`（路由表变化），例如开关 WiFi、Tailscale 拉起 `tun0`
- 单条件规则按当前状态执行，所以家里 WiFi 还连着但挂载进程没了，会补挂
- 组合规则必须「前提已成立 + 触发器边沿」，开机或定时核对本身不会误触发
- 本应用不再常驻前台服务。通知栏常驻显示已挂载或尚未挂载；文件传输才短暂拉起 `dataSync` 进度通知，传完即停

模块路径为 `/data/adb/modules/rclone-android`。不想后台挂载时，可在 Magisk 里删除该模块，或在应用设置里关掉「开机自启」。

VPN 须是系统 `VpnService` 建出的接口（例如 Tailscale 的 `tun0`）。用 `ip link add` 假造的网卡不会进 Android 路由表，看门狗也收不到。

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
