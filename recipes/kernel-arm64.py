"""Linux 内核 —— 7.2.x 稳定版（aarch64/arm64，QEMU virt 平台基线）

手机/Termux proot 不需要内核，但 aarch64 ISO 与 qemu-system-aarch64 实机验证需要。
许可证：GPL-2.0
"""

name = "kernel-arm64"
version = "7.2.9"
release = 1
summary = "Linux 内核（澜岫基线，arm64）"
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
    # Kbuild 只认 CROSS_COMPILE，不看 CC（宿主教训）
    ctx.env("ARCH", "arm64")
    ctx.run("make defconfig")
    # QEMU virt 平台 + live 介质所需（arm64 上 VESA 不存在，fb/drm 保留 virtio-gpu）
    for opt in ("CONFIG_SQUASHFS=y", "CONFIG_OVERLAY_FS=y", "CONFIG_EXT4_FS=y",
                "CONFIG_ISO9660_FS=y", "CONFIG_BLK_DEV_LOOP=y",
                "CONFIG_VIRTIO_PCI=y", "CONFIG_VIRTIO_BLK=y",
                "CONFIG_VIRTIO_NET=y", "CONFIG_SERIAL_AMBA_PL011=y",
                "CONFIG_SERIAL_AMBA_PL011_CONSOLE=y", "CONFIG_DEVTMPFS=y",
                "CONFIG_DEVTMPFS_MOUNT=y", "CONFIG_TMPFS=y",
                "CONFIG_PROC_FS=y", "CONFIG_SYSFS=y", "CONFIG_UNIX=y",
                "CONFIG_INOTIFY_USER=y", "CONFIG_EPOLL=y", "CONFIG_FUSE_FS=y",
                "CONFIG_DRM=y", "CONFIG_DRM_VIRTIO_GPU=y",
                "CONFIG_FB=y", "CONFIG_FRAMEBUFFER_CONSOLE=y",
                "CONFIG_USB_SUPPORT=y", "CONFIG_USB_HID=y",
                "CONFIG_INPUT_EVDEV=y",
                "CONFIG_ZSTD_DECOMPRESS=y", "CONFIG_SQUASHFS_ZSTD=y"):
        key = opt.split("=")[0]
        ctx.run("./scripts/config -e {}".format(key))
    # x86 专属选项在 arm64 里不存在，olddefconfig 会自动丢弃
    ctx.run("make olddefconfig")
    ctx.run("make -j2 Image modules")


def package(ctx):
    ctx.run("mkdir -p {}/boot".format(ctx.destdir))
    ctx.run("cp arch/arm64/boot/Image {}/boot/vmlinuz-7.2.9-arm64".format(ctx.destdir))
    ctx.run("cp System.map {}/boot/System.map-7.2.9-arm64".format(ctx.destdir))
    ctx.run("cp .config {}/boot/config-7.2.9-arm64".format(ctx.destdir))
