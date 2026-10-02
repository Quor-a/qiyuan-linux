"""compositeproto —— X 合成协议头文件


许可证：MIT
"""

name = "compositeproto"
version = "0.4.2"
release = 1
summary = "X 合成协议头文件"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums compositeproto
source = ["https://www.x.org/archive/individual/proto/compositeproto-0.4.1.tar.bz2"]
sha256 = ["e2744576731e1416503aade0d58a7861d0260f70b993351473a9f38ced606984"]

depends = ["xorgproto"]
makedepends = ["xorgproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    # 协议头已统一由 xorgproto 提供，此包仅作依赖别名
    ctx.run("mkdir -p {}/usr/share/qy/aliases".format(ctx.destdir))
    ctx.run("touch {}/usr/share/qy/aliases/compositeproto".format(ctx.destdir))
