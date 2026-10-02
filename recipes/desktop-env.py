"""desktop-env —— 桌面环境元包（会话基础组件）


许可证：Meta
"""

name = "desktop-env"
version = "1.0.0"
release = 1
summary = "桌面环境元包（会话基础组件）"
homepage = ""
license = "Meta"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums desktop-env
source = ["https://example.org/src/desktop-env-1.0.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["gui-base", "alsa-lib", "pipewire", "dbus", "polkit", "desktop-file-utils", "shared-mime-info", "xorg-server"]
makedepends = ["gui-base", "alsa-lib", "pipewire", "dbus", "polkit", "desktop-file-utils", "shared-mime-info", "xorg-server"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("true")


def package(ctx):
    ctx.run("mkdir -p {}/usr/share/qiyuan".format(ctx.destdir))
