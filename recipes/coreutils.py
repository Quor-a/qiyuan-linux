"""coreutils —— 基础文件/文本/shell 工具集（ls cp mv 等）

https://www.gnu.org/software/coreutils
许可证：GPL-3.0-or-later
"""

name = "coreutils"
version = "9.6"
release = 1
summary = "基础文件/文本/shell 工具集（ls cp mv 等）"
homepage = "https://www.gnu.org/software/coreutils"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums coreutils
source = ["https://mirrors.aliyun.com/gnu/coreutils/coreutils-9.6.tar.xz"]
sha256 = ["7a0124327b398fd9eb1a6abde583389821422c744ffa10734b24f557610d3283"]

depends = ["glibc"]
makedepends = ["glibc"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --without-selinux --enable-no-install-program=kill,uptime")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
