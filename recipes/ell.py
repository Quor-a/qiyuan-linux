"""ell —— 嵌入式 Linux 基础库（iwd 依赖）

许可证：LGPL-2.1-or-later
"""
from __future__ import annotations

name = "ell"
version = "0.76"
release = 1
summary = "嵌入式 Linux 基础库（iwd 依赖）"
homepage = "https://git.kernel.org/pub/scm/libs/ell/ell.git"
license = "LGPL-2.1-or-later"

source = ["https://www.kernel.org/pub/linux/libs/ell/ell-0.76.tar.xz"]
sha256 = ["a0bf2b5a78450c0c167e3f65c18452ffe4c0f179d48c2a3661e6afaca8017ef9"]

depends = ["glibc"]
makedepends = ["pkgconf", "glibc"]
provides = []
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
