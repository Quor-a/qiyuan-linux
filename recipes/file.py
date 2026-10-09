"""file —— 按内容识别文件类型

https://www.darwinsys.com/file
许可证：BSD-2-Clause
"""

name = "file"
version = "5.46"
release = 1
summary = "按内容识别文件类型"
homepage = "https://www.darwinsys.com/file"
license = "BSD-2-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums file
source = ["https://ghproxy.net/https://github.com/file/file/archive/refs/tags/FILE5_46.tar.gz"]
sha256 = ["73c5f11a8edf0fded2fe3471b23a7fccb3f3369a13ea612529b869c8dc96aa2b"]

depends = ["zlib"]
makedepends = ["zlib"]
provides = ["libmagic.so.1"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    # GitHub tag 源码无预生成 configure，须先 autoreconf
    ctx.run("autoreconf -f -i -s")
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    # 交叉编译时 magic.mgc 需要本机 file 生成（上游硬性要求：
    # "Cannot use the installed version of file to cross-compile"）。
    # 交给 make 时以 FILE_COMPILE 指到宿主 file。
    if ctx.cross is not None:
        ctx.run("make FILE_COMPILE=/usr/bin/file")
    else:
        ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
