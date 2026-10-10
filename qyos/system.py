"""系统组装：把一堆包变成一棵能启动的树。

单个包安装正确不等于系统能开机。这里负责最后一公里：

    assemble()  按正确顺序装一组包 → 建骨架 → 建设备节点 → 落清单
    check()     可启动性检查（init 在不在、/usr 合并生效没、动态库缺不缺）
    manifest()  生成这棵树的完整清单，用于比对与审计

装机流程和镜像制作都建立在这上面。
"""
from __future__ import annotations

import json
import time
from pathlib import Path

from . import pkgmgr as PM
from . import rootfs
from . import util


def assemble(root: Path, packages: list, repo_dir: Path,
             pubkey=None, allow_unsigned: bool = False,
             make_devnodes: bool = True, version: str = "0.1",
             arch: str | None = None) -> dict:
    """组装一个可启动的根文件系统。

    顺序很重要：filesystem 必须先装（搭骨架），其余按依赖来。
    arch 非 None 时组装异架构 rootfs（如 aarch64，供安卓 Termux proot）。
    """
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    util.log("ok", f"组装根文件系统到 {root}")

    mgr = PM.Manager(root, repo_dir, pubkey, allow_unsigned=allow_unsigned,
                     arch=arch)

    # 1. 先装骨架包（没有它，/etc /usr 这些目录都不存在）
    have_fs = "filesystem" in mgr.db.installed()
    try:
        fs_entry = mgr.available("filesystem")
    except Exception:
        fs_entry = None

    steps = []
    if fs_entry and not have_fs:
        util.log("step", "安装根目录骨架")
        mgr.install(["filesystem"])
        steps.append("filesystem")
    elif fs_entry is None:
        util.log("warn", "仓库里没有 filesystem 包，改用内置骨架")
        touched = rootfs.create_skeleton(root, version=version)
        steps.append(f"内置骨架（{len(touched)} 项）")
    else:
        steps.append("filesystem 已存在")

    # 2. 装目标包
    rest = [p for p in packages if p != "filesystem"]
    if rest:
        util.log("step", "安装软件包: " + " ".join(rest))
        mgr.install(rest)

    # 3. 设备节点（有权限时创建；容器/无权限环境跳过）
    if make_devnodes:
        made = rootfs.make_devnodes(root)
        if made:
            util.log("ok", f"创建 {len(made)} 个设备节点")
        steps.append(f"设备节点 {len(made)} 个")

    # 4. 可启动性检查
    check = rootfs.boot_check(root)
    for e in check["error"]:
        util.log("err", e)
    for w in check["warn"]:
        util.log("warn", w)
    util.log("ok", f"可启动性检查：通过 {len(check['ok'])} 项，"
                   f"警告 {len(check['warn'])} 项，致命 {len(check['error'])} 项")

    result = {"root": str(root), "steps": steps, "check": check,
              "packages": sorted(mgr.db.installed()),
              "bootable": not check["error"]}
    util.atomic_write(root / "var" / "lib" / "qypkg" / "assembly.json",
                      json.dumps(result, ensure_ascii=False, indent=1).encode())
    return result


def manifest(root: Path, out_path: Path | None = None) -> dict:
    """生成根目录的完整清单：每个文件属于哪个包、哈希多少。

    用于比对两台机器装出来是否一致，也是装机后自检的依据。
    """
    root = Path(root)
    db = PM.DB(root)
    files = []
    for name in sorted(db.installed()):
        for f in db.files_of(name):
            files.append({"pkg": name, "path": f["path"],
                          "sha256": f["sha256"], "size": f["size"],
                          "type": f["type"]})
    data = {"generated": int(time.time()), "root": str(root),
            "packages": {n: {"version": r["version"], "release": r["release"]}
                         for n, r in db.installed().items()},
            "file_count": len(files), "files": files}
    if out_path:
        util.atomic_write(Path(out_path),
                          json.dumps(data, ensure_ascii=False, indent=0).encode())
        util.log("ok", f"清单已写入 {out_path}（{len(files)} 个文件）")
    return data


def diff_manifest(a: dict, b: dict) -> dict:
    """比对两份清单，找出差异。装机一致性验证用。"""
    fa = {f["path"]: f for f in a["files"]}
    fb = {f["path"]: f for f in b["files"]}
    only_a = sorted(set(fa) - set(fb))
    only_b = sorted(set(fb) - set(fa))
    changed = sorted(p for p in set(fa) & set(fb)
                     if fa[p]["sha256"] != fb[p]["sha256"])
    return {"only_in_first": only_a, "only_in_second": only_b,
            "changed": changed, "identical": not (only_a or only_b or changed)}
