"""qydesktop —— 启元桌面 shell（GTK3 单窗口桌面：顶栏 + Dock + 壁纸桌面）

源码：recipes/qydesktop.c、recipes/qytheme.css、recipes/weston.ini（随仓库自带）
许可证：MIT
"""

name = "qydesktop"
version = "0.1.0"
release = 113
summary = "启元桌面 shell（GTK3 单窗口 + 主题）"
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
RECIPE_EDIT_C = Path(__file__).parent / "qyedit.c"
RECIPE_MON_C = Path(__file__).parent / "qymon.c"
RECIPE_VIEW_C = Path(__file__).parent / "qyview.c"
RECIPE_CTL_C = Path(__file__).parent / "qyctl.c"
RECIPE_ARC_C = Path(__file__).parent / "qyarc.c"
RECIPE_STORE_C = Path(__file__).parent / "qystore.c"
RECIPE_INST_C = Path(__file__).parent / "qypkg-inst.c"
RECIPE_NET_C = Path(__file__).parent / "qynet.c"


def build(ctx):
    shutil.copy(RECIPE_C, Path(ctx.srcdir) / "qydesktop.c")
    shutil.copy(RECIPE_FILES_C, Path(ctx.srcdir) / "qyfiles.c")
    shutil.copy(RECIPE_SETTINGS_C, Path(ctx.srcdir) / "qysettings.c")
    shutil.copy(RECIPE_APPMENU_C, Path(ctx.srcdir) / "qyappmenu.c")
    shutil.copy(Path(__file__).parent / "qyboot.c", Path(ctx.srcdir) / "qyboot.c")
    shutil.copy(RECIPE_EDIT_C, Path(ctx.srcdir) / "qyedit.c")
    shutil.copy(RECIPE_MON_C, Path(ctx.srcdir) / "qymon.c")
    shutil.copy(RECIPE_VIEW_C, Path(ctx.srcdir) / "qyview.c")
    shutil.copy(RECIPE_CTL_C, Path(ctx.srcdir) / "qyctl.c")
    shutil.copy(RECIPE_ARC_C, Path(ctx.srcdir) / "qyarc.c")
    shutil.copy(RECIPE_NET_C, Path(ctx.srcdir) / "qynet.c")
    shutil.copy(RECIPE_STORE_C, Path(ctx.srcdir) / "qystore.c")
    shutil.copy(RECIPE_INST_C, Path(ctx.srcdir) / "qypkg-inst.c")
    shutil.copy(Path(__file__).parent / "qystore.desktop", Path(ctx.srcdir) / "qystore.desktop")
    shutil.copy(Path(__file__).parent / "qynet.unit", Path(ctx.srcdir) / "qynet.unit")
    shutil.copy(Path(__file__).parent / "start-qynet.sh", Path(ctx.srcdir) / "start-qynet.sh")
    # v1.9.6: 补入此前只在 sysroot 手工存在的脚本/单元源码，使构建可复现
    shutil.copy(Path(__file__).parent / "start-qydesktop.sh", Path(ctx.srcdir) / "start-qydesktop.sh")
    shutil.copy(Path(__file__).parent / "start-sshd.sh", Path(ctx.srcdir) / "start-sshd.sh")
    shutil.copy(Path(__file__).parent / "start-udevd.sh", Path(ctx.srcdir) / "start-udevd.sh")
    shutil.copy(Path(__file__).parent / "start-weston.sh", Path(ctx.srcdir) / "start-weston.sh")
    shutil.copy(Path(__file__).parent / "qyselftest.sh", Path(ctx.srcdir) / "qyselftest.sh")
    shutil.copy(Path(__file__).parent / "sshd.unit", Path(ctx.srcdir) / "sshd.unit")
    shutil.copy(Path(__file__).parent / "udevd.unit", Path(ctx.srcdir) / "udevd.unit")
    shutil.copy(Path(__file__).parent / "weston.unit", Path(ctx.srcdir) / "weston.unit")
    shutil.copy(Path(__file__).parent / "zz-selftest.unit", Path(ctx.srcdir) / "zz-selftest.unit")
    shutil.copy(Path(__file__).parent / "qydesktop.unit", Path(ctx.srcdir) / "qydesktop.unit")
    for _f in ("qyl10n.c", "qyl10n.h", "qysetup.c", "qysudo.c", "qyusers.c", "qywelcome.c",
               "qyuseradd.sh", "qyinstall.sh", "qyinitpw.sh", "qyboot.unit", "qysudoers"):
        shutil.copy(Path(__file__).parent / _f, Path(ctx.srcdir) / _f)
    # v2.0: 桌面主题 CSS + weston 配置（panel 禁用，顶栏由 qydesktop 提供）
    shutil.copy(Path(__file__).parent / "qytheme.css", Path(ctx.srcdir) / "qytheme.css")
    shutil.copy(Path(__file__).parent / "qytheme.c", Path(ctx.srcdir) / "qytheme.c")
    shutil.copy(Path(__file__).parent / "qytheme.h", Path(ctx.srcdir) / "qytheme.h")
    shutil.copy(Path(__file__).parent / "weston.ini", Path(ctx.srcdir) / "weston.ini")
    ctx.run(
        "export PATH={0}/usr/bin:$PATH; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; "
        "export PKG_CONFIG_SYSROOT_DIR={0}; export PKG_CONFIG_LIBDIR={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; "
        "export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; "
        "gcc qydesktop.c qytheme.c qyl10n.c -o qydesktop $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qyfiles.c qytheme.c qyl10n.c -o qyfiles $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qysettings.c qytheme.c qyl10n.c -o qysettings $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qyusers.c qytheme.c qyl10n.c -o qyusers $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qywelcome.c qytheme.c qyl10n.c -o qywelcome $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qysetup.c qytheme.c qyl10n.c -o qysetup $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qysudo.c -o qysudo -O2 -lcrypt && "
        "gcc qyappmenu.c qytheme.c qyl10n.c -o qyappmenu $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qyedit.c qytheme.c qyl10n.c -o qyedit $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qymon.c qytheme.c qyl10n.c -o qymon $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qyview.c qytheme.c qyl10n.c -o qyview $(pkg-config --cflags --libs gtk+-3.0 gdk-pixbuf-2.0) -O2 -ljpeg -lmount && "
        "gcc qyctl.c -o qyctl -O2 -Wall && "
        "gcc qyarc.c qytheme.c qyl10n.c -o qyarc $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qystore.c qytheme.c qyl10n.c -o qystore $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qynet.c qytheme.c qyl10n.c -o qynet $(pkg-config --cflags --libs gtk+-3.0) -O2 -ljpeg -lmount && "
        "gcc qypkg-inst.c -o qypkg-inst -O2".format(ctx.sysroot)
    )


def package(ctx):
    ctx.run("mkdir -p {}/usr/bin".format(ctx.destdir))
    ctx.run("cp qydesktop {}/usr/bin/qydesktop".format(ctx.destdir))
    ctx.run("cp qyfiles {}/usr/bin/qyfiles".format(ctx.destdir))
    ctx.run("cp qysettings {}/usr/bin/qysettings".format(ctx.destdir))
    ctx.run("cp qyappmenu {}/usr/bin/qyappmenu".format(ctx.destdir))
    ctx.run("cp qyedit {}/usr/bin/qyedit".format(ctx.destdir))
    ctx.run("cp qymon {}/usr/bin/qymon".format(ctx.destdir))
    ctx.run("cp qyview {}/usr/bin/qyview".format(ctx.destdir))
    ctx.run("cp qyctl {}/usr/bin/qyctl".format(ctx.destdir))
    ctx.run("cp qyarc {}/usr/bin/qyarc".format(ctx.destdir))
    ctx.run("cp qystore {}/usr/bin/qystore".format(ctx.destdir))
    ctx.run("cp qynet {}/usr/bin/qynet".format(ctx.destdir))
    ctx.run("cp qypkg-inst {}/usr/bin/qypkg-inst".format(ctx.destdir))
    ctx.run("cp qysetup {}/usr/bin/qysetup".format(ctx.destdir))
    ctx.run("cp qyuseradd.sh {}/usr/bin/qyuseradd && chmod +x {}/usr/bin/qyuseradd".format(ctx.destdir, ctx.destdir))
    ctx.run("cp qyusers {}/usr/bin/qyusers".format(ctx.destdir))
    ctx.run("cp qyinstall.sh {}/usr/bin/qyinstall && chmod +x {}/usr/bin/qyinstall".format(ctx.destdir, ctx.destdir))
    ctx.run("cp qysudo {}/usr/bin/qysudo && chmod 4755 {}/usr/bin/qysudo".format(ctx.destdir, ctx.destdir, ctx.destdir))
    ctx.install_file("qysudoers", "etc/qysudoers")
    ctx.run("mkdir -p {}/etc/qyinit.d && cp qyinitpw.sh {}/etc/qyinit.d/40-initpw && chmod +x {}/etc/qyinit.d/40-initpw".format(ctx.destdir, ctx.destdir, ctx.destdir))
    ctx.run("gcc qyboot.c -o {}/usr/bin/qyboot -O2 && chmod 755 {}/usr/bin/qyboot".format(ctx.destdir, ctx.destdir))
    ctx.install_file("qyboot.unit", "etc/qyinit.d/qyboot.unit")
    ctx.run("cp qywelcome {}/usr/bin/qywelcome".format(ctx.destdir))
    # 网络自启单元 (busybox udhcpc DHCP)：
    ctx.run("mkdir -p {}/etc/qyinit.d".format(ctx.destdir))
    ctx.install_file("qynet.unit", "etc/qyinit.d/qynet.unit")
    ctx.run("cp start-qynet.sh {}/usr/bin/start-qynet.sh".format(ctx.destdir))
    ctx.run("chmod 0755 {}/usr/bin/start-qynet.sh".format(ctx.destdir))
    # 软件中心 desktop entry (v1.9.5):
    ctx.run("mkdir -p {}/usr/share/applications".format(ctx.destdir))
    ctx.install_file("qystore.desktop", "usr/share/applications/qystore.desktop")
    # v2.0: 桌面主题 CSS（qydesktop 启动时加载）+ weston 配置
    ctx.run("mkdir -p {}/usr/share/themes/qiyuan/gtk-3.0".format(ctx.destdir))
    ctx.install_file("qytheme.css", "usr/share/themes/qiyuan/gtk-3.0/gtk.css")
    ctx.run("mkdir -p {}/etc/xdg/weston".format(ctx.destdir))
    ctx.install_file("weston.ini", "etc/xdg/weston/weston.ini")
    # v2.x: 桌面版本文件（qysettings 关于页显示）
    ctx.run("mkdir -p {}/usr/share".format(ctx.destdir))
    ctx.run(f"printf '{version}-{release}' > {ctx.destdir}/usr/share/qydesktop-version")
    # v1.9.6: 补入此前只在 sysroot 手工存在的启动脚本与自启单元（源码已入库）
    for _s in ("start-qydesktop.sh", "start-sshd.sh", "start-udevd.sh",
               "start-weston.sh", "qyselftest.sh"):
        ctx.run("cp {0} {1}/usr/bin/{0} && chmod 0755 {1}/usr/bin/{0}".format(_s, ctx.destdir))
    for _u in ("qydesktop.unit", "sshd.unit", "udevd.unit", "weston.unit",
               "zz-selftest.unit"):
        ctx.install_file(_u, "etc/qyinit.d/" + _u)