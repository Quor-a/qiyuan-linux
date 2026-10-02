"""nss —— 网络安全服务（libfprint 等依赖）

许可证：MPL-2.0
"""
from __future__ import annotations

name = "nss"
version = "3.109"
release = 1
summary = "网络安全服务库"
homepage = "https://firefox-source-docs.mozilla.org/security/nss/"
license = "MPL-2.0"

source = []
sha256 = []

depends = ["nspr", "sqlite"]
makedepends = ["ninja", "gyp", "nspr", "sqlite"]
provides = []
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
