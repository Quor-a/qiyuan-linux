"""patch —— 应用 diff 补丁

https://savannah.gnu.org/projects/patch
许可证：GPL-3.0-or-later
"""

name = "patch"
version = "2.8"
release = 1
summary = "应用 diff 补丁"
homepage = "https://savannah.gnu.org/projects/patch"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums patch
source = ["https://mirrors.aliyun.com/gnu/patch/patch-2.8.tar.gz"]
sha256 = ["308a4983ff324521b9b21310bfc2398ca861798f02307c79eb99bb0e0d2bf980"]

depends = []
makedepends = []
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
