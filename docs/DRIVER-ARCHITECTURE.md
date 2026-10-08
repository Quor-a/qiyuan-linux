# 启元 Linux 硬件驱动架构

> 状态：2026-10-08 起草。本文是**产品蓝图的可执行形式**——每一项都对应
> 代码里的模块或内核配置项，不是愿望清单。

## 一、设计原则

1. **只内置通用必备驱动，其余按需获取。**
   live 镜像与基础装机只带"绝大多数机器开机即用"的驱动（有线网、常见
   WiFi、常见显卡、USB 全栈、存储控制器）。小众/专有驱动（NVIDIA 私有、
   Broadcom wl、特定企业网卡）不进基础镜像，由驱动面板按检测结果提示安装。

2. **一切安装走 qypkg 仓库。**
   不做"联网偷偷下驱动"。驱动/固件都是 **可签名的 qyp 包**，来源可审计。
   与主流包管理（apt/dnf/pacman）的对应关系仅作为**查询参考**（qydrv alias），
   不直接调用它们。

3. **识别 → 匹配 → 行动，三段式闭环。**
   `qyhw` 识别硬件 → `qydrv` 生成计划 → `qypkg` 执行。任何一段都可单独
   测试（传入文本而非真机），保证 CI 里能验证。

4. **缺失在构建期暴露，不在装机后爆发。**
   `linux-firmware` 配方对声明的目录做存在性校验；内核片段里每条
   `CONFIG_*` 都在构建日志可查。

## 二、分层架构

```
┌─────────────────────────────────────────────────────────┐
│  驱动管理面板 / qydrv CLI                                 │
│  扫描设备 · 生成修复计划 · 开机自检 · 兼容源查询            │
└───────────────┬─────────────────────────────────────────┘
                │
   ┌────────────┼────────────┬──────────────┬─────────────┐
   ▼            ▼            ▼              ▼             ▼
 qyhw        qykmod       qyudev         qypkg       linux-firmware
 硬件识别     模块映射      设备权限       包安装        固件包
 (lspci/lsusb (设备↔模块)  (规则/组)     (qyp 事务)    (按需裁剪)
  解析)
   │            │            │
   ▼            ▼            ▼
内核驱动层：内核 config 片段（kernel-config/*.fragment）
  ├ qiyuan-net-bus.fragment      有线网/WiFi/蓝牙/USB/NVMe
  └ qiyuan-peripherals.fragment  触摸屏/显示/文件系统/虚拟机/移动设备
```

## 三、能力矩阵（对应产品需求）

| 需求 | 内核层 | 用户态 | 状态 |
|---|---|---|---|
| 触摸屏 | TOUCHSCREEN_* / HID_* / I2C_HID | libinput | ✅ 已配（peripherals 片段）|
| 显示器连接管理 | DRM 全驱动 + KMS + 热插拔 | wayland/weston/xorg | ✅ |
| 有线网口 | e100/e1000e/r8169/igb/... | NetworkManager | ✅ |
| WiFi | iwlwifi/ath/rtw/brcm/mt76 | iwd + NM(-Dwifi=true) | ✅ |
| 蓝牙 | BT 核心 + btusb/hci_uart | bluez | ✅ |
| USB | xhci/ehci/ohci/uhci + 存储/串口/网卡 | usbutils/libusb | ✅ |
| 数据线连接（MTP） | USB_F_MTP + configfs gadget | （面板调用）| ✅ 已配 |
| D盘/NTFS/exFAT | NTFS3 + exFAT + FUSE | ntfs-3g(可选) | ✅ 已配 |
| 虚拟机客户机驱动 | virtio/vmware/vbox/hyperv/xen | — | ✅ 已配 |
| Android 虚拟环境 | binder/ashmem/f2fs 见下 | qyandroid | ⚠️ 部分 |
| Windows 虚拟环境 | KVM + virtio | qemu | ⚠️ 待建包 |
| 驱动管理面板 | — | qydrv + GUI | ✅ 后端就绪 |
| 启动自检安装 | — | qydrv boot-check | ✅ |
| 内核管理面板（升级） | — | qykernel(规划) | ❌ 待做 |
| 兼容主流包管理 | — | qydrv alias | ✅ 查询就绪 |

## 四、Android 虚拟环境驱动

需要内核侧：
- `CONFIG_ANDROID_BINDER_IPC` / `BINDERFS`（Waydroid 基础）
- `CONFIG_ASHMEM`（旧式共享内存）
- `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"`
- `CONFIG_PSI`（压力失速信息，容器/虚拟环境需要）

用户态：`qyandroid`（bin/qyandroid 已存在，待接入 Waydroid 容器运行时）。

## 五、驱动管理面板数据流

```
开机
 └─ qydrv boot-check          (读 /proc/modules、查组，<100ms)
     ├─ 有问题 → 通知面板「检测到 N 个硬件缺驱动/固件」
     └─ 无问题 → 静默

用户点「扫描」
 └─ qyhw scan                 (lspci/lsusb → 设备列表)
     └─ qydrv fix             (设备列表 → JSON 修复计划)
         └─ 用户确认
             └─ qypkg install linux-firmware iwd bluez ...  (qyp 事务)
```

## 六、不做与原因

- **不内置专有 GPU 驱动**：许可证、体积、内核版本强耦合。基础显示用
  开源 nouveau/amdgpu/i915；需要 CUDA 的用户自行从仓库装（有签名可审计）。
- **不自动下载未审计驱动**：所有安装经 qypkg 仓库，保证可回滚、可签名验证。
- **不替代内核自带的驱动匹配**：udev + kmod 的 modalias 机制已能自动
  加载模块；我们只在"固件缺失/用户态栈缺失"这些内核管不到的地方补位。

## 七、可测试性

- `qyhw demo` / `qydrv demo`：内置样例，无需真机跑通全链路
- `qydrv fix`：纯 JSON 输出，CI 里可断言动作集合
- `qydrv boot-check`：纯读 /proc，可单元测试
- linux-firmware 配方：目录校验，构建期即暴露偏移
