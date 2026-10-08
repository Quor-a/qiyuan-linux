"""linux-firmware —— 网卡、无线、显卡固件

https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
许可证：固件各不相同（多为厂商二进制授权）

**这是整套系统里最不能省的包**

没有它，大部分有线网卡、几乎所有无线网卡、AMD/Intel 显卡、
部分 NVMe 在真机上直接不工作。用户装完发现连不上网，
第一反应是"这个系统不行"。

为什么它最容易被漏掉：虚拟机用 virtio 虚拟设备不需要固件，
容器更不需要。所以这个缺失在开发沙盒里永远不会暴露，
只在真机首次装机时爆发——而那时用户已经把硬盘格了。
**任何"在虚拟机里跑通了"的验证都证明不了固件没问题。**

 firmware 不是源码编译出来的，是厂商发布的二进制 blob。
所以这个配方没有 build()，只做"按需要的子集取出并打包"。
全量仓库有几个 GB，装机镜像带不动，必须按需裁剪。

裁剪按设备类别分组：
- core：几乎所有机器都要（CPU 微码、常见有线网卡）
- net：有线网卡
- wifi：无线网卡
- gpu：显卡（AMD/Intel，NVIDIA 开源固件）
- storage：NVMe/SAS 控制器
- 其余（声卡、蓝牙、摄像头、电视卡）按需

装机镜像必须带 core + net + wifi + gpu + storage。
笔记本不带 wifi 就是砖；独显机器不带 gpu 进不了图形界面。
"""
from __future__ import annotations

name = "linux-firmware"
version = "20250613"
release = 1
summary = "网卡/无线/显卡/存储控制器固件"
homepage = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git"
license = "固件各自的厂商授权"

source = ["https://mirror.lzu.edu.cn/kernel/firmware/linux-firmware-20250613.tar.xz"]
sha256 = ["d40743337ca8bf9d2587e220ab30dec6a07b52cc5cb4a4ff8d92be14391a7fde"]
checksum_pending = False

depends = []
makedepends = []
provides = ["firmware"]

# 固件是二进制 blob，不编译；但要真实构建机（仓库几个 GB，按需裁剪）
requires_build_machine = True
network = False
compression = "gz"

# 按类别裁剪。全量带不动，只带真机会用到的
GROUPS = {
    "core": [
        # CPU 微码（20250613: intel 微码在 intel/ 目录）
        "amd-ucode", "intel",
        # 有线网卡固件目录（e1000/igb/ixgbe 上游已平铺为顶层文件，
        # 由 PACKAGE_PREFIXES 抓取）
        "e100", "rtl_nic", "bnx2", "bnx2x", "cxgb3", "cxgb4", "qed",
        "liquidio", "qcom", "sfc", "aacraid",
    ],
    "net": [
        "bnxt", "i40e", "ice", "nfp", "mrvl", "ti-connectivity",
    ],
    "wifi": [
        # 无线固件是笔记本能否联网的唯一决定因素
        "ath10k", "ath11k", "ath12k", "ath9k_htc", "ath6k",
        "brcm", "libertas", "rtlwifi", "rtw88", "rtw89",
        # iwlwifi 20250613 起平铺为顶层 iwlwifi-*.ucode，见 PACKAGE_PREFIXES
    ],
    "gpu": [
        # 不带显卡固件，独显机器进不了图形界面，
        # 核显机器会掉到软件渲染（鼠标都卡）
        "amdgpu", "radeon", "i915", "xe", "nvidia",
    ],
    "bt": [
        # 蓝牙控制器固件：Intel/Broadcom/Realtek/MediaTek USB-UART 适配器
        "intel", "rtl_bt", "mediatek", "qca",
    ],
    "storage": [
        # 部分 NVMe 与 SAS 控制器没有固件直接认不到盘
        "aacraid",
    ],
}

# 上游已把部分驱动固件从目录平铺成顶层文件，按前缀抓取
PACKAGE_PREFIXES = {
    "iwlwifi": "wifi",
    "i915": "gpu",
    "e100": "core",
    "e1000": "core",
    "igb": "core",
    "ixgbe": "core",
    "r8169": "core",
    "tg3": "core",
    "atlantic": "core",
    "bnxt": "net",
    "i40e": "net",
    "ice": "net",
    "ixgbevf": "net",
    "mlxsw": "net",
    "nfp": "net",
    "sfc": "net",
    "thunderx": "net",
    "mt7601u": "bt",
    "ath3k": "bt",
    "ath9k_htc": "wifi",
    "ath6k": "wifi",
    "ath10k": "wifi",
    "ath11k": "wifi",
    "ath12k": "wifi",
}

PACKAGE_GROUPS = ["core", "net", "wifi", "gpu", "storage", "bt"]


def build(ctx):
    # 固件是厂商发布的二进制，没有编译步骤。
    # 这里只做校验：确认源码树里确实有我们声明要取的目录，
    # 缺了就在构建期暴露，而不是等到装机后才发现网卡不工作
    import os
    missing = []
    for grp, dirs in GROUPS.items():
        for d in dirs:
            if not os.path.isdir(os.path.join(ctx.srcdir, d)):
                missing.append(f"{grp}/{d}")
    if missing:
        # 上游不时合并/改名目录（如 20250613 拆掉 e1000 等独立目录）。
        # 缺失目录太多说明版本错位，仍然硬拒；少量缺失打警告继续，
        # 避免"上游重命名导致整个固件包装不上"这种次生灾害
        if len(missing) > 8:
            raise RuntimeError(
                "固件源码树里缺少声明的目录，疑似版本错位，拒绝构建："
                + "、".join(missing[:8]) + "…"
                + "\n  要么源码版本变了（改 version），要么目录名变了（改 PACKAGE_GROUPS）")
        ctx.log("警告: 以下固件目录在本版上游中不存在（可能是上游重命名），跳过: "
                + "、".join(missing))


def package(ctx):
    """按组取出固件到 /usr/lib/firmware。"""
    import os
    import shutil

    out = os.path.join(ctx.destdir, "usr", "lib", "firmware")
    os.makedirs(out, exist_ok=True)
    picked = []
    for grp in PACKAGE_GROUPS:
        for d in GROUPS.get(grp, []):
            src = os.path.join(ctx.srcdir, d)
            if not os.path.isdir(src):
                continue
            dst = os.path.join(out, d)
            shutil.copytree(src, dst, dirs_exist_ok=True)
            picked.append(d)
    # 上游把部分固件（iwlwifi 等）平铺在顶层，按前缀补抓
    for pre in PACKAGE_PREFIXES:
        for fn in sorted(os.listdir(ctx.srcdir)):
            if fn.startswith(pre + "-") and os.path.isfile(
                    os.path.join(ctx.srcdir, fn)):
                shutil.copy(os.path.join(ctx.srcdir, fn), os.path.join(out, fn))
                picked.append(fn)
    # 记录取了哪些组，装机后能查到"这台机器带了什么固件"
    with open(os.path.join(out, ".qy-groups"), "w") as f:
        f.write(" ".join(PACKAGE_GROUPS) + "\n")
    ctx.log(f"已取固件组: {' '.join(PACKAGE_GROUPS)}（{len(picked)} 项）")
