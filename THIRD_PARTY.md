# 第三方组件说明

本程序（rclone-android）以 GNU GPL v3.0 发布。下列组件不是本仓库的原创代码，继续适用其各自许可证。分发 APK 或重新打包时，请一并保留这些声明。

## rclone

- 项目：<https://github.com/rclone/rclone>
- 网站：<https://rclone.org/>
- 版权：Copyright (C) 2012 Nick Craig-Wood <http://www.craig-wood.com/nick/>
- 许可证：[MIT](https://github.com/rclone/rclone/blob/master/COPYING)
- 本应用用法：将官方 **Android 21** 构建（当前脚本使用 v1.75.0）作为 `librclone.so` 打入 APK，运行 `rclone rcd` 与 `rclone mount`
- 下载来源：<https://beta.rclone.org/v1.75.0/testbuilds/>

MIT 允许再分发二进制。本仓库未修改 rclone 源码；完整源码请到 rclone 仓库获取。

## fusermount（libfusermount.so）

- 二进制取自：[rclone-mount-magisk](https://github.com/AvinashReddy3108/rclone-mount-magisk) 的 `common/binary/`（该模块本身也声明基于 piyushgarg 的 rclone-mount，并致谢 Termux 等构建者）
- 功能上游：FUSE / [libfuse](https://github.com/libfuse/libfuse)（通常为 **GPL-2.0**）
- 本应用用法：复制为 `fusermount` / `fusermount3` 供 `rclone mount` 调用

对应源码请参见 libfuse 与上述 Magisk 模块仓库。若你再分发本 APK，你也在再分发该 GPL 二进制，需遵守其许可证（提供源码获取方式）。

## libsu

- 项目：<https://github.com/topjohnwu/libsu>
- 版权：John Wu (topjohnwu) 及贡献者
- 许可证：[Apache License 2.0](https://github.com/topjohnwu/libsu/blob/master/LICENSE)
- 本应用用法：以 `FLAG_MOUNT_MASTER` 执行 Root 命令，完成 FUSE 挂载与 bind

Apache-2.0 与 GPL-3.0 可以组合使用。libsu 本身仍按 Apache-2.0 授权。

## Flutter 与 Dart 包

- Flutter 引擎与框架：[BSD 3-Clause](https://github.com/flutter/flutter/blob/master/LICENSE)，Google LLC
- 主要 Dart 依赖（见 `pubspec.yaml`）：
  - `flutter_riverpod` — MIT
  - `http` — BSD 3-Clause
  - `file_picker` — MIT
  - `permission_handler` — MIT
  - `intl` — BSD 3-Clause
  - `path` — BSD 3-Clause
  - `cupertino_icons` — MIT

完整列表以 `pubspec.lock` 为准。

## AndroidX

`androidx.core:core-ktx` 等 AndroidX 库为 Apache License 2.0。

## 商标

rclone、Flutter、Magisk、Tailscale 等名称为其各自所有者的商标。本项目与这些组织无官方从属关系。
