"""runc —— OCI 容器运行时


许可证：Apache-2.0
"""

name = "runc"
version = "1.2.6"
release = 1
summary = "OCI 容器运行时"
homepage = ""
license = "Apache-2.0"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums runc
source = ["https://example.org/src/runc-1.2.6.tar.xz"]
sha256 = []
checksum_pending = True

depends = []
makedepends = ["libseccomp"]
provides = ["containers"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("make runc")


def package(ctx):
    ctx.run("install -Dm755 runc {}/usr/bin/runc".format(ctx.destdir))
