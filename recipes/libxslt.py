"""libxslt —— XSLT 转换库（WebKit 依赖）

许可证：MIT
"""

name = "libxslt"
version = "1.1.43"
release = 1
summary = "XSLT 转换库"
license = "MIT"

source = ["https://download.gnome.org/sources/libxslt/1.1/libxslt-1.1.43.tar.xz"]
sha256 = ["5a3d6b383ca5afc235b171118e90f5ff6aa27e9fea3303065231a6d403f0183a"]
checksum_pending = False

depends = ["libxml2"]
makedepends = ["libxml2"]
provides = []

requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    ctx.run("./configure" + " " .join(ctx.configure_args()) + " --prefix=/usr --sysconfdir=/etc "
            "--without-python --without-debug --without-mem-debug "
            "--disable-static")


def package(ctx):
    ctx.run("make -j{}".format(ctx.jobs))
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
