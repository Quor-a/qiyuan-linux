"""popt —— 命令行参数解析库

http://ftp.rpm.org/popt/
许可证：MIT
"""

name = "popt"
version = "1.19"
release = 1
summary = "getopt(3) 的增强版参数解析库"
homepage = "http://ftp.rpm.org/popt/"
license = "MIT"

source = ["http://ftp.rpm.org/popt/releases/popt-1.x/popt-1.19.tar.gz"]
sha256 = ["c25a4838fc8e4c1c8aacb8bd620edb3084a3d63bf8987fdad3ca2758c63240f9"]

depends = []


def fetch(ctx):
    ctx.default_fetch()


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make -j2")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
