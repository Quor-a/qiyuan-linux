"""vim —— Vim 文本编辑器


许可证：Vim
"""

name = "vim"
version = "9.1.1234"
release = 1
summary = "Vim 文本编辑器"
homepage = ""
license = "Vim"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums vim
source = ["https://github.com/vim/vim/archive/refs/tags/v9.1.1234.tar.gz"]
sha256 = ["30270dcaf226a7672387992705287bab4f0142941eb33721050f7cc2f7405df8"]
checksum_pending = True

depends = ["ncurses", "acl", "lua"]
makedepends = ["ncurses", "acl", "lua"]
provides = ["editor", "vi"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    import os
    inc = os.path.join(str(ctx.sysroot), "usr/include")
    lib = os.path.join(str(ctx.sysroot), "usr/lib")
    ctx.run("./configure --prefix=/usr --enable-multibyte --with-features=huge "
            "--disable-gui --disable-nls --with-tlib=tinfo --disable-selinux "
            "CPPFLAGS=-I{inc} LDFLAGS='-L{lib} -Wl,-rpath-link,{lib}'".format(inc=inc, lib=lib))
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
