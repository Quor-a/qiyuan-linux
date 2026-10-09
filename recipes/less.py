"""less —— 文本文件分页查看器

https://greenwoodsoftware.com/less
许可证：GPL-3.0-or-later
"""

name = "less"
version = "668"
release = 1
summary = "文本文件分页查看器"
homepage = "https://greenwoodsoftware.com/less"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums less
source = ["https://mirrors.aliyun.com/gnu/less/less-668.tar.gz"]
sha256 = ["2819f55564d86d542abbecafd82ff61e819a3eec967faa36cd3e68f1596a44b8"]

depends = ["ncurses", "pcre2"]
makedepends = ["ncurses", "pcre2"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --sysconfdir=/etc")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
