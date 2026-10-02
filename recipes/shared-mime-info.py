"""shared-mime-info —— 共享 MIME 类型数据库

许可证：GPL-2.0-or-later
"""

name = "shared-mime-info"
version = "2.4"
release = 2
summary = "共享 MIME 类型数据库"
license = "GPL-2.0-or-later"

source = ["https://mirror.timeweb.ru/ubuntu/pool/main/s/shared-mime-info/shared-mime-info_2.4.orig.tar.bz2"]
sha256 = ["32dc32ae39ff1c1bf8434dd3b36770b48538a1772bc0298509d034f057005992"]

depends = ["glib", "libxml2"]
makedepends = ["meson", "ninja", "glib", "libxml2"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    S = ctx.sysroot
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run(
        "cd build && export PATH={0}/usr/bin:$PATH; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; "
        "export PKG_CONFIG_SYSROOT_DIR={0}; export PKG_CONFIG_LIBDIR={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; "
        "export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; "
        "meson setup .. --prefix=/usr -Dupdate-mimedb=false".format(S)
    )


def package(ctx):
    S = ctx.sysroot
    ctx.run(
        "cd build && export PATH={0}/usr/bin:$PATH; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; "
        "ninja".format(S)
    )
    ctx.run(
        "cd build && export PATH={0}/usr/bin:$PATH; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; "
        "DESTDIR={1} ninja install".format(S, ctx.destdir)
    )
    # 生成编译版 MIME 数据库（GIO 内容嗅探依赖它；缺了会导致 gdk-pixbuf 无法识别 PNG）
    ctx.run(
        "export PATH={0}/usr/bin:$PATH; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; "
        "{0}/usr/bin/update-mime-database {1}/usr/share/mime".format(S, ctx.destdir)
    )
