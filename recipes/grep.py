"""grep —— 模式匹配与文本搜索

https://www.gnu.org/software/grep
许可证：GPL-3.0-or-later
"""

name = "grep"
version = "3.11"
release = 1
summary = "模式匹配与文本搜索"
homepage = "https://www.gnu.org/software/grep"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums grep
source = ["https://mirrors.aliyun.com/gnu/grep/grep-3.11.tar.gz"]
sha256 = ["1f31014953e71c3cddcedb97692ad7620cb9d6d04fbdc19e0d8dd836f87622bb"]

depends = ["pcre2"]
makedepends = ["pcre2"]
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
