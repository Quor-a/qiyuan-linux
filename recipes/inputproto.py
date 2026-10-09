"""inputproto —— X11 输入扩展协议头文件


许可证：MIT
"""

name = "inputproto"
version = "2.3.2"
release = 1
summary = "X11 输入扩展协议头文件"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums inputproto
source = ["https://www.x.org/archive/individual/proto/inputproto-2.3.2.tar.bz2"]
sha256 = ["893a6af55733262058a27b38eeb1edc733669f01d404e8581b167f03c03ef31d"]

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
    ctx.run("touch {}/usr/share/qy/aliases/inputproto".format(ctx.destdir))
