"""xorgproto —— X11 协议头文件（所有 X 客户端的编译前提）


许可证：MIT
"""

name = "xorgproto"
version = "2024.1"
release = 1
summary = "X11 协议头文件（所有 X 客户端的编译前提）"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums xorgproto
source = ["https://www.x.org/archive/individual/proto/xorgproto-2024.1.tar.xz"]
sha256 = ["372225fd40815b8423547f5d890c5debc72e88b91088fbfb13158c20495ccb59"]

depends = []
makedepends = ["util-linux"]
provides = ["fixesproto", "xproto", "xextproto", "inputproto", "kbproto", "renderproto", "randrproto"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
