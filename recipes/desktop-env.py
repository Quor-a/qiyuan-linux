"""desktop-env —— 桌面环境元包（会话基础组件）


许可证：Meta
"""

name = "desktop-env"
version = "1.0.0"
release = 1
summary = "桌面环境元包（会话基础组件）"
homepage = ""
license = "Meta"

source = []
sha256 = []

depends = ["gui-base", "alsa-lib", "pipewire", "dbus", "polkit", "desktop-file-utils", "shared-mime-info", "xorg-server"]
makedepends = ["gui-base", "alsa-lib", "pipewire", "dbus", "polkit", "desktop-file-utils", "shared-mime-info", "xorg-server"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("true")


def package(ctx):
    ctx.run("mkdir -p {}/usr/share/lanxiu".format(ctx.destdir))
