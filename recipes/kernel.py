"""Linux 内核 —— 7.2.x 稳定版（x86_64，内置图形/网络/文件系统驱动）

许可证：GPL-2.0
"""

name = "kernel"
version = "7.2.9"
release = 1
summary = "Linux 内核（启元基线配置）"
homepage = ""
license = "GPL-2.0"

source = ["https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.9.tar.xz"]
sha256 = ["b4c5dfbe51a364a6c7f03869200f88c8e1f77403539005f14b7fc6bc91b8d8ba"]

depends = []
makedepends = ["bison", "flex", "libelf"]
provides = ["kernel", "vmlinuz"]

requires_build_machine = True
network = False
compression = "gz"

config_dir = "kernel-config"


def build(ctx):
    # 内核是自包含(freestanding)构建：sysroot 的用户态头会污染
    # 内核与 objtool（宿主工具）的编译，必须清掉注入路径。
    ctx.env("CPATH", "")
    ctx.env("CFLAGS", "")
    ctx.env("CXXFLAGS", "")
    ctx.env("LIBRARY_PATH", "")
    ctx.env("LDFLAGS", "")
    ctx.env("PKG_CONFIG_PATH", "")
    ctx.env("PKG_CONFIG_SYSROOT_DIR", "")
    ctx.run("make defconfig")
    # 驱动扩展片段：有线网/WiFi/蓝牙/USB 全栈（kernel-config/*.fragment）
    # 片段随仓库分发，宿主机直接读取（不进沙箱），逐条交给 scripts/config。
    from pathlib import Path as _P
    frag_dir = _P(__file__).resolve().parent.parent / "kernel-config"
    import glob
    for frag in sorted(glob.glob(str(frag_dir) + "/*.fragment")):
        for line in open(frag):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            if val == "m":
                ctx.run("./scripts/config -m {}".format(key))
            elif val.startswith('"'):
                ctx.run("./scripts/config --set-str {} {}".format(key, val.strip('"')))
            else:
                ctx.run("./scripts/config -e {}".format(key))
    # 发行版基线：live 介质与真实装机都需要这些
    for opt in ("CONFIG_SQUASHFS=y", "CONFIG_OVERLAY_FS=y", "CONFIG_EXT4_FS=y",
                "CONFIG_ISO9660_FS=y", "CONFIG_BLK_DEV_LOOP=y",
                "CONFIG_VIRTIO_PCI=y", "CONFIG_VIRTIO_BLK=y",
                "CONFIG_VIRTIO_NET=y", "CONFIG_SERIAL_8250=y",
                "CONFIG_SERIAL_8250_CONSOLE=y", "CONFIG_DEVTMPFS=y",
                "CONFIG_DEVTMPFS_MOUNT=y", "CONFIG_TMPFS=y",
                "CONFIG_PROC_FS=y", "CONFIG_SYSFS=y", "CONFIG_UNIX=y",
                "CONFIG_INOTIFY_USER=y", "CONFIG_EPOLL=y", "CONFIG_FUSE_FS=y",
                "CONFIG_DRM=y", "CONFIG_DRM_VIRTIO_GPU=y",
                "CONFIG_FB=y", "CONFIG_FB_VESA=y", "CONFIG_FRAMEBUFFER_CONSOLE=y",
                "CONFIG_USB_SUPPORT=y", "CONFIG_USB_HID=y",
                "CONFIG_INPUT_EVDEV=y",
                "CONFIG_SOUND=y", "CONFIG_SND=y", "CONFIG_SND_PCI=y",
                "CONFIG_SND_HDA_INTEL=y", "CONFIG_SND_HDA_GENERIC=y",
                "CONFIG_ZSTD_DECOMPRESS=y", "CONFIG_SQUASHFS_ZSTD=y"):
        ctx.run("./scripts/config -e {}".format(opt.split("=")[0]))
    ctx.run("make olddefconfig")
    ctx.run("make -j2 bzImage modules")


def package(ctx):
    ctx.run("mkdir -p {}/boot".format(ctx.destdir))
    ctx.run("cp arch/x86/boot/bzImage {}/boot/vmlinuz-7.2.9".format(ctx.destdir))
    ctx.run("cp System.map {}/boot/System.map-7.2.9".format(ctx.destdir))
    ctx.run("cp .config {}/boot/config-7.2.9".format(ctx.destdir))
    ctx.run("make INSTALL_MOD_PATH={} modules_install".format(ctx.destdir))
