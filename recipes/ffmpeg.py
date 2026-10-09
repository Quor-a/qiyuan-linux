"""ffmpeg —— 音视频编解码

许可证：LGPL-2.1-or-later / GPL-2.0-or-later（取决于启用项）

浏览器播放视频、系统做任何音视频处理都要它。
没有它，浏览器里所有视频都是黑屏——用户会以为网站坏了。
"""
from __future__ import annotations

name = "ffmpeg"
version = "7.1"
release = 1
summary = "音视频编解码与处理"
homepage = "https://ffmpeg.org/"
license = "LGPL-2.1-or-later"

source = ["https://ffmpeg.org/releases/ffmpeg-7.1.tar.xz"]
sha256 = ["40973d44970dbc83ef302b0609f2e74982be2d85916dd2ee7472d30678a7abe6"]

depends = ["zlib", "libwebp"]
makedepends = ["pkgconf", "nasm", "zlib", "libwebp"]
provides = ["libavcodec.so.61"]
requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    ctx.run("./configure" + " " .join(ctx.configure_args()) + " --prefix=/usr"
            " --enable-shared --disable-static"
            " --enable-gpl --enable-libwebp"
            " --disable-doc")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
