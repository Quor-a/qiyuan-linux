"""hicolor-icon-theme —— 图标主题目录规范骨架


许可证：
"""

name = "hicolor-icon-theme"
version = "0.18"
release = 1
summary = "图标主题目录规范骨架"
homepage = ""
license = ""

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums hicolor-icon-theme
source = ["https://icon-theme.freedesktop.org/releases/hicolor-icon-theme-0.18.tar.xz"]
sha256 = ["db0e50a80aa3bf64bb45cbca5cf9f75efd9348cf2ac690b907435238c3cf81d7"]
checksum_pending = False

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    # 0.18 起改用 meson，源码包内只有 index.theme + meson.build
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr " + x + "")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
