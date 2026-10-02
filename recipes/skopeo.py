"""skopeo —— 容器镜像搬运工具


许可证：Apache-2.0
"""

name = "skopeo"
version = "1.17.0"
release = 1
summary = "容器镜像搬运工具"
homepage = ""
license = "Apache-2.0"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums skopeo
source = ["https://example.org/src/skopeo-1.17.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["gpgme"]
makedepends = ["gpgme"]
provides = ["containers"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("make bin/skopeo")


def package(ctx):
    ctx.run("install -Dm755 bin/skopeo {}/usr/bin/skopeo".format(ctx.destdir))
