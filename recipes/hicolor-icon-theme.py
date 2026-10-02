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
source = ["https://example.org/src/hicolor-icon-theme-0.18.tar.xz"]
sha256 = []
checksum_pending = True

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("true")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
