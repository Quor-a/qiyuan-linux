"""unzip / zip —— 最通用的压缩格式

许可证：Info-ZIP

.zip 是跨平台交换文件的默认格式。
没有它，用户收到的附件、下载的源码包都打不开。
"""
from __future__ import annotations

name = "unzip"
version = "6.0"
release = 1
summary = "zip 格式的解压与打包"
homepage = "https://infozip.sourceforge.net/"
license = "Info-ZIP"

source = ["https://deb.debian.org/debian/pool/main/u/unzip/unzip_6.0.orig.tar.gz"]
sha256 = ["036d96991646d0449ed0aa952e4fbe21b476ce994abc276e49d30e686708bd37"]

depends = []
makedepends = []
provides = ["zip", "unzip"]
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("make -f unix/Makefile generic")


def package(ctx):
    import os, shutil, glob as _glob
    srcdir = "src" if os.path.isdir("src") else "."
    d = os.path.join(str(ctx.destdir), "usr/bin")
    os.makedirs(d, exist_ok=True)
    os.makedirs(os.path.join(str(ctx.destdir), "usr/share/man/man1"), exist_ok=True)
    for b in ["unzip", "funzip", "unzipsfx", "zipinfo", "zipgrep"]:
        f = os.path.join(srcdir, b)
        if os.path.exists(f):
            shutil.copy2(f, os.path.join(d, b))
            os.chmod(os.path.join(d, b), 0o755)
    for m in _glob.glob(os.path.join(srcdir, "man/*.1")):
        shutil.copy2(m, os.path.join(str(ctx.destdir), "usr/share/man/man1"))
