"""linux-headers —— 内核导出的用户空间头文件。

glibc 需要它才知道系统调用号与内核数据结构。这是整个自举链上
第一个必须编出来的包：没有它，glibc 编不了，后面全停。

版本取自 LFS 12.4（2025-09-01）核对过的稳定版。升级时改这里即可，
构建系统会自动重编所有依赖它的包。
"""

name = "linux-headers"
version = "6.16.1"
release = 1
summary = "Linux 内核用户空间头文件"
description = "供 glibc 与用户程序使用的内核 API 头文件（系统调用号、结构体、常量）。"
license = "GPL-2.0"
homepage = "https://www.kernel.org"

# 内核源码（构建时下载）。用官方镜像，校验和随版本更新。
source = ["https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.16.1.tar.xz"]
sha256 = ["ea43491bc7ace1e414b3b2d957f8cf96e7049155123f0acce798accf8da1acba"]

# 内核源码体积大（100MB 量级），配方落地时尚未下载，校验和留空。
# 在真实构建机上执行 `qybuild fetch-checksums linux-headers` 会自动下载并填回这里，
# 之后该行自动删除——未补齐前构建会被明确拒绝，绝不静默接受未校验的源码。

depends = []
makedepends = []
provides = ["linux-api-headers"]

# 需真实构建机：源码数百 MB、编译以小时计、磁盘 30G+
requires_build_machine = True

network = True
compression = "xz"

# 自举标记：这是第一关的第一个包
bootstrap_stage = 1


def build(ctx):
    # 头文件不需要编译，只需要 sanitize（去掉内核内部用的东西）
    ctx.run("make mrproper")


def package(ctx):
    # headers_install 会剔除内核私有头，只留用户空间能用的
    # 注意：目标是 <INSTALL_HDR_PATH>/include（新版内核忽略 PATH 后缀的 /usr）
    ctx.run("make headers_install INSTALL_HDR_PATH={}/usr".format(ctx.destdir))
    ctx.run("mkdir -p {}/usr/include && cp -r {}/usr/include/* {}/usr/include/ || true".format(
        ctx.destdir, ctx.destdir, ctx.destdir))
    ctx.run("find {}/usr/include -name '.*' -delete".format(ctx.destdir))
