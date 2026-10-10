"""gui-base —— 图形栈基础元包（X11/Wayland 与工具包）


许可证：Meta
"""

name = "gui-base"
version = "1.0.0"
release = 1
summary = "图形栈基础元包（X11/Wayland 与工具包）"
homepage = ""
license = "Meta"

source = []
sha256 = []

depends = ["mesa", "libxkbcommon", "libinput", "gtk3", "fontconfig", "freetype", "harfbuzz", "cairo", "pango", "gdk-pixbuf", "hicolor-icon-theme", "adwaita-icon-theme", "dbus"]
makedepends = ["mesa", "libxkbcommon", "libinput", "gtk3", "fontconfig", "freetype", "harfbuzz", "cairo", "pango", "gdk-pixbuf", "hicolor-icon-theme", "adwaita-icon-theme", "dbus"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("true")


def package(ctx):
    ctx.run("mkdir -p {}/usr/share/lanxiu".format(ctx.destdir))
