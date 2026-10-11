"""damageproto —— X 损坏协议头文件


许可证：MIT
"""

name = "damageproto"
version = "1.2.1"
release = 1
summary = "X 损坏协议头文件"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums damageproto
source = ["https://www.x.org/archive/individual/proto/damageproto-1.2.1.tar.bz2"]
sha256 = ["5c7c112e9b9ea8a9d5b019e5f17d481ae20f766cb7a4648360e7c1b46fc9fc5b"]

depends = ["xorgproto"]
makedepends = ["xorgproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    # 老 X 协议包的 config.sub/guess 不认识 qiyuan/aarch64 三元组——用宿主新版覆盖
    ctx.run("cp /usr/share/misc/config.sub config.sub 2>/dev/null || true; cp /usr/share/misc/config.guess config.guess 2>/dev/null || true")
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    # 协议头已统一由 xorgproto 提供，此包仅作依赖别名
    ctx.run("mkdir -p {}/usr/share/qy/aliases".format(ctx.destdir))
    ctx.run("touch {}/usr/share/qy/aliases/damageproto".format(ctx.destdir))
