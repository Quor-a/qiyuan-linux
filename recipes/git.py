"""git —— 分布式版本控制系统


许可证：GPL-2.0-only
"""

name = "git"
version = "2.49.0"
release = 1
summary = "分布式版本控制系统"
homepage = ""
license = "GPL-2.0-only"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums git
source = ["https://example.org/src/git-2.49.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["curl", "openssl", "zlib", "expat", "pcre2", "libiconv"]
makedepends = ["curl", "openssl", "zlib", "expat", "pcre2", "libiconv"]
provides = ["vcs"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("make prefix=/usr NO_PYTHON=1 NO_TCLTK=1")


def package(ctx):
    ctx.run("make prefix=/usr DESTDIR={} NO_PYTHON=1 NO_TCLTK=1 install".format(ctx.destdir))
