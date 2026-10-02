"""qt5-base —— Qt5 基础库（fcitx5 配置界面等依赖）

许可证：LGPL-3.0-or-later OR GPL-2.0-or-later
"""
from __future__ import annotations

name = "qt5-base"
version = "5.15.16"
release = 1
summary = "Qt5 基础库"
homepage = "https://www.qt.io/"
license = "LGPL-3.0-or-later OR GPL-2.0-or-later"

source = []
sha256 = []

depends = ["zlib", "libpng", "dbus", "freetype", "fontconfig"]
makedepends = ["pkgconf", "python", "zlib", "libpng", "dbus", "freetype", "fontconfig"]
provides = ["libQt5Core.so.5"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
