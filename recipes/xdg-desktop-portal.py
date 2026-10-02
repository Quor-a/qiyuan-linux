"""xdg-desktop-portal —— 截图、拖拽、文件选择的统一入口

许可证：LGPL-2.1-or-later

Wayland 下应用不能自己截屏、不能自己打开文件选择器，
必须走 portal 由用户授权。没有它：
- 截图快捷键没反应（没人接收请求）
- 应用里的"打开文件"对话框打不开
- 拖放文件内容跨应用失败

这三项都是"点了没反应"，用户完全无法归因。
"""
from __future__ import annotations

name = "xdg-desktop-portal"
version = "1.20.0"
release = 1
summary = "截图/文件选择/拖放的授权入口"
homepage = "https://github.com/flatpak/xdg-desktop-portal"
license = "LGPL-2.1-or-later"

source = []
sha256 = []

depends = ["glib", "dbus", "polkit"]
makedepends = ["meson", "ninja", "pkgconf", "glib", "dbus", "polkit"]
provides = ["desktop-portal"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
