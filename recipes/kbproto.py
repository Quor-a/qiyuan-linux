"""kbproto —— X11 键盘扩展协议头文件


许可证：MIT
"""

name = "kbproto"
version = "1.0.7"
release = 1
summary = "X11 键盘扩展协议头文件"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums kbproto
source = ["https://www.x.org/archive/individual/proto/kbproto-1.0.7.tar.bz2"]
sha256 = ["f882210b76376e3fa006b11dbd890e56ec0942bc56e65d1249ff4af86f90b857"]

depends = ["xorgproto"]
makedepends = ["xorgproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    # 协议头已统一由 xorgproto 提供，此包仅作依赖别名
    ctx.run("mkdir -p {}/usr/share/qy/aliases".format(ctx.destdir))
    ctx.run("touch {}/usr/share/qy/aliases/kbproto".format(ctx.destdir))
