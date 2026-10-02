"""wvkbd —— 屏幕虚拟键盘

许可证：GPL-3.0-or-later

触屏设备没有物理键盘时必须有它。
平板上没有虚拟键盘等于没法输入任何东西——
而用户往往不知道要自己装，只会觉得"这系统不支持触控输入"。
"""
from __future__ import annotations

name = "wvkbd"
version = "0.15"
release = 1
summary = "触屏虚拟键盘"
homepage = "https://github.com/jjsullivan5196/wvkbd"
license = "GPL-3.0-or-later"

source = []
sha256 = []

depends = ["wayland", "cairo", "pango"]
makedepends = ["meson", "ninja", "pkgconf", "wayland", "cairo", "pango"]
provides = ["virtual-keyboard", "on-screen-keyboard"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
