"""meson —— 构建系统（很多现代项目改用 meson）


许可证：Apache-2.0
"""

name = "meson"
version = "1.7.0"
release = 1
summary = "构建系统（很多现代项目改用 meson）"
homepage = ""
license = "Apache-2.0"

source = ["https://github.com/mesonbuild/meson/releases/download/1.7.0/meson-1.7.0.tar.gz"]
sha256 = ["08efbe84803eed07f863b05092d653a9d348f7038761d900412fddf56deb0284"]

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
