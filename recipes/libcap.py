"""libcap —— 能力位（capability）管理

许可证：BSD-3-Clause OR GPL-2.0-or-later

ping、网络工具等需要特定能力位而不是完整 root。
没有它只能给二进制 setuid，那等于给了完整 root。
"""
from __future__ import annotations

name = "libcap"
version = "2.75"
release = 1
summary = "能力位（capability）管理"
homepage = "https://sites.google.com/site/fullycapable/"
license = "BSD-3-Clause OR GPL-2.0-or-later"

source = []
sha256 = []

depends = []
makedepends = []
provides = ["libcap.so.2"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
