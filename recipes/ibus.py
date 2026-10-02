"""ibus —— 输入法框架（fcitx5 的替代）

许可证：LGPL-2.1-or-later

与 fcitx5 二选一。默认装 fcitx5（中文社区支持更好），
ibus 提供给习惯 GNOME 生态的用户。
"""
from __future__ import annotations

name = "ibus"
version = "1.5.32"
release = 1
summary = "输入法框架（Intelligent Input Bus）"
homepage = "https://github.com/ibus/ibus"
license = "LGPL-2.1-or-later"

source = []
sha256 = []

depends = ["glib", "dbus", "gtk3"]
makedepends = ["meson", "ninja", "pkgconf", "glib", "dbus", "gtk3"]
provides = ["input-method"]
conflicts = ["fcitx5"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
