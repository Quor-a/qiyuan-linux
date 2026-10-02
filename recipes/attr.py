"""attr —— 扩展属性工具与库


许可证：LGPL-2.1-or-later AND GPL-2.0-or-later
"""

name = "attr"
version = "2.5.2"
release = 1
summary = "扩展属性工具与库"
homepage = ""
license = "LGPL-2.1-or-later AND GPL-2.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums attr
source = ["https://download.savannah.gnu.org/releases/attr/attr-2.5.2.tar.xz"]
sha256 = ["f2e97b0ab7ce293681ab701915766190d607a1dba7fae8a718138150b700a70b"]
checksum_pending = True

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
