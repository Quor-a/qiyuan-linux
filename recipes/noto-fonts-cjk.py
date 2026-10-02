"""noto-fonts-cjk —— 启元 Linux 中文字体（Noto Sans CJK）。

只有 DejaVu（西文）时 GTK/Pango 中文渲染为 tofu 方框。
Noto Sans CJK 覆盖简繁日韩四种字形，Pango 经 fontconfig 自动回退。
源：Ubuntu pool fonts-noto-cjk_20230817+repack1.orig.tar.xz（GitHub 直连不稳）。
"""

name = "noto-fonts-cjk"
version = "20230817"
release = 1
summary = "Noto Sans CJK 中文字体"
description = "Google Noto Sans CJK (SC/TC/JP/KR)，系统中文渲染字体。"
license = "OFL-1.1"

source = ["http://archive.ubuntu.com/ubuntu/pool/main/f/fonts-noto-cjk/fonts-noto-cjk_20230817+repack1.orig.tar.xz"]
sha256 = ["544a4f53d2dbf35d02760e1e4631228431c384fcd729a18dd6257adc4c62fee3"]

depends = ["fontconfig"]
makedepends = []
network = False
compression = "xz"


def build(ctx):
    pass


def package(ctx):
    S = str(ctx.srcdir)
    ctx.run(
        "mkdir -p {0}/usr/share/fonts/notocjk && "
        "install -m 0644 {1}/Sans/OTC/NotoSansCJK-Regular.ttc "
        "{0}/usr/share/fonts/notocjk/".format(ctx.destdir, S)
    )
