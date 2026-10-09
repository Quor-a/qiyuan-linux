"""mo —— 墨语言：启元官方系统开发语言

自举编译的静态类型语言，编译到原生 x86-64 ELF，零 libc 依赖。
启元改造：编译器支持 /usr/lib/mo/ 系统标准库路径，
任何目录直接 `moc prog.mo prog.elf` 即可用标准库。

用途：
- 写系统组件与守护进程（net.mo/pty.mo/fs.mo 直达 syscall）
- 写软件包构建脚本与开发工具（编译器自己就是墨语言写的）
- 四后端：原生 ELF / C / JS / Python

旧包管理（qypkg）继续可用；墨语言开发的工具同样走 qypkg 打包分发。
"""

name = "mo"
version = "1.10.0"
release = 6
summary = "墨语言——启元官方系统开发语言（自举编译器 + 标准库 + 工具链）"
homepage = "https://github.com/Quor-a/qiyuan-linux"
license = "MIT"

# 源码以本地仓库为准（qiyuan-work/mo），打包脚本从仓库根拿
source = []
sha256 = []
checksum_pending = False

depends = []
makedepends = ["binutils"]
provides = ["moc", "mo"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # 本地源码配方：源码在 qiyuan-work/mo（qybuild 无外部 source 可下，
    # 从固定位置同步进来）。改 src/mo/*.mo 后 cat 成 compiler.mo 再编。
    import os
    import shutil
    mo_src = "/home/agentuser/qiyuan-work/mo"
    dst = str(ctx.srcdir)  # build_fn 的 Python cwd 是项目根，必须显式用 srcdir
    for item in ("src", "lib", "examples", "tools", "tests", "docs", "bench",
                 "Makefile", "build.sh", "verify_bootstrap.sh", "README.md",
                 "CHANGELOG.md", "CONTRIBUTING.md", "VERSION"):
        s = os.path.join(mo_src, item)
        t = os.path.join(dst, item)
        if os.path.isdir(s):
            shutil.copytree(s, t, dirs_exist_ok=True)
        elif os.path.isfile(s):
            shutil.copy2(s, t)
    ctx.log("墨语言：build.sh（seed → moc 自举）+ 99 项测试")
    ctx.run("mkdir -p bin && bash build.sh all")
    # 回归：99 项测试 + 三级自举 md5 一致
    ctx.run("bash verify_bootstrap.sh | tail -1")
    ctx.run("bash tests/run.sh | tail -1")


def package(ctx):
    d = ctx.destdir
    ctx.run("mkdir -p {0}/usr/bin {0}/usr/lib/mo {0}/usr/share/doc/mo "
            "{0}/usr/share/mo/examples".format(d))
    ctx.run("install -m755 bin/moc {}/usr/bin/moc".format(d))
    # 工具链包装器：mo build/run/test/boot/fmt/size/info
    ctx.run("install -m755 tools/mo.sh {}/usr/bin/mo".format(d))
    # 标准库 → 系统路径（编译器会搜 /usr/lib/mo/）
    ctx.run("install -m644 lib/*.mo {}/usr/lib/mo/".format(d))
    # 示例与文档
    ctx.run("install -m644 examples/*.mo {}/usr/share/mo/examples/".format(d))
    ctx.run("install -m644 README.md CHANGELOG.md docs/tutorial.md "
            "{}/usr/share/doc/mo/ 2>/dev/null || true".format(d))
    # 冒烟：装好的编译器在临时目录用系统标准库编 hwinfo
    ctx.run("tmp=$(mktemp -d) && cp examples/hwinfo.mo $tmp/ && "
            "(cd $tmp && {}/usr/bin/moc hwinfo.mo hw.elf && ./hw.elf | head -1) && "
            "rm -rf $tmp".format(d))
