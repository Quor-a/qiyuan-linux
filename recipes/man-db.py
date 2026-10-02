"""man-db —— 手册页浏览工具（man）

https://www.nongnu.org/man-db
许可证：GPL-3.0-or-later
"""

name = "man-db"
version = "2.13.1"
release = 1
summary = "手册页浏览工具（man）"
homepage = "https://www.nongnu.org/man-db"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums man-db
source = ["https://download.savannah.gnu.org/releases/man-db/man-db-2.13.1.tar.xz"]
sha256 = ["8afebb6f7eb6bb8542929458841f5c7e6f240e30c86358c1fbcefbea076c87d9"]

depends = ["zlib", "gdbm", "libpipeline"]
makedepends = ["zlib", "gdbm", "libpipeline"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-setuid --disable-cache-owner")
    # 预渲染手册 man_db.cat 需要宿主 groff 宏包（目标系统不需要），
    # 直接把它改成 no-op 目标避免 make 失败
    ctx.run("sed -i 's|^man_db.cat:|man_db.cat: DISABLED\nDISABLED:|' manual/Makefile 2>/dev/null || true")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
