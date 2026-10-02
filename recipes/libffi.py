"""libffi —— 外部函数接口库（解释器与 JIT 依赖）

https://sourceware.org/libffi
许可证：MIT
"""

name = "libffi"
version = "3.4.7"
release = 1
summary = "外部函数接口库（解释器与 JIT 依赖）"
homepage = "https://sourceware.org/libffi"
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libffi
source = ["https://ghproxy.net/https://github.com/libffi/libffi/releases/download/v3.4.7/libffi-3.4.7.tar.gz"]
sha256 = ["138607dee268bdecf374adf9144c00e839e38541f75f24a1fcf18b78fda48b2d"]

depends = []
makedepends = []
provides = ["libffi.so.8"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
