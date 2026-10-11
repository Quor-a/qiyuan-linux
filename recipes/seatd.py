"""seatd —— 最小化 seat 与会话管理守护进程（无 systemd 环境的图形会话前提）

https://git.sr.ht/~kennylevinsen/seatd
许可证：MIT
"""

name = "seatd"
version = "0.9.1"
release = 1
summary = "最小化 seat 与会话管理守护进程"
homepage = "https://git.sr.ht/~kennylevinsen/seatd"
license = "MIT"

source = ["https://github.com/kennylevinsen/seatd/archive/refs/tags/0.9.1.tar.gz"]
sha256 = ["819979c922a0be258aed133d93920bce6a3d3565a60588d6d372ce9db2712cd3"]

depends = []
makedepends = ["meson", "ninja"]
provides = ["libseat"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr "
            "-Dlibseat-seatd=enabled -Dlibseat-logind=disabled "
            "-Dlibseat-builtin=disabled -Dserver=enabled" + x)


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
    # 运行前置：qyinit 服务单元，由 qyinit 按依赖启动
    unit = ctx.destdir / "etc/qyinit.d/seatd.unit"
    unit.parent.mkdir(parents=True, exist_ok=True)
    unit.write_text(
        "[Unit]\n"
        "Description=Seat management daemon\n"
        "After=dbus\n"
        "\n"
        "[Service]\n"
        "ExecStart=/usr/bin/seatd -g video\n"
        "Restart=on-failure\n")
