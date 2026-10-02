"""nspr —— Netscape 可移植运行时（nss 依赖）

许可证：MPL-2.0
"""
from __future__ import annotations

name = "nspr"
version = "4.36"
release = 1
summary = "Netscape 可移植运行时"
homepage = "https://firefox-source-docs.mozilla.org/nspr/"
license = "MPL-2.0"

source = []
sha256 = []

depends = ["glibc"]
makedepends = ["glibc"]
provides = []
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
