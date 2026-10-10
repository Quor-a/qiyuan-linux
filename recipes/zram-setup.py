"""zram-setup —— zram 内存压缩配置与开机启用（元包）

许可证：MIT
"""

name = "zram-setup"
version = "1.0.0"
release = 1
summary = "zram 内存压缩配置与开机启用（元包）"
license = "MIT"

source = ["https://example.org/src/zram-setup-1.0.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["util-linux", "procps-ng"]
makedepends = ["util-linux", "procps-ng"]
provides = ["zram"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("true")


def package(ctx):
    ctx.run("mkdir -p {}/etc/qyinit.d {}/usr/share/lanxiu".format(ctx.destdir))
