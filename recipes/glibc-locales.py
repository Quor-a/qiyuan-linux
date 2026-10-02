"""glibc-locales —— 语言环境数据（locale）

由 glibc 的 localedata 生成。没有它，设了 LANG=zh_CN.UTF-8
也不会生效：程序找不到对应 locale 就静默回退到 C，
表现为"我明明设了中文却还是乱码"——这是最难排查的一类问题。

glibc 主配方不带 locale（生成它要很久且占空间），
单独拆成这个包，按需安装。

装机必须装：中文用户拿到系统的第一件事就是能看懂中文。
"""
from __future__ import annotations

name = "glibc-locales"
version = "2.42"
release = 1
summary = "语言环境数据（locale）"
homepage = "https://www.gnu.org/software/libc/"
license = "LGPL-2.1-or-later AND GPL-2.0-or-later"

# locale 由 glibc 源码树里的 localedata 生成，不是独立上游
source = ["https://mirrors.aliyun.com/gnu/glibc/glibc-2.42.tar.xz"]
sha256 = ["d1775e32e4628e64ef930f435b67bb63af7599acb6be2b335b9f19f16509f17f"]

depends = ["glibc"]
makedepends = ["glibc"]
provides = ["locale-data"]

requires_build_machine = True
network = False
compression = "gz"

# 装机默认生成的 locale。C.UTF-8 是兜底——
# 任何 glibc 都有它，比 C 好（至少认得多字节字符）
DEFAULT_LOCALES = [
    "zh_CN.UTF-8",     # 简体中文
    "zh_TW.UTF-8",     # 繁体中文
    "en_US.UTF-8",     # 英文
    "ja_JP.UTF-8",     # 日文
    "ko_KR.UTF-8",     # 韩文
    "de_DE.UTF-8",
    "fr_FR.UTF-8",
    "C.UTF-8",         # 兜底
]


def build(ctx):
    # 只生成 locale 数据，不重编整个 glibc
    ctx.run("mkdir -p build-locales")
    ctx.run("cd build-locales && ../configure --prefix=/usr"
            " --disable-profile --disable-werror")
    ctx.run("make -C build-locales localedata/install-locales"
            " DESTDIR={} localedef_args=--no-archive".format(ctx.destdir))


def package(ctx):
    import os
    # 记录这个包生成了哪些 locale，装机后能查到
    d = os.path.join(ctx.destdir, "usr", "lib", "locale")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, ".qy-generated"), "w") as f:
        f.write("\n".join(DEFAULT_LOCALES) + "\n")
    ctx.log(f"已生成 {len(DEFAULT_LOCALES)} 个 locale")
