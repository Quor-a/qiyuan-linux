"""libpsl —— PSL 公共后缀列表库（WebKit/libsoup 依赖）

许可证：MIT
"""

name = "libpsl"
version = "0.21.5"
release = 1
summary = "公共后缀列表（PSL）解析库"
license = "MIT"

source = ["https://github.com/rockdaboot/libpsl/releases/download/0.21.5/libpsl-0.21.5.tar.gz"]
sha256 = ["1dcc9ceae8b128f3c0b3f654decd0e1e891afc6ff81098f227ef260449dae208"]
checksum_pending = False

depends = ["icu"]
makedepends = ["meson", "ninja", "icu", "python"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.out_of_tree()
    ctx.run("meson " + str(ctx.srcdir) + " --prefix=/usr -Ddocs=false "
            "-Dtests=false -Druntime=libicu -Dbuiltin=true")


def package(ctx):
    ctx.run("ninja")
    ctx.run("DESTDIR={} ninja install".format(ctx.destdir))
