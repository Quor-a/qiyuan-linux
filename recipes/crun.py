"""crun —— 轻量 OCI 容器运行时


许可证：GPL-2.0-or-later
"""

name = "crun"
version = "1.21"
release = 1
summary = "轻量 OCI 容器运行时"
homepage = ""
license = "GPL-2.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums crun
source = ["https://example.org/src/crun-1.21.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["libseccomp", "yajl"]
makedepends = ["libseccomp", "yajl"]
provides = ["containers"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-systemd")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
