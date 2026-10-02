"""neard —— NFC 管理

许可证：GPL-2.0-or-later

NFC 读卡、标签、点对点。多数 NFC 芯片走 USB 或串口，
neard 统一抽象。
"""
from __future__ import annotations

name = "neard"
version = "0.19"
release = 1
summary = "NFC 管理与标签读写"
homepage = "https://01.org/neard"
license = "GPL-2.0-or-later"

source = []
sha256 = []

depends = ["glib", "dbus", "libnl"]
makedepends = ["pkgconf", "glib", "dbus", "libnl"]
provides = ["nfc"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
