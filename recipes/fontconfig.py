"""fontconfig —— 字体配置与匹配库


许可证：MIT
"""

name = "fontconfig"
version = "2.16.0"
release = 1
summary = "字体配置与匹配库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums fontconfig
source = ["https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.16.0.tar.xz"]
sha256 = ["6a33dc555cc9ba8b10caf7695878ef134eeb36d0af366041f639b1da9b6ed220"]

depends = ["freetype", "expat", "libxml2"]
makedepends = ["gperf", "freetype", "expat", "libxml2"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
