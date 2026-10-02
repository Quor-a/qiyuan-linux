"""gyp —— 生成构建文件（nss 用）

许可证：BSD-3-Clause
"""
from __future__ import annotations

name = "gyp"
version = "0.16"
release = 1
summary = "跨平台构建文件生成器"
homepage = "https://gyp.gsrc.io/"
license = "BSD-3-Clause"

source = []
sha256 = []

depends = ["python"]
makedepends = ["python"]
provides = []
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
