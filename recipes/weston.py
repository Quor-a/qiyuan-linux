"""weston —— Wayland 参考合成器（轻量桌面图形会话）

https://gitlab.freedesktop.org/wayland/weston
许可证：MIT
"""

name = "weston"
version = "14.0.2"
release = 1
summary = "Wayland 参考合成器（轻量桌面图形会话）"
homepage = "https://gitlab.freedesktop.org/wayland/weston"
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums weston
source = ["https://gitlab.freedesktop.org/wayland/weston/-/archive/14.0.2/weston-14.0.2.tar.gz"]
sha256 = ["633f4e0f232ad150300c95ffcbc646fedf1349487bf389dbd2045fa69013d6e2"]

depends = ["wayland", "libxkbcommon", "cairo", "jpeg-turbo", "pango",
           "libdrm", "mesa", "seatd", "libinput", "dbus", "pixman"]
makedepends = ["meson", "ninja", "wayland-protocols", "wayland", "libxkbcommon", "cairo", "jpeg-turbo", "pango", "libdrm", "mesa", "seatd", "libinput", "dbus", "pixman", "hwdata"]
provides = ["compositor"]

requires_build_machine = True
network = False
compression = "gz"


from pathlib import Path


def build(ctx):
    # 启元补丁: 顶栏时钟支持 clock-format-string (自定义 strftime, 用于中文日期)
    import shutil as _sh
    _sh.copy(Path(__file__).parent.parent / "qypatches" / "patch-weston-clock.py", Path(ctx.srcdir) / "patch-weston-clock.py")
    ctx.run("python3 patch-weston-clock.py")
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr "
            "-Dbackend-drm=true -Dbackend-headless=true -Dbackend-drm-screencast-vaapi=false -Dbackend-pipewire=false -Dbackend-rdp=false "
            "-Dpipewire=false -Dremoting=false -Dsystemd=false -Dbackend-vnc=false -Dcolor-management-lcms=false "
            "-Dxwayland=false -Dshell-desktop=true -Dshell-fullscreen=true "
            "-Dimage-webp=false -Dimage-jpeg=true -Ddemo-clients=false "
            "-Dsimple-clients= -Dresize-pool=false -Dtests=false "
            "-Dbackend-default=drm")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
