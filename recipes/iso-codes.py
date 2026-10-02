"""iso-codes —— ISO 标准代码数据集（语言/国家/货币名）


许可证：LGPL-2.1-or-later
"""

name = "iso-codes"
version = "4.17.0"
release = 1
summary = "ISO 标准代码数据集（语言/国家/货币名）"
homepage = ""
license = "LGPL-2.1-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums iso-codes
source = ["https://salsa.debian.org/iso-codes-team/iso-codes/-/archive/v4.17.0/iso-codes-v4.17.0.tar.gz"]
sha256 = ["dd5ca13db77ec6dd1cc25f5c0184290a870ec1fed245d8e39a04ff34f59076c3"]

depends = []
makedepends = ["python"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
