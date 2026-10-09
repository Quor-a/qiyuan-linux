"""wget —— 命令行下载工具（系统必备）

https://www.gnu.org/software/wget/
许可证：GPL-3.0+
"""

name = "wget"
version = "1.25.0"
release = 1
summary = "命令行网络下载工具"
homepage = "https://www.gnu.org/software/wget/"
license = "GPL-3.0+"

source = ["https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz"]
sha256 = ["766e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784"]

depends = ["openssl", "zlib"]


def fetch(ctx):
    ctx.default_fetch()


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --sysconfdir=/etc --with-ssl=openssl --disable-nls")
    ctx.run("make -j2")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
