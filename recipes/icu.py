"""icu —— Unicode 与国际化组件库


许可证：ICU
"""

name = "icu"
version = "77.1"
release = 1
summary = "Unicode 与国际化组件库"
homepage = ""
license = "ICU"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums icu
source = ["https://github.com/unicode-org/icu/releases/download/release-77-1/icu4c-77_1-src.tgz"]
sha256 = ["588e431f77327c39031ffbb8843c0e3bc122c211374485fa87dc5f3faff24061"]

depends = []
makedepends = []
provides = ["libicuuc.so.76"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("cd source && ./configure --prefix=/usr && make")


def package(ctx):
    ctx.run("cd source && make DESTDIR={} install".format(str(ctx.destdir)))
