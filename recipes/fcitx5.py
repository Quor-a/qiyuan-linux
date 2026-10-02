"""fcitx5 —— 输入法框架

许可证：LGPL-2.1-or-later

中文输入必须有输入法框架。没有它，用户只能输入英文——
这不是"少个功能"，是中文用户完全没法用。

输入法是系统里少数几个需要常驻、且要拿到所有按键的程序，
所以它的权限模型和安全要单独考虑。
"""
from __future__ import annotations

name = "fcitx5"
version = "5.1.12"
release = 1
summary = "输入法框架"
homepage = "https://fcitx-im.org/"
license = "LGPL-2.1-or-later"

source = []
sha256 = []

depends = ["glib", "dbus", "qt5-base"]
makedepends = ["cmake", "ninja", "pkgconf", "glib", "dbus", "qt5-base"]
provides = ["input-method", "virtual-keyboard"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
