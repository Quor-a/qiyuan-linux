"""readline —— 命令行行编辑与历史库

https://tiswww.case.edu/php/chet/readline/rltop.html
许可证：GPL-3.0-or-later
"""

name = "readline"
version = "8.2"
release = 1
summary = "命令行行编辑与历史库"
homepage = "https://tiswww.case.edu/php/chet/readline/rltop.html"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums readline
source = ["https://mirrors.aliyun.com/gnu/readline/readline-8.2.tar.gz"]
sha256 = ["3feb7171f16a84ee82ca18a36d7b9be109a52c04f492a053331d7d1095007c35"]

depends = ["ncurses"]
makedepends = ["ncurses"]
provides = ["libreadline.so.8"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    # bash 内置的 termcap 支持缺位：readline 必须显式链上 ncursesw，
    # 否则 libreadline.so 只 NEED libc，UP/BC 等 termcap 能力符号无人
    # 提供，任何带 LD_LIBRARY_PATH 的构建都会被它炸掉（宿主 awk 实测）。
    ctx.run("./configure --prefix=/usr --disable-static "
            "--with-curses=yes "
            "bash_cv_termcap_lib=libncursesw")
    # configure 有时不填 SHLIB_LIBS（上游已知问题），直接改 Makefile 兜底。
    # 注意：UP/BC 符号在 libtinfo（termlib）里而不是 libncursesw 主库——
    # 本发行版 ncurses 用 --with-termlib 拆分，必须链 tinfow。
    ctx.run("sed -i 's|^SHLIB_LIBS = *$|SHLIB_LIBS = -ltinfow|' shlib/Makefile")
    ctx.run("make SHLIB_LIBS=-ltinfow")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
