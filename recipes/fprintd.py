"""fprintd / libfprint —— 指纹识别

许可证：GPL-2.0-or-later / LGPL-2.1-or-later

必须说明的现实：**多数消费级指纹传感器没有 Linux 驱动**。
libfprint 支持的型号有限，且笔记本内置指纹常常是
厂商定制方案，不公开协议。

所以这个包要有配套的"不支持时怎么提示"——
没有驱动时 PAM 会静默跳过指纹，用户以为没配上，
反复重试直到锁定。
"""
from __future__ import annotations

name = "fprintd"
version = "1.94.4"
release = 1
summary = "指纹识别（fprintd/libfprint）"
homepage = "https://fprint.freedesktop.org/"
license = "GPL-2.0-or-later AND LGPL-2.1-or-later"

source = []
sha256 = []

depends = ["dbus", "polkit", "pam", "libfprint"]
makedepends = ["meson", "ninja", "pkgconf", "dbus", "polkit", "pam", "libfprint"]
provides = ["fingerprint"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True

# 支持清单必须公开：不支持的型号要提前说，
# 不能等用户配了半天才发现硬件不支持
UNSUPPORTED_HINT = "多数消费级指纹传感器无 Linux 驱动"
