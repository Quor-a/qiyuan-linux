"""wireguard-tools —— VPN 配置工具

许可证：GPL-2.0-or-later

内核自带 WireGuard 模块，但配置需要 wg/quick。
没有它就配不了 VPN——而"能装模块但配不了"
最难排查，用户会以为是内核不支持。
"""
from __future__ import annotations

name = "wireguard-tools"
version = "1.0.20250521"
release = 1
summary = "WireGuard VPN 配置工具"
homepage = "https://www.wireguard.com/"
license = "GPL-2.0-or-later"

source = []
sha256 = []

depends = []
makedepends = []
provides = ["wg"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
