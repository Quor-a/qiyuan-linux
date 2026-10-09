"""randrproto —— X RandR 协议头文件


许可证：MIT
"""

name = "randrproto"
version = "1.5.0"
release = 1
summary = "X RandR 协议头文件"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums randrproto
source = ["https://www.x.org/archive/individual/proto/randrproto-1.5.0.tar.bz2"]
sha256 = ["4c675533e79cd730997d232c8894b6692174dce58d3e207021b8f860be498468"]

depends = ["xorgproto"]
makedepends = ["xorgproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    # 协议头已统一由 xorgproto 提供，此包仅作依赖别名
    ctx.run("mkdir -p {}/usr/share/qy/aliases".format(ctx.destdir))
    ctx.run("touch {}/usr/share/qy/aliases/randrproto".format(ctx.destdir))
