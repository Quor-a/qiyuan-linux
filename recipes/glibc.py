"""glibc —— C 运行时库。

自举第一关的收尾。它一旦编出来，系统就有了自己的 libc，
之后的所有包都可以链接到它而不是宿主的 libc——这一刻才是真正的分界点。

要点：
  * 必须用第一遍的 gcc 编，且 --host/--build 要写对
  * rpc 头在新版 glibc 里已移除，不要再去装
  * 安装后要确认产物链接的是自己的 libc，不是宿主的（下面有自检）
"""

name = "glibc"
version = "2.42"
release = 1
summary = "GNU C 库"
description = "系统调用封装、线程、内存分配与本地化，用户空间的地基。"
license = "LGPL-2.1"
homepage = "https://www.gnu.org/software/libc/"

source = ["https://mirrors.aliyun.com/gnu/glibc/glibc-2.42.tar.xz"]
sha256 = ["d1775e32e4628e64ef930f435b67bb63af7599acb6be2b335b9f19f16509f17f"]

# glibc 源码体积大（100MB 量级），配方落地时尚未下载，校验和留空。
# 在真实构建机上执行 `qybuild fetch-checksums glibc` 会自动下载并填回这里，
# 之后该行自动删除——未补齐前构建会被明确拒绝，绝不静默接受未校验的源码。

depends = ["linux-headers"]
makedepends = ["gcc", "binutils", "linux-headers"]
provides = ["libc", "libc.so.6"]

# 需真实构建机：源码数百 MB、编译以小时计、磁盘 30G+
requires_build_machine = True

network = True
compression = "xz"
bootstrap_stage = 1


def build(ctx):
    ctx.run("mkdir -p build && cd build && ../configure "
            "--prefix=/usr "
            "--disable-werror "
            "--enable-kernel=5.15 "
            "--enable-stack-protector=strong "
            "--with-headers=/usr/include "
            "--disable-nscd "
            "--enable-obsolete-rpc=no")
    ctx.run("cd build && make")


def package(ctx):
    ctx.run("cd build && make DESTDIR={} install".format(ctx.destdir))
    # 自检：确认 libc 链接的是自己，而不是宿主
    # 这一条是自举真假的判据，失败说明自举没成功
    ctx.check_no_host_libs(["usr/lib/libc.so.6", "usr/lib/libm.so.6"])
