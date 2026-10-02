#!/usr/bin/env python3
"""生成核心包配方。

数据来源是各上游项目的真实版本与依赖关系，按 LFS 12.x / BLFS 的稳定组合
整理。生成的是配方文件本身（可手工维护），不是中间产物。

这些配方绝大多数 requires_build_machine = True：它们要下载源码、
编译数分钟到数小时，沙盒环境跑不了。但依赖关系是真实的，
足以驱动依赖求解、并行分层、重建闭包、安全扫描在正常规模上验证。
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "recipes"

# (name, version, summary, depends, makedepends, provides, homepage, license,
#  configure, extra)
# configure 是给 autotools 类项目用的；None 表示用自定义 build
PKGS = [
    # ---------------------------------------------------------- 基础库
    dict(name="zlib", version="1.3.1",
         summary="通用无损数据压缩库",
         homepage="https://zlib.net", license="Zlib",
         provides=["libz.so.1"],
         configure=None,
         build=["make"],
         package=["make DESTDIR={destdir} install"]),

    dict(name="xz", version="5.6.4",
         summary="XZ / LZMA 压缩工具与库",
         homepage="https://tukaani.org/xz", license="GPL-2.0-or-later AND PublicDomain",
         provides=["liblzma.so.5"],
         configure="--prefix=/usr --disable-static --docdir=/usr/share/doc/xz",
         ),

    dict(name="zstd", version="1.5.7",
         summary="Zstandard 实时压缩算法与库",
         homepage="https://github.com/facebook/zstd", license="BSD-3-Clause",
         depends=["zlib"], provides=["libzstd.so.1"],
         configure=None,
         build=["make PREFIX=/usr"],
         package=["make PREFIX=/usr DESTDIR={destdir} install"]),

    dict(name="openssl", version="3.5.0",
         summary="TLS/SSL 与通用密码学库",
         homepage="https://www.openssl.org", license="Apache-2.0",
         depends=["zlib"], provides=["libssl.so.3", "libcrypto.so.3"],
         configure=None,
         build=["./config --prefix=/usr --openssldir=/etc/ssl "
                "--libdir=lib shared zlib-dynamic",
                "make"],
         package=["make DESTDIR={destdir} install_sw"]),

    dict(name="ncurses", version="6.5",
         summary="终端处理库（供 bash、less、vi 等使用）",
         homepage="https://invisible-island.net/ncurses", license="MIT",
         provides=["libncursesw.so.6"],
         configure="--prefix=/usr --with-shared --without-debug "
                   "--enable-widec --with-cxx-shared",
         ),

    dict(name="readline", version="8.2",
         summary="命令行行编辑与历史库",
         homepage="https://tiswww.case.edu/php/chet/readline/rltop.html",
         license="GPL-3.0-or-later",
         depends=["ncurses"], provides=["libreadline.so.8"],
         configure="--prefix=/usr --disable-static",
         ),

    dict(name="expat", version="2.7.0",
         summary="流式 XML 解析库",
         homepage="https://libexpat.github.io", license="MIT",
         provides=["libexpat.so.1"],
         configure="--prefix=/usr --disable-static",
         ),

    dict(name="libffi", version="3.4.7",
         summary="外部函数接口库（解释器与 JIT 依赖）",
         homepage="https://sourceware.org/libffi", license="MIT",
         provides=["libffi.so.8"],
         configure="--prefix=/usr --disable-static",
         ),

    dict(name="pcre2", version="10.45",
         summary="Perl 兼容正则表达式库",
         homepage="https://www.pcre.org", license="BSD-3-Clause",
         provides=["libpcre2-8.so.0"],
         configure="--prefix=/usr --enable-pcre2-16 --enable-pcre2-32 "
                   "--disable-static",
         ),

    dict(name="sqlite", version="3.49.2",
         summary="嵌入式关系型数据库引擎",
         homepage="https://sqlite.org", license="blessing",
         depends=["zlib", "readline"], provides=["libsqlite3.so.0"],
         configure="--prefix=/usr --disable-static "
                   "--enable-fts5 --enable-readline",
         ),

    dict(name="libxml2", version="2.14.3",
         summary="XML 解析与处理库",
         homepage="https://gitlab.gnome.org/GNOME/libxml2", license="MIT",
         depends=["zlib", "xz"], provides=["libxml2.so.2"],
         configure="--prefix=/usr --disable-static --with-history",
         ),

    dict(name="curl", version="8.13.0",
         summary="命令行数据传输工具与 libcurl",
         homepage="https://curl.se", license="curl",
         depends=["openssl", "zlib", "zstd"], provides=["libcurl.so.4"],
         configure="--prefix=/usr --disable-static --with-openssl "
                   "--with-zlib --with-zstd --enable-threaded-resolver",
         ),

    dict(name="gdbm", version="1.25",
         summary="GNU 数据库例程库",
         homepage="https://www.gnu.org.ua/software/gdbm", license="GPL-3.0-or-later",
         depends=["readline"], provides=["libgdbm.so.6"],
         configure="--prefix=/usr --disable-static --enable-libgdbm-compat",
         ),

    # ---------------------------------------------------------- 核心工具
    dict(name="bash", version="5.3.0",
         summary="GNU Bourne-Again Shell（系统默认 shell）",
         homepage="https://www.gnu.org/software/bash", license="GPL-3.0-or-later",
         depends=["readline", "ncurses"],
         provides=["/bin/sh", "sh"],
         configure="--prefix=/usr --without-bash-malloc --with-installed-readline",
         ),

    dict(name="coreutils", version="9.6",
         summary="基础文件/文本/shell 工具集（ls cp mv 等）",
         homepage="https://www.gnu.org/software/coreutils",
         license="GPL-3.0-or-later",
         depends=["glibc"],
         configure="--prefix=/usr --enable-no-install-program=kill,uptime",
         ),

    dict(name="diffutils", version="3.11",
         summary="文件比较工具（diff cmp）",
         homepage="https://www.gnu.org/software/diffutils",
         license="GPL-3.0-or-later",
         configure="--prefix=/usr",
         ),

    dict(name="file", version="5.46",
         summary="按内容识别文件类型",
         homepage="https://www.darwinsys.com/file", license="BSD-2-Clause",
         depends=["zlib"], provides=["libmagic.so.1"],
         configure="--prefix=/usr --disable-static",
         ),

    dict(name="findutils", version="4.10.0",
         summary="文件搜索工具（find xargs locate）",
         homepage="https://www.gnu.org/software/findutils",
         license="GPL-3.0-or-later",
         configure="--prefix=/usr --localstatedir=/var/lib/locate",
         ),

    dict(name="gawk", version="5.3.1",
         summary="GNU awk 文本处理语言",
         homepage="https://www.gnu.org/software/gawk", license="GPL-3.0-or-later",
         depends=["readline", "mpfr"],
         configure="--prefix=/usr",
         ),

    dict(name="grep", version="3.11",
         summary="模式匹配与文本搜索",
         homepage="https://www.gnu.org/software/grep", license="GPL-3.0-or-later",
         depends=["pcre2"],
         configure="--prefix=/usr",
         ),

    dict(name="gzip", version="1.13",
         summary="GNU 压缩工具",
         homepage="https://www.gnu.org/software/gzip", license="GPL-3.0-or-later",
         configure="--prefix=/usr",
         ),

    dict(name="make", version="4.4.1",
         summary="GNU make 构建工具",
         homepage="https://www.gnu.org/software/make", license="GPL-3.0-or-later",
         configure="--prefix=/usr",
         ),

    dict(name="patch", version="2.8",
         summary="应用 diff 补丁",
         homepage="https://savannah.gnu.org/projects/patch",
         license="GPL-3.0-or-later",
         configure="--prefix=/usr",
         ),

    dict(name="sed", version="4.9",
         summary="非交互式流编辑器",
         homepage="https://www.gnu.org/software/sed", license="GPL-3.0-or-later",
         configure="--prefix=/usr",
         ),

    dict(name="tar", version="1.35",
         summary="归档工具",
         homepage="https://www.gnu.org/software/tar", license="GPL-3.0-or-later",
         depends=["zlib", "zstd"],
         configure="--prefix=/usr",
         ),

    dict(name="gettext", version="0.25",
         summary="国际化与本地化工具集",
         homepage="https://www.gnu.org/software/gettext",
         license="GPL-3.0-or-later",
         depends=["libxml2", "ncurses"], provides=["libintl.so.8"],
         configure="--prefix=/usr --disable-static --docdir=/usr/share/doc/gettext",
         ),

    dict(name="perl", version="5.40.2",
         summary="Perl 脚本语言（很多构建系统依赖它）",
         homepage="https://www.perl.org", license="GPL-1.0-or-later OR Artistic-1.0-Perl",
         depends=["gdbm", "zlib"], makedepends=["coreutils"],
         configure=None,
         build=["./Configure -des -Dprefix=/usr -Dvendorprefix=/usr "
                "-Dprivlib=/usr/lib/perl5/5.40/core_perl "
                "-Darchlib=/usr/lib/perl5/5.40/core_perl "
                "-Dsitelib=/usr/lib/perl5/5.40/site_perl "
                "-Dsitearch=/usr/lib/perl5/5.40/site_perl "
                "-Dman1dir=/usr/share/man/man1 -Dman3dir=/usr/share/man/man3 "
                "-Duseshrplib -Dusethreads",
                "make"],
         package=["make DESTDIR={destdir} install"]),

    dict(name="python", version="3.13.3",
         summary="Python 语言与运行时",
         homepage="https://www.python.org", license="PSF-2.0",
         depends=["openssl", "zlib", "libffi", "expat", "sqlite", "readline",
                  "ncurses", "xz"],
         makedepends=["coreutils"],
         provides=["python3"],
         configure="--prefix=/usr --enable-shared --with-system-expat "
                   "--with-system-ffi --with-ensurepip=yes "
                   "--enable-optimizations",
         ),

    dict(name="texinfo", version="7.2",
         summary="Texinfo 文档系统（生成 info 手册）",
         homepage="https://www.gnu.org/software/texinfo",
         license="GPL-3.0-or-later",
         depends=["ncurses"], makedepends=["perl"],
         configure="--prefix=/usr",
         ),

    dict(name="util-linux", version="2.41",
         summary="系统杂项工具（mount lsblk fdisk 等）",
         homepage="https://github.com/util-linux/util-linux",
         license="GPL-2.0-or-later AND BSD-3-Clause AND PublicDomain",
         depends=["zlib", "ncurses"],
         makedepends=["coreutils"],
         configure="--prefix=/usr --disable-static --enable-usrdir-path "
                   "--without-systemd --without-systemdsystemunitdir",
         ),

    dict(name="procps-ng", version="4.0.5",
         summary="进程与系统状态工具（ps top kill）",
         homepage="https://gitlab.com/procps-ng/procps",
         license="GPL-2.0-or-later AND LGPL-2.1-or-later",
         depends=["ncurses"],
         configure="--prefix=/usr --disable-static --disable-kill",
         ),

    dict(name="e2fsprogs", version="1.47.3",
         summary="ext2/3/4 文件系统工具",
         homepage="http://e2fsprogs.sourceforge.net",
         license="GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause",
         provides=["libext2fs.so.2"],
         configure="--prefix=/usr --enable-elf-shlibs --disable-libblkid "
                   "--disable-libuuid --disable-uuidd --disable-fsck",
         ),

    dict(name="kmod", version="34.1",
         summary="内核模块加载与管理",
         homepage="https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git",
         license="GPL-2.0-or-later AND LGPL-2.1-or-later",
         depends=["openssl", "zlib", "xz", "zstd"],
         configure="--prefix=/usr --with-zstd --with-xz --with-zlib "
                   "--with-openssl",
         ),

    dict(name="shadow", version="4.17.3",
         summary="账户与口令管理（useradd passwd）",
         homepage="https://github.com/shadow-maint/shadow",
         license="BSD-3-Clause AND GPL-2.0-or-later",
         configure="--prefix=/usr --disable-static --with-group-name-max-length=32",
         ),

    dict(name="iproute2", version="6.14.0",
         summary="网络配置工具（ip ss tc）",
         homepage="https://wiki.linuxfoundation.org/networking/iproute2",
         license="GPL-2.0-or-later",
         depends=["libelf"], makedepends=["bison", "flex"],
         configure=None,
         build=["make PREFIX=/usr"],
         package=["make PREFIX=/usr DESTDIR={destdir} SBINDIR=/usr/sbin install"]),

    dict(name="libelf", version="0.191",
         summary="ELF 文件读写库（elfutils 的一部分）",
         homepage="https://sourceware.org/elfutils",
         license="GPL-2.0-or-later AND LGPL-3.0-or-later",
         depends=["zlib", "zstd"], provides=["libelf.so.1"],
         configure="--prefix=/usr --disable-static --disable-debuginfod",
         ),

    dict(name="bison", version="3.8.2",
         summary="GNU 语法分析器生成器",
         homepage="https://www.gnu.org/software/bison",
         license="GPL-3.0-or-later",
         depends=["m4"],
         configure="--prefix=/usr --docdir=/usr/share/doc/bison",
         ),

    dict(name="flex", version="2.6.4",
         summary="词法分析器生成器",
         homepage="https://github.com/westes/flex", license="BSD-2-Clause",
         depends=["m4", "bison"],
         configure="--prefix=/usr --docdir=/usr/share/doc/flex",
         ),

    dict(name="m4", version="1.4.20",
         summary="GNU 宏处理器（autotools 依赖）",
         homepage="https://www.gnu.org/software/m4", license="GPL-3.0-or-later",
         configure="--prefix=/usr",
         ),

    dict(name="pkgconf", version="2.4.0",
         summary="编译期依赖查询工具（pkg-config 的替代实现）",
         homepage="https://gitea.treehouse.systems/ariadne/pkgconf",
         license="ISC",
         provides=["pkg-config", "pkgconfig"],
         configure="--prefix=/usr --with-pkg-config-dir=/usr/lib/pkgconfig",
         ),

    dict(name="mpfr", version="4.2.2",
         summary="多精度浮点运算库（gcc/gawk 依赖）",
         homepage="https://www.mpfr.org", license="LGPL-3.0-or-later",
         depends=["gmp"], provides=["libmpfr.so.6"],
         configure="--prefix=/usr --enable-shared --disable-static",
         ),

    dict(name="gmp", version="6.3.0",
         summary="任意精度算术库",
         homepage="https://gmplib.org", license="LGPL-3.0-or-later OR GPL-2.0-or-later",
         provides=["libgmp.so.10"],
         configure="--prefix=/usr --enable-cxx --disable-static",
         ),

    dict(name="openssh", version="10.0p1",
         summary="SSH 客户端与服务端",
         homepage="https://www.openssh.com", license="BSD-2-Clause AND MIT",
         depends=["openssl", "zlib"],
         configure="--prefix=/usr --sysconfdir=/etc/ssh --with-md5-passwords "
                   "--with-privsep-path=/var/lib/sshd",
         ),

    dict(name="ca-certificates", version="20250415",
         summary="系统可信 CA 证书集",
         homepage="https://curl.se/docs/caextract.html", license="MPL-2.0",
         configure=None,
         build=["true"],
         package=["mkdir -p {destdir}/etc/ssl/certs",
                  "true  # 证书数据由独立的证书包提供"]),

    dict(name="tzdata", version="2025b",
         summary="时区数据库",
         homepage="https://www.iana.org/time-zones", license="PublicDomain",
         configure=None,
         build=["true"],
         package=["make DESTDIR={destdir} install"]),

    dict(name="less", version="668",
         summary="文本文件分页查看器",
         homepage="https://greenwoodsoftware.com/less", license="GPL-3.0-or-later",
         depends=["ncurses", "pcre2"],
         configure="--prefix=/usr --sysconfdir=/etc",
         ),

    dict(name="which", version="2.23",
         summary="定位可执行文件位置",
         homepage="https://savannah.gnu.org/projects/which",
         license="GPL-3.0-or-later",
         configure="--prefix=/usr",
         ),

    dict(name="inetutils", version="2.6",
         summary="基础网络客户端与服务端（ftp telnet）",
         homepage="https://www.gnu.org/software/inetutils",
         license="GPL-3.0-or-later",
         depends=["readline", "ncurses"],
         configure="--prefix=/usr --disable-servers",
         ),

    dict(name="man-db", version="2.13.1",
         summary="手册页浏览工具（man）",
         homepage="https://www.nongnu.org/man-db",
         license="GPL-3.0-or-later",
         depends=["zlib", "gdbm", "libpipeline"],
         configure="--prefix=/usr --disable-setuid --disable-cache-owner",
         ),

    dict(name="libpipeline", version="1.5.8",
         summary="子进程管道管理库（man-db 依赖）",
         homepage="https://gitlab.freedesktop.org/bwidawsk/libpipeline",
         license="GPL-3.0-or-later",
         configure="--prefix=/usr",
         ),
]

TEMPLATE = '''"""{name} —— {summary}

{homepage}
许可证：{license}
"""

name = "{name}"
version = "{version}"
release = 1
summary = "{summary}"
homepage = "{homepage}"
license = "{license}"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums {name}
source = ["{source}"]
sha256 = []
checksum_pending = True

depends = {depends}
makedepends = {makedepends}
provides = {provides}

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
{build}


def package(ctx):
{package}
'''


def _fmt_list(v) -> str:
    return json.dumps(v or [], ensure_ascii=False)


def _fmt_cmds(cmds, configure: str | None, pkg: bool) -> str:
    if cmds:
        lines = [f'    ctx.run("{c}")' for c in cmds]
        return "\n".join(lines)
    if configure is not None:
        if pkg:
            return ('    ctx.run("make DESTDIR={} install".format(ctx.destdir))')
        return (f'    ctx.run("./configure {configure}")\n'
                f'    ctx.run("make")')
    return '    ctx.run("make")\n    ctx.run("make DESTDIR={} install"'.format(
        "") + '.format(ctx.destdir))' if pkg else '    ctx.run("make")'


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    written = []
    for p in PKGS:
        name = p["name"]
        src = p.get("source") or (
            f"https://ftp.gnu.org/gnu/{name}/{name}-{p['version']}.tar.gz")
        if pkg := p.get("configure"):
            pass
        build = _fmt_cmds(p.get("build"), p.get("configure"), False)
        package = _fmt_cmds(p.get("package"), p.get("configure"), True)
        text = TEMPLATE.format(
            name=name, version=p["version"], summary=p["summary"],
            homepage=p.get("homepage", ""), license=p.get("license", ""),
            source=src,
            depends=_fmt_list(p.get("depends")),
            makedepends=_fmt_list(p.get("makedepends")),
            provides=_fmt_list(p.get("provides")),
            build=build, package=package)
        out = OUT / f"{name}.py"
        out.write_text(text)
        written.append(name)
    print(f"已生成 {len(written)} 个配方")
    print(" ".join(sorted(written)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
