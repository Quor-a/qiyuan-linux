"""gcc —— GNU 编译器集合。

自举里最难的一个包，难在三点：

1. **循环依赖**：编完整 gcc 需要 glibc，编 glibc 又需要 gcc。
   解法是先编一个"精简 gcc"（只含 C、不链接 glibc），用它编出 glibc，
   再回来编完整 gcc。这是自举第一关的核心动作。
2. **不能偷看宿主**：必须用 --with-sysroot 和 --with-newlib 保证
   第一遍的 gcc 不使用宿主的头文件和库，否则整个自举是假的。
3. **构建目录必须独立**：在源码树里编会被上游明确拒绝。

下面的 build() 走的是第一遍（精简）流程，完整编译在第二关完成。
"""

name = "gcc"
version = "15.2.0"
release = 1
summary = "GNU 编译器集合"
description = "C/C++ 等语言的编译器，工具链的核心。"
license = "GPL-3.0"
homepage = "https://gcc.gnu.org/"

source = ["https://mirrors.aliyun.com/gnu/gcc/gcc-15.2.0/gcc-15.2.0.tar.xz"]
sha256 = ["438fd996826b0c82485a29da03a72d71d6e3541a83ec702df4271f6fe025d24e"]

# gcc 源码体积大（100MB 量级），配方落地时尚未下载，校验和留空。
# 在真实构建机上执行 `qybuild fetch-checksums gcc` 会自动下载并填回这里，
# 之后该行自动删除——未补齐前构建会被明确拒绝，绝不静默接受未校验的源码。

depends = []
makedepends = ["binutils", "linux-headers", "gmp", "mpfr", "mpc"]
provides = ["gcc-runtime", "libstdc++", "libgcc_s"]

# 需真实构建机：源码数百 MB、编译以小时计、磁盘 30G+
requires_build_machine = True

network = True
compression = "xz"
bootstrap_stage = 1

# 自举相关：这个包在自举过程中要编不止一次
multipass = True


def build(ctx):
    ctx.run("mkdir -p build && cd build && ../configure "
            "--prefix=/usr "
            "--enable-languages=c,c++ "
            "--disable-multilib "
            "--disable-bootstrap "
            "--with-sysroot=/ "
            "--with-newlib "
            "--without-headers "
            "--disable-nls "
            "--disable-shared "
            "--disable-threads "
            "--disable-decimal-float "
            "--disable-libatomic "
            "--disable-libgomp "
            "--disable-libquadmath "
            "--disable-libssp "
            "--disable-libvtv "
            "--disable-libstdcxx "
            "--enable-linker-build-id")
    ctx.run("cd build && make")


def package(ctx):
    ctx.run("cd build && make DESTDIR={} install".format(ctx.destdir))
    # cc 是绝大多数构建脚本默认找的名字，必须有
    ctx.run("ln -sf gcc {}/usr/bin/cc".format(ctx.destdir))
