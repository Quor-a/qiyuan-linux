"""kmod —— 内核模块加载与管理

https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git
许可证：GPL-2.0-or-later AND LGPL-2.1-or-later
"""

name = "kmod"
version = "34.1"
release = 1
summary = "内核模块加载与管理"
homepage = "https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git"
license = "GPL-2.0-or-later AND LGPL-2.1-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums kmod
source = ["https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-34.tar.xz"]
sha256 = ["12e7884484151fbd432b6a520170ea185c159f4393c7a2c2a886ab820313149a"]

depends = ["openssl", "zlib", "xz", "zstd"]
makedepends = ["openssl", "zlib", "xz", "zstd"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    # kmod 发行 tar 包缺 autotools 辅助文件；gtk-doc.m4 缺失时
    # NOCONFIGURE 环境下仍会触发 aclocal，先补空 m4 再 autoreconf
    # 上游 tarball 里 m4/gtk-doc.m4 与 libkmod/docs/gtk-doc.make 是指向
    # /usr/share/gtk-doc 的悬空符号链接（宿主没装 gtk-doc 时必炸 autoreconf）
    ctx.run("find . -xtype l -delete")
    ctx.run("mkdir -p m4 libkmod/docs && : > m4/gtk-doc.m4 && : > libkmod/docs/gtk-doc.make")
    ctx.run("autoreconf -f -i")
    ctx.run("./configure --prefix=/usr --with-zstd --with-xz --with-zlib --with-openssl --disable-manpages --disable-gtk-doc")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
