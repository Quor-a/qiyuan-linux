"""libXext —— X11 扩展库


许可证：MIT
"""

name = "libXext"
version = "1.3.6"
release = 1
summary = "X11 扩展库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXext
source = ["https://www.x.org/archive/individual/lib/libXext-1.3.6.tar.xz"]
sha256 = ["edb59fa23994e405fdc5b400afdf5820ae6160b94f35e3dc3da4457a16e89753"]

depends = ["libX11", "xextproto"]
makedepends = ["libX11", "xextproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
    # xorgproto 已收编协议头与文档，libXext 里的旧副本去掉避免冲突
    ctx.run("rm -rf {}/usr/share/doc/xextproto".format(ctx.destdir))
    ctx.run("rm -f {}/usr/include/X11/extensions/EVI.h {}/usr/include/X11/extensions/EVIproto.h {}/usr/include/X11/extensions/xtestext1.h".format(ctx.destdir, ctx.destdir, ctx.destdir))
