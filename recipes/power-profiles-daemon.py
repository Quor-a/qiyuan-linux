"""power-profiles-daemon —— 电源模式（性能/均衡/省电）

许可证：GPL-3.0-or-later

没有它，笔记本无法在插电和电池之间切换性能策略，
表现为"续航很短"或"插电也不快"，而用户找不到开关在哪。
"""
from __future__ import annotations

name = "power-profiles-daemon"
version = "0.23"
release = 1
summary = "电源模式管理（性能/均衡/省电）"
homepage = "https://gitlab.freedesktop.org/upower/power-profiles-daemon"
license = "GPL-3.0-or-later"

source = []
sha256 = []

depends = ["dbus", "glib", "upower"]
makedepends = ["meson", "ninja", "pkgconf", "dbus", "glib", "upower"]
provides = ["power-profile"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
