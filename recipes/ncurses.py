"""ncurses —— 终端处理库（供 bash、less、vi 等使用）

https://invisible-island.net/ncurses
许可证：MIT
"""

name = "ncurses"
version = "6.5"
release = 1
summary = "终端处理库（供 bash、less、vi 等使用）"
homepage = "https://invisible-island.net/ncurses"
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums ncurses
source = ["https://mirrors.aliyun.com/gnu/ncurses/ncurses-6.5.tar.gz"]
sha256 = ["136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6"]

depends = []
makedepends = []
provides = ["libncursesw.so.6"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --with-shared --without-debug --enable-widec --with-cxx-shared --with-termlib")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
    # --enable-widec 下 termlib 装出来的是 libtinfow.so.6，但大量上游（gawk、bash、
    # less 等）链接的是非 wide 的 libtinfo.so.6。ldconfig 按 SONAME 建索引，用符号
    # 链接指过去不会被收录，运行期必然报找不到库。这里复制一份并把 SONAME 改成
    # libtinfo.so.6（尾部补 NUL 对齐，C 字符串语义不变），得到真正可被索引的库。
    ctx.run(
        "python3 - {d} <<'PYEOF'\n"
        "import shutil, sys, pathlib\n"
        "d = pathlib.Path(sys.argv[1]) / 'usr/lib'\n"
        "src = next(d.glob('libtinfow.so.6.5*'), None)\n"
        "if src is None:\n"
        "    sys.exit(0)\n"
        "data = bytearray(src.read_bytes())\n"
        "old = b'libtinfow.so.6\\x00'\n"
        "new = b'libtinfo.so.6\\x00\\x00'\n"
        "if old in data and len(new) == len(old):\n"
        "    data = data.replace(old, new)\n"
        "out = d / 'libtinfo.so.6.5'\n"
        "out.write_bytes(bytes(data))\n"
        "for link in ('libtinfo.so.6', 'libtinfo.so'):\n"
        "    p = d / link\n"
        "    if p.is_symlink() or p.exists():\n"
        "        p.unlink()\n"
        "    p.symlink_to(out.name)\n"
        "PYEOF".format(d=ctx.destdir)
    )
