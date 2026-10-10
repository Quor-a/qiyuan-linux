"""flex —— 词法分析器生成器

https://github.com/westes/flex
许可证：BSD-2-Clause
"""

name = "flex"
version = "2.6.4"
release = 1
summary = "词法分析器生成器"
homepage = "https://github.com/westes/flex"
license = "BSD-2-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums flex
source = ["https://ghproxy.net/https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz"]
sha256 = ["e87aae032bf07c26f85ac0ed3250998c37621d95f8bd748b31f15b33c45ee995"]

depends = ["m4", "bison"]
makedepends = ["m4", "bison"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --docdir=/usr/share/doc/flex")
    # flex 2.6.4 上游 bug：stage1flex（构建机原生的引导工具）的 *.o 编译规则
    # 用的是 $(CC)（交叉时=aarch64 编译器）+ 目标 sysroot 头——原生 cc 吃到
    # aarch64 的 bits/math-vector.h（__Float32x4_t 等类型）直接报错。
    # 发行版通用修法：stage1flex 对象单独用宿主 cc 编译、不注入目标头路径。
    # （链接规则本来就用 CC_FOR_BUILD，只有编译规则漏了。）
    if ctx.configure_args():
        # flex 2.6.4 上游 bug：stage1flex（构建机原生引导工具）的编译规则
        # 用 $(CC)（交叉时=aarch64 编译器）+ 目标 sysroot 头（builder 经
        # CFLAGS -I 与环境 CPATH 双路注入）——原生 cc 吃 aarch64 的
        # bits/math-vector.h（__Float32x4_t）必炸。发行版通用修法：
        # 1) 把 src/Makefile 里 stage1flex-*.o 规则的 $(CC) 换成
        #    $(CC_FOR_BUILD)；2) 编译时 env -u CPATH。
        # （链接规则本来就 用 CC_FOR_BUILD，只有编译规则漏了。）
        ctx.run("sed -i '/stage1flex-.*\\.o:/s/\\$(CC) /\\$(CC_FOR_BUILD) /' "
                "src/Makefile")
        objs = " ".join(f"stage1flex-{o}.o" for o in
            ("scan", "buf", "ccl", "dfa", "ecs", "filter", "gen", "main",
             "misc", "nfa", "options", "parse", "regex", "scanflags",
             "scanopt", "skel", "sym", "tables", "tables_shared", "tblcmp",
             "yylex"))
        ctx.run(f"env -u CPATH make -C src {objs} "
                "CC=gcc CC_FOR_BUILD=gcc CPPFLAGS= CFLAGS='-O2' ",
                check=False)
        # stage1flex 虽然编译出来了，但它的 config.h 来自交叉 configure
        # （host=aarch64 的 rpl_realloc 等重定义混进宿主二进制）——运行必
        # segfault。stage1scan.c 只是 scan.l 的生成物，直接用构建机的
        # flex 生成，绕开这个自举死结（Debian/Fedora 同样处理）。
        # 预生成 stage1scan.c 后，把构建树里的 stage1flex 换成宿主 flex：
        # make 规则 "stage1scan.c: scan.l stage1flex" 里 stage1flex 每次重链
        # 都比 stage1scan.c 新，必然强制重跑 segfault 的交叉版 stage1flex。
        # 宿主 flex 2.6.4 与目标版本一致，输出等价（Debian/Fedora 同法）。
        # 用宿主 flex 预生成 stage1scan.c，并把 Makefile 里那条
        # "./stage1flex -o stage1scan.c" 规则命令替换成 true（stage1flex
        # 的 config.h 来自交叉 configure，在构建机上跑必 segfault——
        # 上游 flex 2.6.4 的交叉自举 bug，Debian/Fedora 同样绕过）。
        ctx.run("flex -o src/stage1scan.c src/scan.l && "
                "sed -i 's|^\\t\\./stage1flex\\$(EXEEXT)|\\ttrue|' "
                "src/Makefile && touch src/stage1scan.c", check=False)
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
