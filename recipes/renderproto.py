"""renderproto —— X 渲染协议头文件


许可证：MIT
"""

name = "renderproto"
version = "0.11.1"
release = 1
summary = "X 渲染协议头文件"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums renderproto
source = ["https://www.x.org/archive/individual/proto/renderproto-0.11.1.tar.bz2"]
sha256 = ["06735a5b92b20759204e4751ecd6064a2ad8a6246bb65b3078b862a00def2537"]

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
    ctx.run("touch {}/usr/share/qy/aliases/renderproto".format(ctx.destdir))
