"""filesystem —— 根目录骨架与基础配置文件包。

发行版不是一堆包的堆叠，是一棵有约定的目录树。这个包提供：
  * FHS 目录骨架（/bin /sbin /lib 指向 /usr 的合并布局）
  * 基础 /etc：os-release、passwd、group、hosts、fstab、profile
  * 设备节点清单（真正创建由启动时做）

它必须最先安装：别的包往里放文件，它负责把架子搭起来。
"""

name = "filesystem"
version = "0.2.0"
release = 1
summary = "根目录骨架与基础配置文件"

# 这些是管理员会改的文件。升级时不加保护地覆盖，等于每次升级
# 都把用户改过的 fstab、hosts、profile 冲掉。
config_files = [
    "etc/os-release",
    "etc/fstab",
    "etc/hosts",
    "etc/profile",
    "etc/passwd",
    "etc/group",
]
description = "FHS 目录结构、/usr 合并布局、基础 /etc 文件与设备节点清单。"
license = "MIT"

source = []
sha256 = []

depends = []
makedepends = []

network = False
compression = "gz"


def build(ctx):
    # 没有源码要编：内容由 package() 直接生成
    pass


def package(ctx):
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(ctx.recipe.path).resolve().parent.parent))
    from qyos import rootfs

    touched = rootfs.create_skeleton(ctx.destdir, version=ctx.version)
    ctx.log_skipped = True
    # 记录这个包到底放了什么，便于审计
    files = ctx.destdir / "usr/share/doc/filesystem/skeleton.txt"
    files.parent.mkdir(parents=True, exist_ok=True)
    files.write_text("本包创建的目录与文件（相对根）：\n\n"
                     + "\n".join(sorted(touched)) + "\n")

    # 设备节点清单（装机时据此 mknod）
    nodes = ctx.destdir / "usr/share/doc/filesystem/devnodes.txt"
    lines = ["# 路径 类型 主设备号 次设备号 权限"]
    for n in rootfs.devnode_list():
        lines.append("{} {} {} {} {}".format(
            n["path"], n["type"], n["major"], n["minor"], oct(n["mode"])))
    nodes.write_text("\n".join(lines) + "\n")
