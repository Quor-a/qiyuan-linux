"""libiconv —— 字符编码转换库（git 在部分平台上需要）


许可证：LGPL-2.1-or-later
"""

name = "libiconv"
version = "1.18"
release = 1
summary = "字符编码转换库（git 在部分平台上需要）"
homepage = ""
license = "LGPL-2.1-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libiconv
source = ["https://example.org/src/libiconv-1.18.tar.xz"]
sha256 = []
checksum_pending = True

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
