"""mesa —— 开源 OpenGL / Vulkan 实现

许可证：MIT AND Apache-2.0 AND SGI-B-2.0
"""

name = "mesa"
version = "24.0.9"
release = 1
summary = "开源 OpenGL / Vulkan 实现"
license = "MIT AND Apache-2.0 AND SGI-B-2.0"

source = ["https://archive.mesa3d.org/mesa-24.0.9.tar.xz"]
sha256 = ["51aa686ca4060e38711a9e8f60c8f1efaa516baf411946ed7f2c265cd582ca4c"]

depends = ["libdrm", "libxcb", "libX11", "libXext", "libXdamage", "libXfixes", "libxkbcommon", "wayland", "zlib", "zstd", "expat", "libelf", "libxshmfence", "libXxf86vm", "libXrender", "libXrandr"]
makedepends = ["meson", "ninja", "bison", "flex", "python", "cmake", "glslang", "libdrm", "libxcb", "libX11", "libXext", "libXdamage", "libXfixes", "libxkbcommon", "wayland", "zlib", "zstd", "expat", "libelf", "libxshmfence", "libXxf86vm", "libXrender", "libXrandr"]
provides = ["libGL.so.1", "libEGL.so.1", "libgbm.so.1"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && LLVMSRCDIR= PKG_CONFIG_PATH=/usr/lib/llvm-18/lib/pkgconfig:$PKG_CONFIG_PATH meson setup .. --prefix=/usr -Dgallium-drivers=swrast -Dvulkan-drivers= -Dgbm=enabled -Dglvnd=false -Dllvm=enabled -Dplatforms=x11,wayland -Ddri3=enabled -Dglx-direct=true -Degl=enabled")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && meson install --destdir {}".format(ctx.destdir))
