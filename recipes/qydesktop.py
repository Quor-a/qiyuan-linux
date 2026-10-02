"""qydesktop —— 启元桌面 shell（GTK3 顶栏 + 桌面窗口）

源码：recipes/qydesktop.c（随仓库自带，无外部下载）
许可证：MIT
"""

name = "qydesktop"
version = "0.1.0"
release = 1
summary = "启元桌面 shell（GTK3）"
license = "MIT"

source = []
sha256 = []

depends = ["gtk3", "glib"]
makedepends = ["gtk3"]

requires_build_machine = True
network = False
compression = "xz"

import shutil
from pathlib import Path

RECIPE_C = Path(__file__).parent / "qydesktop.c"
RECIPE_FILES_C = Path(__file__).parent / "qyfiles.c"
RECIPE_SETTINGS_C = Path(__file__).parent / "qysettings.c"
RECIPE_APPMENU_C = Path(__file__).parent / "qyappmenu.c"


def build(ctx):
    shutil.copy(RECIPE_C, Path(ctx.srcdir) / "qydesktop.c")
    shutil.copy(RECIPE_FILES_C, Path(ctx.srcdir) / "qyfiles.c")
    shutil.copy(RECIPE_SETTINGS_C, Path(ctx.srcdir) / "qysettings.c")
    shutil.copy(RECIPE_APPMENU_C, Path(ctx.srcdir) / "qyappmenu.c")
    ctx.run(
        "export PATH={0}/usr/bin:$PATH; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; "
        "export PKG_CONFIG_SYSROOT_DIR={0}; export PKG_CONFIG_LIBDIR={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; "
        "export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; "
        "gcc qydesktop.c -o qydesktop $(pkg-config --cflags --libs gtk+-3.0) -O2 && "
        "gcc qyfiles.c -o qyfiles $(pkg-config --cflags --libs gtk+-3.0) -O2 && "
        "gcc qysettings.c -o qysettings $(pkg-config --cflags --libs gtk+-3.0) -O2 && "
        "gcc qyappmenu.c -o qyappmenu $(pkg-config --cflags --libs gtk+-3.0) -O2".format(ctx.sysroot)
    )


def package(ctx):
    ctx.run("mkdir -p {}/usr/bin".format(ctx.destdir))
    ctx.run("cp qydesktop {}/usr/bin/qydesktop".format(ctx.destdir))
    ctx.run("cp qyfiles {}/usr/bin/qyfiles".format(ctx.destdir))
    ctx.run("cp qysettings {}/usr/bin/qysettings".format(ctx.destdir))
    ctx.run("cp qyappmenu {}/usr/bin/qyappmenu".format(ctx.destdir))
