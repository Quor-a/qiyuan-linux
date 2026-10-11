"""adwaita-icon-theme —— GNOME 默认图标集

许可证：CC-BY-SA-3.0
"""

name = "adwaita-icon-theme"
version = "48.0"
release = 1
summary = "GNOME 默认图标集"
license = "CC-BY-SA-3.0"

source = ["https://download.gnome.org/sources/adwaita-icon-theme/48/adwaita-icon-theme-48.0.tar.xz"]
sha256 = ["847068888650d9673115be6dbf2bfdc31a46aebc528a6a9db4420e60e656b8d4"]
checksum_pending = False

depends = ["hicolor-icon-theme"]
makedepends = ["meson", "ninja", "hicolor-icon-theme"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr " + x + "")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
