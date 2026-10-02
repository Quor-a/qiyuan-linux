"""hwdata —— 硬件标识数据库（pnp.ids / pci.ids 等，纯数据包）

许可证：GPL-2.0-or-later（数据文件）
"""

name = "hwdata"
version = "0.392"
release = 1
summary = "硬件标识数据库（pnp.ids 等，纯数据）"
homepage = ""
license = "GPL-2.0-or-later"

source = ["https://ghproxy.net/https://github.com/vcrhonek/hwdata/archive/refs/tags/v0.392.tar.gz"]
sha256 = ["1f472d8f2ec824d4efe6a75480767c4ce240fa5d91b6428d9f8775035da3ba1f"]

depends = []
makedepends = []
provides = []

requires_build_machine = False
network = False
compression = "gz"


def build(ctx):
    # 纯数据包，无需编译
    pass


def package(ctx):
    import os
    d = os.path.join(ctx.destdir, "usr/share/hwdata")
    ctx.run("mkdir -p " + d)
    ctx.run("cp pnp.ids pci.ids " + d)
