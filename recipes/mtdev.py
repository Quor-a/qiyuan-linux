"""mtdev —— 多点触控协议转换库


许可证：MIT
"""

name = "mtdev"
version = "1.1.6"
release = 1
summary = "多点触控协议转换库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums mtdev
source = ["http://bitmath.org/code/mtdev/mtdev-1.1.7.tar.gz"]
sha256 = ["a55bd02a9af4dd266c0042ec608744fff3a017577614c057da09f1f4566ea32c"]

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
