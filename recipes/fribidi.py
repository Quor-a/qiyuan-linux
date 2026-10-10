"""fribidi —— 双向文本算法实现


许可证：LGPL-2.1-or-later
"""

name = "fribidi"
version = "1.0.16"
release = 1
summary = "双向文本算法实现"
homepage = ""
license = "LGPL-2.1-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums fribidi
source = ["https://github.com/fribidi/fribidi/archive/refs/tags/v1.0.16.tar.gz"]
sha256 = ["5a1d187a33daa58fcee2ad77f0eb9d136dd6fa4096239199ba31e850d397e8a8"]

depends = []
makedepends = ["meson", "ninja"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("rm -rf build && mkdir -p build")
    cf = ctx.meson_cross_file()
    x = f"--cross-file={cf}" if cf else ""
    ctx.run(f"cd build && meson setup .. --prefix=/usr {x} -Dtests=false -Ddocs=false")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
