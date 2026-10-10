# Ubuntu 差距审计

对照 Ubuntu 22.04/24.04 的构成，逐项排查澜岫 Linux 的缺失。
不是列功能清单，而是按"没有它系统能不能用"分级。

审计时间：2026-09-30 · 配方 181 个 · 工具 16 个 · 代码 23000+ 行

> **更新**：P0 四项（linux-firmware、PAM、sudo、locale）已在本轮补齐，
> 见 `recipes/linux-firmware.py`、`recipes/pam.py` + `qyos/pamd.py`、
> `recipes/sudo.py`、`recipes/glibc-locales.py` + `qyos/locale.py`。
> 四种形态全部带上（minimal 例外：容器镜像不需要固件）。
> 专项测试 22 项全绿（`tests/p0.sh`）。

---

## 判定原则

Ubuntu 有的我们不一定都要有——systemd、apt、snapd 我们用了自己的解法，
那不是缺失，是设计选择。真正要找的是**没有对应能力**的项：

- Ubuntu 有，我们没有，且**没有替代方案** → 缺失
- Ubuntu 有，我们用别的方式解决 → 设计差异，不算缺失
- Ubuntu 有，我们只在开发侧有、用户侧没有 → 半成品

---

## P0：没有它，系统装完不能用

这四项在虚拟机/容器里都测不出来，真机一装必然暴露。

### 1. linux-firmware（最危险） —— **已补齐**

Ubuntu 装机自带 linux-firmware 包，里面有网卡、无线、显卡的固件。
我们**完全没有**。

后果：大部分有线网卡、几乎所有无线网卡、AMD/Intel 显卡、NVMe 部分型号
在真机上直接不工作。用户装完发现连不上网，第一反应是"这个系统不行"。

为什么最危险：**开发环境测不出**。虚拟机用的是 virtio 虚拟设备，
不需要固件；容器更不需要。这个缺失在沙盒里永远不会暴露，
只在真机首次装机时爆发——而那时用户已经把硬盘格了。

### 2. PAM（Linux-PAM） —— **已补齐**

Ubuntu 的整套认证栈基于 PAM：登录、su、sudo、屏幕锁、密码策略。
我们**完全没有**。

后果：login、su 全部不成立，只能以 root 直接进系统。
没有 PAM 就没有"普通用户"这回事，多用户系统是假的。

### 3. sudo —— **已补齐**

配方里有 shadow（用户/组），但**没有 sudo**。
Ubuntu 默认禁用 root 登录、全靠 sudo。

后果：装完系统没有可用的权限提升机制。以 root 日常操作是安全事故，
而 su 又依赖 PAM（见上）——两项叠加，等于没有权限管理。

### 4. locale / 语言环境 —— **已补齐**

**没有 locale-gen、没有 /etc/locale.conf、没有 LANG 设置**。
配方里 locale 相关命中数为 0。

后果：中文用户拿到系统直接乱码，`ls` 出来的中文文件名是问号，
终端显示方块。这是 Ubuntu 装机第一步就做的事（`locale-gen zh_CN.UTF-8`）。

用户手册里 locale 只出现 1 次，说明这条链路根本没建起来。

---

## P1：能开机，但很快出问题

### 5. logrotate

**完全没有**。日志会无限增长，几个月后撑爆磁盘。
Ubuntu 默认配了 logrotate 每天滚动。

### 6. 定时任务（cron / timer）

有 qyinit 管服务，但**没有 cron 也没有定时器机制**。

后果：logrotate、证书续期、更新检查、临时文件清理
这些"该定期跑的事"全部跑不了。它们不是可选项——
没有定时清理的系统，半年后必然出问题。

### 7. DNS 解析管理

没有 `/etc/resolv.conf` 的管理者（Ubuntu 用 systemd-resolved）。
装完系统 DNS 谁来写、NetworkManager 改了之后谁来更新，都不明确。

### 8. 无线（wpa_supplicant / iwd）

**完全没有**。笔记本装完连不上 WiFi——
配合上面第 1 项（没有固件），无线是彻底不可用的。

### 9. os-prober（多系统引导检测）

**没有**。装双系统时 grub 找不到已有的 Windows 或 Ubuntu，
用户会看到"只有澜岫一个启动项"，如果直接装就覆盖了别人的系统。

这一项的后果不可逆：**用户数据丢失**。

---

## P2：设计差异，不是缺失

这些 Ubuntu 有，我们用不同方式解决，不算缺失：

| Ubuntu | 澜岫的解法 | 状态 |
|---|---|---|
| systemd | qyinit（C 实现，含依赖拓扑、崩溃限流） | 已实现 |
| apt/dpkg | qypkg + .qyp 格式（事务、回滚、自动依赖发现） | 已实现 |
| journald | syslog-ng | 已实现 |
| snapd | qyapp 登记层（纳管 Flatpak/Snap/AppImage） | 已实现 |
| apt 源管理 | qysource（多源、优先级、失效降级） | 已实现 |
| ufw | qynet firewall（按登记端口生成 nftables） | 已实现 |
| netplan | NetworkManager（配方已有） | 已实现 |
| udev | libudev + 内核配置已含 | 部分 |
| AppArmor | 内核配置已含选项，无策略集 | 部分 |

---

## P3：体验层差距

- plymouth 开机动画：无（不影响使用）
- grub 主题：无
- 密码强度检查（cracklib/pwquality）：无
- unattended-upgrades：有 qysec 扫描，但无自动应用安全更新

---

## 最需要警惕的三件事

**一、固件缺失会被开发环境完全掩盖。**
这是本次审计最重要的发现。它在 2 核沙盒、虚拟机、容器里都不暴露，
只在真机首次装机时爆发。而那时用户已经格了盘。
任何"在虚拟机里跑通了"的验证都证明不了固件没问题。

**二、PAM + sudo 同时缺失，等于没有权限模型。**
单缺 sudo 还能用 su 顶，单缺 PAM 还能以 root 凑合。
两项都没有，多用户系统就是假的——而且不会报错，
用户只会觉得"这个系统好像不太对"，说不出哪里不对。

**三、os-prober 缺失的后果不可逆。**
P0 那四项装完能补救，os-prober 缺失会导致用户覆盖掉已有系统。
这是唯一一项会造成数据丢失的。

---

## 补齐顺序建议

按"不补会怎样"排，不是按"好不好做"排：

1. **linux-firmware** — 补配方，装机镜像必带
2. **PAM** — 补配方 + /etc/pam.d 配置集
3. **sudo** — 补配方 + sudoers 默认配置
4. **locale** — 补 locale-gen 流程 + /etc/locale.conf，装机时询问语言
5. **os-prober** — 装机脚本里检测已有系统并加入引导菜单
6. **logrotate** — 补配方 + 默认滚动规则
7. **定时任务** — qyinit 加 timer 单元类型
8. **wpa_supplicant** — 补配方
9. **DNS 解析** — 明确 resolv.conf 归属

前五项做完，系统才具备"在真机上给真人用"的基本条件。

---

## 审计方法说明

- 命中数按关键词在 `recipes/`、`qyos/`、`docs/` 下检索统计
- 0 命中不等于必然缺失（可能用了不同命名），但结合人工确认，
  上述各项确无对应实现
- 沙盒环境无法验证真实编译与真机行为，
  P0 各项的后果是按 Ubuntu 实际依赖链推定的
