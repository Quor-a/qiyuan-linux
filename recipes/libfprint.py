"""libfprint —— 指纹传感器驱动库

许可证：LGPL-2.1-or-later
"""
from __future__ import annotations

name = "libfprint"
version = "1.94.9"
release = 1
summary = "指纹传感器驱动库"
homepage = "https://fprint.freedesktop.org/"
license = "LGPL-2.1-or-later"

source = []
sha256 = []

depends = ["glib", "libusb", "nss"]
makedepends = ["meson", "ninja", "pkgconf", "gtk3", "glib", "libusb", "nss"]
provides = []
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
