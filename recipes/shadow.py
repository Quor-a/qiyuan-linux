"""shadow —— 账户与口令管理（useradd passwd）

https://github.com/shadow-maint/shadow
许可证：BSD-3-Clause AND GPL-2.0-or-later
"""

name = "shadow"
version = "4.17.4"
release = 1
summary = "账户与口令管理（useradd passwd）"
homepage = "https://github.com/shadow-maint/shadow"
license = "BSD-3-Clause AND GPL-2.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums shadow
source = ["https://github.com/shadow-maint/shadow/releases/download/4.17.4/shadow-4.17.4.tar.xz"]
sha256 = ["b1cd6c9cc0bea2e51541b301f86b8395a1b6c48ddda56937da5bd4daaf1c4632"]

depends = []
makedepends = []
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    # readpassphrase 来自 libbsd（宿主专属交互密码输入），目标系统用
    # shadow 自带的实现即可
    ctx.run("./configure --prefix=/usr --disable-static --with-group-name-max-length=32 --without-libbsd")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
