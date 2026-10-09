"""sqlite —— 嵌入式关系型数据库引擎

https://sqlite.org
许可证：blessing
"""

name = "sqlite"
version = "3.49.2"
release = 1
summary = "嵌入式关系型数据库引擎"
homepage = "https://sqlite.org"
license = "blessing"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums sqlite
source = ["https://sqlite.org/2025/sqlite-autoconf-3490200.tar.gz"]
sha256 = ["5c6d8697e8a32a1512a9be5ad2b2e7a891241c334f56f8b0fb4fc6051e1652e8"]

depends = ["zlib", "readline"]
makedepends = ["zlib", "readline"]
provides = ["libsqlite3.so.0"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    # sqlite 的 configure 是自写脚本，不认 --with-sysroot
    args = [a for a in ctx.configure_args() if not a.startswith("--with-sysroot")]
    ctx.run("./configure " + " ".join(args) + " --prefix=/usr --disable-static --enable-fts5")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
