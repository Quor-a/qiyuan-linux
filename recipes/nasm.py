"""nasm —— x86 汇编器（ffmpeg 等构建期依赖）

许可证：BSD-2-Clause
"""
from __future__ import annotations

name = "nasm"
version = "2.16.03"
release = 1
summary = "x86 汇编器"
homepage = "https://www.nasm.us/"
license = "BSD-2-Clause"

source = ["https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/nasm-2.16.03.tar.xz"]
sha256 = ["1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148"]

depends = []
makedepends = []
provides = []
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
