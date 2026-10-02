"""diffutils —— 文件比较工具（diff cmp）

https://www.gnu.org/software/diffutils
许可证：GPL-3.0-or-later
"""

name = "diffutils"
version = "3.11"
release = 1
summary = "文件比较工具（diff cmp）"
homepage = "https://www.gnu.org/software/diffutils"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums diffutils
source = ["https://mirrors.aliyun.com/gnu/diffutils/diffutils-3.11.tar.gz"]
sha256 = ["c80a3c2bf87e252fe7d605b8ba6bf928d75a90b55f3bfcf7c4a4f337ec62fc31"]

depends = []
makedepends = []
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
