"""pipewire —— 音视频服务器与路由（兼容 PulseAudio/JACK）

许可证：MIT AND LGPL-2.1-or-later AND Apache-2.0
"""

name = "pipewire"
version = "1.4.1"
release = 1
summary = "音视频服务器与路由（兼容 PulseAudio/JACK）"
license = "MIT AND LGPL-2.1-or-later AND Apache-2.0"

source = ["https://example.org/src/pipewire-1.4.1.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["alsa-lib", "glib", "libudev", "libsndfile", "dbus"]
makedepends = ["meson", "ninja", "python", "alsa-lib", "glib", "libudev", "libsndfile", "dbus"]
provides = ["pulseaudio"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Ddocs=disabled -Dtests=disabled")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
