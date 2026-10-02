"""dejavu-fonts —— 启元 Linux 基础字体（TTF）。

GTK/Pango 没有字体文件时文本测量会返回巨大 natural size，
导致 Wayland 下 "taller than 65535" + Cairo surface 溢出崩溃。
"""

name = "dejavu-fonts"
version = "2.37"
release = 1
summary = "DejaVu TTF 基础字体"
description = "基于 Bitstream Vera 的 DejaVu 字体家族，系统基础字体。"
license = "Bitstream Vera / Arev"

source = ["https://downloads.sourceforge.net/project/dejavu/dejavu/2.37/dejavu-fonts-ttf-2.37.tar.bz2"]
sha256 = ["fa9ca4d13871dd122f61258a80d01751d603b4d3ee14095d65453b4e846e17d7"]

depends = ["fontconfig"]
makedepends = []
network = False
compression = "gz"


def build(ctx):
    # 纯字体包，无需编译
    pass


def package(ctx):
    S = str(ctx.srcdir)
    ctx.run(
        "mkdir -p {1}/usr/share/fonts/dejavu && "
        "install -m 0644 {0}/ttf/DejaVuSans.ttf "
        "{0}/ttf/DejaVuSans-Bold.ttf "
        "{0}/ttf/DejaVuSansMono.ttf "
        "{0}/ttf/DejaVuSerif.ttf "
        "{1}/usr/share/fonts/dejavu/".format(S, ctx.destdir)
    )
