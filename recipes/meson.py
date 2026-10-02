"""meson —— 构建系统（很多现代项目改用 meson）


许可证：Apache-2.0
"""

name = "meson"
version = "1.7.0"
release = 1
summary = "构建系统（很多现代项目改用 meson）"
homepage = ""
license = "Apache-2.0"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums meson
source = ["https://example.org/src/meson-1.7.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["python"]
makedepends = ["ninja", "python"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("true")


def package(ctx):
    ctx.run("python3 setup.py install --prefix=/usr --root={} --optimize=1 --skip-build".format(ctx.destdir))
