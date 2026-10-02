"""libxcrypt —— libcrypt 密码散列库（perl/shadow 等运行期依赖）

许可证：LGPL-2.1-or-later
"""
from __future__ import annotations

name = "libxcrypt"
version = "4.4.38"
release = 1
summary = "libcrypt 密码散列库"
homepage = "https://github.com/besser82/libxcrypt"
license = "LGPL-2.1-or-later"

source = ["https://ghproxy.net/https://github.com/besser82/libxcrypt/releases/download/v4.4.38/libxcrypt-4.4.38.tar.xz"]
sha256 = ["80304b9c306ea799327f01d9a7549bdb28317789182631f1b54f4511b4206dd6"]

depends = []
makedepends = []
provides = ["libcrypt.so.1"]

requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --enable-hashes=strong,glibc "
            "--enable-obsolete-api=glibc --disable-static "
            "--disable-failure-tokens")
    ctx.run("make")


def package(ctx):
    ctx.run("make install DESTDIR={}".format(ctx.destdir))
