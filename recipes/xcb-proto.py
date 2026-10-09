"""xcb-proto —— XCB 协议描述（生成绑定代码用）


许可证：MIT
"""

name = "xcb-proto"
version = "1.17.0"
release = 1
summary = "XCB 协议描述（生成绑定代码用）"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums xcb-proto
source = ["https://www.x.org/archive/individual/xcb/xcb-proto-1.17.0.tar.xz"]
sha256 = ["2c1bacd2110f4799f74de6ebb714b94cf6f80fb112316b1219480fd22562148c"]

depends = []
makedepends = ["python"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
