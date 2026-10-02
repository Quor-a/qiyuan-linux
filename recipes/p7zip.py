"""p7zip —— 7z / zip / rar 等格式的解压与打包

许可证：LGPL-2.1-or-later（部分 unRAR 代码有额外限制）

日常拿到压缩包有一半是 zip、rar、7z。
libarchive 覆盖不了 rar，缺了这个包用户遇到 .rar 只能干瞪眼。
"""
from __future__ import annotations

name = "p7zip"
version = "17.05"
release = 1
summary = "7z / zip / rar 等格式的解压与打包"
homepage = "https://github.com/p7zip-project/p7zip"
license = "LGPL-2.1-or-later"

source = ["https://ghproxy.net/https://github.com/p7zip-project/p7zip/archive/refs/tags/v17.05.tar.gz"]
sha256 = ["d2788f892571058c08d27095c22154579dfefb807ebe357d145ab2ddddefb1a6"]

depends = ["gcc-runtime"]
makedepends = ["gcc-runtime"]
provides = ["7z", "7za"]
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("cp makefile.linux_amd64 makefile.machine")
    ctx.run("make -f makefile OPTFLAGS=-O2 7za 7zr")


def package(ctx):
    import os
    b = os.path.join(ctx.destdir, "usr", "bin")
    os.makedirs(b, exist_ok=True)
    for x in ("7za", "7zr"):
        ctx.run("install -m 755 bin/{} {}/{}".format(x, b, x))
