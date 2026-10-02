"""binutils —— 汇编器、链接器与二进制工具。

自举第一关的第二步。要点：
  * 必须在独立目录构建（不能在源码树里，否则会污染）
  * --with-sysroot 让它只认目标系统的头文件，不偷看宿主的
  * 第一遍用宿主的 gcc 编，第二遍用第一遍自己编的 gcc 编 → 闭环
"""

name = "binutils"
version = "2.45"
release = 1
summary = "GNU 二进制工具集（as / ld / objdump 等）"
description = "汇编器、链接器与二进制分析工具，工具链的第一环。"
license = "GPL-3.0"
homepage = "https://www.gnu.org/software/binutils/"

source = ["https://mirrors.aliyun.com/gnu/binutils/binutils-2.45.tar.xz"]
sha256 = ["c50c0e7f9cb188980e2cc97e4537626b1672441815587f1eab69d2a1bfbef5d2"]

# binutils 源码体积大（100MB 量级），配方落地时尚未下载，校验和留空。
# 在真实构建机上执行 `qybuild fetch-checksums binutils` 会自动下载并填回这里，
# 之后该行自动删除——未补齐前构建会被明确拒绝，绝不静默接受未校验的源码。

depends = []
makedepends = ["linux-headers"]
provides = ["ld", "as"]

# 需真实构建机：源码数百 MB、编译以小时计、磁盘 30G+
requires_build_machine = True

network = True
compression = "xz"
bootstrap_stage = 1


def build(ctx):
    # 独立构建目录：源码树保持干净，重编不用解压
    ctx.run("mkdir -p build && cd build && ../configure "
            "--prefix=/usr "
            "--with-sysroot=/ "
            "--enable-gold "
            "--enable-ld=default "
            "--enable-plugins "
            "--enable-shared "
            "--disable-werror "
            "--enable-64-bit-bfd "
            "--with-system-zlib "
            # gprofng 是 C++ 性能分析组件，与 sysroot glibc 的 getopt 声明
            # （C++ 异常规格）冲突，且嵌入式目标系统完全用不到
            "--disable-gprofng ")
    ctx.run("cd build && make tooldir=/usr")


def package(ctx):
    ctx.run("cd build && make DESTDIR={} tooldir=/usr install".format(ctx.destdir))
    # 移除宿主残留的 libtool 归档，它会把构建机路径带进用户系统
    ctx.run("rm -f {}/usr/lib/libbfd.la {}/usr/lib/libopcodes.la".format(
        ctx.destdir, ctx.destdir))
    # binutils 的可执行文件（as/ld/...）动态链 libbfd/libsframe 等 .so，
    # 但它们默认无 RUNPATH：装进目标系统后运行期找不到（libonion 宿主上
    # 更是直接挂）。给工具和 .so 全部写死 RUNPATH，$ORIGIN 相对定位。
    ctx.run(
        "cd {d}/usr/bin && for t in as ld ld.bfd ld.gold nm objdump strip ar "
        "ranlib readelf addr2line size strings objcopy c++filt; do "
        "[ -f $t ] && patchelf --set-rpath '$ORIGIN/../lib' $t || true; done; "
        "cd {d}/usr/lib && for so in libbfd-*.so* libopcodes-*.so* "
        "libctf-nobfd.so* libsframe.so*; do "
        "[ -f $so ] && patchelf --set-rpath '$ORIGIN' $so || true; done"
        .format(d=ctx.destdir))
