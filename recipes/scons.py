"""scons —— Python 构建工具（gpsd 用）

许可证：MIT
"""
from __future__ import annotations

name = "scons"
version = "4.8.1"
release = 1
summary = "Python 构建工具"
homepage = "https://scons.org/"
license = "MIT"

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
