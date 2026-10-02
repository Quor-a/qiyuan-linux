"""gui-base —— 图形栈基础元包（X11/Wayland 与工具包）


许可证：Meta
"""

name = "gui-base"
version = "1.0.0"
release = 1
summary = "图形栈基础元包（X11/Wayland 与工具包）"
homepage = ""
license = "Meta"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums gui-base
source = ["https://example.org/src/gui-base-1.0.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["mesa", "libxkbcommon", "libinput", "gtk3", "fontconfig", "freetype", "harfbuzz", "cairo", "pango", "gdk-pixbuf", "hicolor-icon-theme", "adwaita-icon-theme", "dbus"]
makedepends = ["mesa", "libxkbcommon", "libinput", "gtk3", "fontconfig", "freetype", "harfbuzz", "cairo", "pango", "gdk-pixbuf", "hicolor-icon-theme", "adwaita-icon-theme", "dbus"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("true")


def package(ctx):
    ctx.run("mkdir -p {}/usr/share/qiyuan".format(ctx.destdir))
