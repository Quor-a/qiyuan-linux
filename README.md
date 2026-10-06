# 启元 Linux（Qiyuan Linux）

一个从零开始的自建 Linux 发行版工程。工具链自己控制，包格式与包管理器自己实现，
构建配方自己定义，软件以上游源码为输入。

当前状态：**地基已完工并跑通端到端验证**——从配方到可运行软件的完整链路可用。

```
配方 → 沙箱构建 → 独立安装目录 → .qyp 包（签名）→ 仓库索引（验签）→ 包管理器安装 → 可运行
```

---

## 一、已经做出来的东西

### 1. 自建包格式 `.qyp`

单文件三段式容器（`qyos/format.py`）：

| 段 | 内容 | 作用 |
|---|---|---|
| header 128B | 魔数、版本、段偏移与长度、段哈希 | 不解压就能定位与校验 |
| meta | JSON 元数据：依赖、provides、文件清单（含 sha256）、安装脚本 | 快速查询、依赖求解、完整性校验 |
| data | tar.gz 数据段，路径相对根目录 | 实际文件 |
| sig | ed25519 对 (meta+data) 哈希的签名，可分离 | 防篡改 |

### 2. 构建系统 `qybuild`

- 配方是纯 Python 模块（`recipes/*.py`）：声明式字段 + `build()` / `package()` 两段式
- 构建隔离：统一 PATH 与编译参数、清空宿主侵入变量、命名空间 + 默认断网（`unshare -n`）
- **构建依赖自动装进 sysroot**，头文件与库路径注入构建环境——这是通向交叉编译的接口
- 编译基线一次定好全系统生效：`-fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wl,-z,relro,-z,now`
- 边构建边入库，后面的包才能拿到前面的依赖
- 幂等：已构建的包自动跳过，`--force` 强制重编

### 3. 包管理器 `qypkg`

- 依赖求解：版本约束、虚拟包与提供者、冲突检测、循环依赖检测、拓扑排序
- 事务化安装：先算完整变更集 → 校验 → 写入，**失败按日志回滚**
- 显式安装 / 依赖安装分开标记，可清理孤儿包
- 已安装包存 SQLite：查文件归属、反查依赖者、校验文件是否被改动
- 卸载保护：仍被依赖的包拒绝卸载

### 4. 仓库 `qyrepo`

- 索引记录每个包的 sha256，安装时按索引校验包文件
- 索引必须签名，篡改索引会被明确拒绝
- 密钥 ed25519，密钥 ID 可核对

### 5. 根文件系统与 init

`filesystem` 包提供 FHS 骨架和 `/usr` 合并布局（`/bin` `/sbin` `/lib` 指向 `/usr`），
外加基础 `/etc`。`qyinit` 是一个真正能用的 1 号进程，C 语言实现：

- 挂载 `/proc` `/sys` `/dev`，创建必要设备节点
- 读服务单元、按依赖拓扑排序启动、停机时逆序停止
- 回收孤儿进程（1 号进程的天职）
- 按 `Restart=` 策略拉起崩溃的服务，并带**崩溃风暴限流**（10 秒内最多 5 次）
- 收到 SIGTERM 走正常关机流程

`qypkg assemble` 把一组包组装成可启动的根，`bootcheck` 检查它能不能开机
（init 在不在、合并布局生效没、动态库缺不缺），`manifest` 生成完整清单可比对
两台机器装出来是否一致。

### 6. 内核配置管理 `qyos/kernel.py`

配置项上万条，手写 `.config` 不可维护。做法是一个基线 + 若干片段叠加：

```bash
./bin/qybuild --kernel-config --arch x86_64 \
  --fragment kernel/config/base-x86_64.fragment \
  --fragment kernel/config/hardening.fragment \
  --out kernel/config/merged.config
```

必需项（initramfs 支持、devtmpfs、futex、EFI…）和禁用项（强制模块签名、
KGDB…）写成清单，每次构建强制校验。这份清单本身就是发行版的安全姿态声明。

### 7. initramfs 构建器 `qyos/initramfs.py`

内核不会直接挂真根——它挂 initramfs，由里面的程序找到真根再切过去。
这里用纯 Python 手写 cpio(newc) + gzip，不依赖外部 `cpio` 命令，产物可复现。

早期 init 用 C 写成并**强制静态链接**：它运行时 `/usr/lib` 还没挂载，
动态链接器找不到 libc，一执行就段错误。这是新手最容易踩的坑，
`inspect` 会把它当作硬性检查项。

```bash
./bin/qybuild --initramfs --out var/boot/initramfs.img
```

### 8. 自举分析 `qyos/bootstrap.py`

自举 = 用这套系统重建这套系统，是"原创发行版"和"套壳改版"的分界线。
三关：

1. **工具链关**：用宿主编译器编出自己的 gcc/binutils
2. **系统关**：用第一遍工具链编出全套基础系统，产物不得链接宿主任何库
3. **自持关**：用第二遍的系统重编所有包，逐字节一致（可复现构建）

```bash
./bin/qybuild --bootstrap
```

会算出构建闭包、检测循环构建依赖、按关分批、报出阻塞项。

### 9. 磁盘分区与镜像 `qyos/disk.py` `qyos/bootloader.py` `qyos/image.py`

装机最容易出事的地方就是分区。把方案变成可校验的数据，再生成分步脚本：

```bash
./bin/qydisk layout  --disk /dev/nvme0n1 --size 200G --memory 16G
./bin/qydisk scripts --disk /dev/sda --size 100G --out var/install/scripts
./bin/qydisk image   --target /tmp/root --image-size 4G
```

几个刻意做的决策：

- **fstab 一律用 UUID**，不用 `/dev/sda1`。设备名在加装硬盘、换接口后会漂移，
  这是"昨天还好好的今天起不来"的头号原因
- **swap 跟着内存走**：<2G 给 2 倍，8~64G 给一半（上限 8G），>64G 固定 4G
- **EFI 分区按挂载点判定而非文件系统**——按 fs 判的话，
  "EFI 分区误设成 ext4"就查不出来，而那恰恰是最该拦住的错误
- **NVMe/MMC 的分区名带 p**（`nvme0n1p1` vs `sda1`），写死 sda1 会分错盘
- **GRUB 配置必须带一个非静默的救援项**：系统起不来时第一件事就是看内核输出，
  只给一个 quiet 项是给自己找麻烦
- **装机脚本拆成 6 步**，每步可单独重跑，失败不用从头再来
- **清空磁盘前强制二次确认**，并先 `wipefs` 清旧签名

### 10. 安全响应 `qyos/security.py`

系统发布只是开始，真正考验发行版的是出事之后。CVE 公布后，
多久能知道哪些包受影响、多久能出修复包、用户多久能拿到。

```bash
./bin/qysec scan --root /mnt/system      # 这台机器上有什么没修
./bin/qysec by-cve --cve CVE-2026-0001   # 某个 CVE 影响哪些包
./bin/qysec rebuild --changed glibc      # 改了这个包，谁要跟着重编
```

两个刻意做对的地方：

- **按版本区间判定，不是按版本号相等**。CVE 影响 1.2~2.0，
  只查 `version == 1.2` 会漏掉绝大多数受影响的安装
- **改一个包要算出谁要重编**。共享库一改，所有链接它的包都得重编，
  只发新库不发依赖方，运行时会炸

### 11. 系统形态 `qyos/profile.py`

同一个发行版可以长成不同样子：容器最小系统、服务器、桌面、开发工作站。
差别不在内核和包管理器，而在**选哪些包 + 怎么配置**。

```bash
./bin/qyrelease profiles --profile server
```

形态必须**声明它排除了什么**——只写"包含桌面"不写"不装打印服务"，
用户拿到手才知道少了什么。

### 12. 发布工程 `qyos/release.py`

```bash
./bin/qyrelease bump --version 0.1.0-rc.2 --bump promote   # → 0.1.0
./bin/qyrelease manifest --dir var/release --sign var/repo/keys/qiyuan
./bin/qyrelease verify  --dir var/release --pubkey var/repo/keys/qiyuan.pub
./bin/qyrelease changelog --version 0.1.0
```

**发布清单里每个产物都有 sha256，清单本身也签名**。只发镜像不发校验和，
用户无法判断自己拿到的是不是被中间人换过的东西。

### 13. 自动依赖发现 `qyos/shlibdeps.py`

扫产物 ELF 的 DT_NEEDED → 反查哪个包提供该 soname → 自动补进 depends。

```bash
./bin/qybuild --shlibdeps qydemo
```

手工维护依赖必然遗漏（忘写 glibc 最常见），后果是装包时报"找不到共享库"，
且安全扫描会漏。只加不删——自动分析看不出"还需要某个数据文件包"。

### 14. 循环依赖处理 `qyos/cycles.py`

包库到 166 个时撞上了一个真实的环：

```
cairo → fontconfig → freetype → harfbuzz → cairo
```

```bash
./bin/qybuild --cycles
```

用 Tarjan 强连通分量一次找全所有环（而不是遇到一个崩一个），
配方用 `cycle_break` 声明断在哪一侧，然后两遍构建：
先编断开版，环上包齐了再重编。**忘了重编，系统会带着一个不支持复杂文本
排版的 freetype 发布出去——能跑、能过测试，中文和阿拉伯文渲染是错的。**

### 15. 工具链引导器 `bootstrap/bootstrap.py`

把 Linux From Scratch 的手工步骤变成**可无人值守、可断点续跑**的自动化流程：
宿主检查 → 下载校验 → 交叉 binutils → 交叉 gcc（无 libc）→ 内核头文件 → glibc →
libstdc++ → 完整交叉编译器 → 工具链自检。每阶段幂等、写检查点、日志分离。

版本基线已按 **LFS 12.4（2025-09-01 发布）** 核对：binutils-2.45、gcc-15.2.0、
glibc-2.42、linux-6.16.1。其余条目在 `bootstrap/versions.json` 中标为 TODO，
开工当天从 LFS 官方书填充实际版本，不要沿用过期值。

---

## 二、马上可以跑

```bash
cd qiyuan

# 生成签名密钥（只需一次）
./bin/qybuild --gen-key var/repo/keys/qiyuan

# 构建全部配方（含依赖求解、sysroot 依赖安装、签名入库）
./bin/qybuild all --sign var/repo/keys/qiyuan

# 查看仓库
./bin/qyrepo list --pubkey var/repo/keys/qiyuan.pub

# 安装到某个根（/ 就是装到本机，也可以指向任意目录或挂载的系统）
./bin/qypkg --root /tmp/qyroot install qydemo

# 跑起来
LD_LIBRARY_PATH=/tmp/qyroot/usr/lib /tmp/qyroot/usr/bin/qydemo
# → qydemo 0.1.0
#   1 + 2 = 3

# 端到端冒烟测试（16 项检查）
./tests/smoke.sh        # 地基链路 18 项
./tests/upgrade.sh      # 升级与回滚 19 项
./tests/system.sh       # 根文件系统与 init 27 项
./tests/boot.sh         # 内核配置 / initramfs / 自举分析 17 项
./tests/install.sh      # 分区 / fstab / 引导器 / 装机脚本 / 镜像 15 项
./tests/security.sh     # 安全响应 / 系统形态 / 发布工程 20 项
./tests/deps.sh         # 自动依赖发现 / 循环依赖 / 大规模依赖图 20 项
```

组装一个能启动的根并实测 init：

```bash
./bin/qypkg --root /tmp/qyroot assemble filesystem qyinit qydemo
./bin/qypkg --root /tmp/qyroot bootcheck
/tmp/qyroot/usr/bin/qyinit --unit-dir /tmp/qyroot/etc/qyinit.d \
    --log /tmp/boot.log --oneshot
```

工具链引导（需要约 30G 磁盘、宿主装有 bison/flex/gawk 等）：

```bash
python3 bootstrap/bootstrap.py plan            # 看阶段计划
python3 bootstrap/bootstrap.py preflight       # 检查宿主环境
python3 bootstrap/bootstrap.py run             # 开始引导
python3 bootstrap/bootstrap.py run --from gcc-p1   # 断了从某阶段继续
```

---

## 三、已验证的能力（16 项冒烟测试全绿）

| 能力 | 验证方式 |
|---|---|
| 配方树解析与依赖排序 | 全量构建按正确顺序完成 |
| 构建依赖隔离安装 | libqydemo 自动装进 sysroot 后 qydemo 才编译 |
| 包格式自洽 | 每个 .qyp 的 meta/data 段哈希校验通过 |
| 索引验签 | 篡改 index.json 后安装被明确拒绝 |
| 包文件校验 | 仓库包哈希与索引记录全部匹配 |
| 依赖自动安装 | 装 qydemo 自动带上 libqydemo |
| 真实可运行 | 安装后的二进制能执行并输出正确结果 |
| 完整性校验 | 能检出文件被篡改 |
| 依赖保护 | 拒绝卸载仍被依赖的包 |
| 卸载干净 | 递归卸载后无残留文件 |

---

## 四、还没有做的（对应 12 个月路线图）

| 阶段 | 内容 | 状态 |
|---|---|---|
| 地基期 | 工具链引导器 | 结构完成，需在真实构建机上跑通 |
| 包与仓库期 | 原子升级、并行下载、系统级回滚 | **已完成**（19 项测试） |
| 包与仓库期 | 原子升级、并行下载、系统级回滚 | 单包事务回滚已有，系统级快照待做 |
| 系统成型期 | 根文件系统、init、内核配置、initramfs、自举分析 | 结构**已完成**（44 项测试）；真机编译待做 |
| 装机与镜像期 | 分区方案、fstab、引导器、装机脚本、镜像 | **已完成**（15 项测试）；真机装机待做 |
| 安全与发布期 | 漏洞响应、系统形态、发布工程 | **已完成**（20 项测试） |
| 包库与依赖期 | 166 个配方、自动依赖发现、循环依赖打破 | **已完成**（20 项测试） |
| 装机与形态期 | 安装器、ISO、桌面与服务器形态 | 待做 |
| 产品级稳定期 | 安全响应、CI、文档体系、1.0 | 待做 |

**判断：能不能叫原创发行版，取决于自举能否打通**——用这套系统重建这套系统，
不再依赖任何宿主发行版。地基已完成，剩下的时间是确定的工程量，不是未知数。

---

## 五、目录结构

```
qiyuan/
├── qyos/            内核模块（格式/配方/沙箱/依赖/构建/仓库/包管理）
├── bin/             qybuild · qypkg · qyrepo
├── recipes/         构建配方（*.py）
├── bootstrap/       工具链引导器 + 版本配置
├── tests/           演示源码 · 端到端冒烟测试
├── var/
│   ├── pkgs/        构建产物 *.qyp
│   ├── repo/        仓库（索引、签名、密钥）
│   ├── sysroot/     构建依赖安装点
│   └── work/        构建中间目录
└── docs/            设计说明
```

## 六、给维护者的三条硬规矩

1. **远程源码必须锁 sha256**，本地源码目录可以留空。没有校验和就没有可复现。
2. **构建默认断网**。构建期偷偷联网的包，结果不可复现，也不安全。
3. **先保可复现，再谈功能**。构建流水线死了，进度就归零。

---

## 七、桌面环境进展（2026-10 实测）

**ISO v0.9 已在 QEMU 实测达成桌面闭环**：

![桌面](docs/screenshots/wallpaper.png)
![图标](docs/screenshots/icons.png) ![启动器](docs/screenshots/launcher.png)

- **内核**：linux 6.16.1（defconfig 基底 + DRM_BOCHS/DRM_VIRTIO_GPU/SQUASHFS/USB_HID/fbcon 等）
- **显示**：bochs-drm 加载 → seatd 会话 → udevd 设备枚举 → weston 14.0.2 DRM backend (pixman) 真上屏
- **桌面 qydesktop**（GTK3，`recipes/qydesktop.c`）：
  - 品牌壁纸（cairo + gdk-pixbuf 铺满，PIL 程序化生成）
  - 桌面图标（终端/文件/设置，点击 g_spawn 拉起）
  - 应用启动器窗口、顶栏（全宽 + 时钟）
- **文件管理器 qyfiles**（`recipes/qyfiles.c`）：目录导航、类型列、位置状态栏
- **中文渲染**：DejaVu + Noto Sans CJK（145 号包，Ubuntu pool 源 + sha256 锁定）
- **自研 init qyinit**：unit 依赖编排 + /dev/shm tmpfs + 崩溃重启

关键坑位记录（详见 git log）：grub-mkrescue 必须重跑（只 mksquashfs 不生效）、
udevd 缺席会让 libinput 枚举不到输入设备、qyinit unit `After=` 暂不生效需 sleep 兜底、
系统无字体时 Pango 会把窗口算成 65535px 高。

## 桌面一览（QEMU 实测截图）

| 桌面（中文+Noto CJK） | 品牌壁纸桌面 |
|---|---|
| ![桌面](docs/screenshots/chinese.png) | ![壁纸](docs/screenshots/wallpaper.png) |

**开始菜单**（搜索 + 固定应用网格 + 常用列表）：

![开始菜单](docs/screenshots/desktop-appmenu.jpg)

![统一图标主题](docs/screenshots/qyappmenu-color-icons.png)
*v1.7 统一图标主题：cairo 圆角色块 + 9 色板 + 深灰高对比标签*
![系统设置 v1.7](docs/screenshots/qysettings-170.png)
*v1.7.0 系统设置：关于页 Qiyuan Linux 1.7 + 声音/亮度页实际生效（ALSA Master / backlight）*
![用户管理 GUI](docs/screenshots/qyusers-gui.png)
*v1.7.1 用户管理 qyusers：用户列表 / 新建 / 改密 / 删除 / wheel 组标记*



## 桌面环境 v1.1.1（2026-10-04，QEMU 实测）

**渲染消失病已根治**：应用窗口在点击后不再被桌面壳层遮挡——

| 修复后桌面（多次点击窗口全部保持） |
|---|
| ![修复后](docs/screenshots/desktop-fixed.png) |

- **窗口管理**：weston 14.0.2 + 自研 shell 补丁——真任务栏（按窗口列表画按钮）、点击切换焦点、qy-winop 关闭/最小化
- **壳层策略**：qydesktop/dock/bar 固定在窗口层最底且激活不抬层；任务栏主 widget 全条命中
- **文件管理器 qyfiles v2**：回收站、新建文件夹、重命名/删除、右键选中行 + 工具栏操作
- **设置 qysettings**：声音（ALSA amixer Master）、屏幕亮度（/sys/class/backlight）
- **音频栈**：alsa-lib + alsa-utils 1.2.14（147 包）
- **健壮性**：initramfs cpio 重建修复、grub.cfg 显式化、DRM 输入设备未就绪自动重试

## 桌面环境 v1.2.1（2026-10-05，QEMU 实测）

**鼠标点击链路彻底打通**（v1.1.1–v1.2.0 连续三案告破）：

1. **渲染消失病**（v1.1.1）：应用窗口点击后被壁纸窗遮挡 → map 压底 z 序方向修正
   （weston 渲染器 `wl_list_for_each_reverse` → view_list 头=最顶、尾=最底；旧补丁插头=置顶）
2. **测试工具链**：QEMU monitor `mouse_button b=1` 是静默失败语法，正确为 `mouse_button 1`（按下）+ `0`（释放）
3. **HOME 归一**（v1.2.0）：GLib `g_get_home_dir()` 优先读 `$HOME`，init 环境未设时回收站等
   `~/.local` 路径全部错位 → start-qydesktop.sh 强制 `export HOME=$(getent passwd …)`

**回收站显示 bug 根治实证**（样本数据在而列表空 = HOME 错位，非读取逻辑问题）：

| 回收站视图（修复实证） |
|---|
| ![回收站修复](docs/screenshots/qyfiles-trash-ok.png) |

- qyfiles `--trash` 启动参数自证回收站视图；GtkApplication 只传 argv[0]
  （`--trash` 会被其命令行解析器判 Unknown option 静默退出——自启场景大坑）
- **qymon 系统监视器 v1**：/proc/stat CPU + /proc/meminfo 内存实时曲线（GtkDrawingArea+cairo，1s 刷新）
- **qyview 图片查看器 v1**：GdkPixbuf 打开/自适应、滚轮缩放、左右键同目录翻页、双击还原
- 应用菜单扩至 7 应用；启动器图标点击拉起应用全链路实测

**Release**：[v1.1.2](https://github.com/Quor-a/qiyuan-linux/releases/tag/v1.1.2)（ISO 1.2.0 + 全部修复）

## 开发进度与下一步

- ✅ 已完成：包管理/构建/仓库/init 内核全链路、weston 桌面+任务栏、鼠标点击闭环、
  qyfiles（回收站全功能）、qysettings（声音/亮度）、qyappmenu、qyedit、qymon、qyview（147 包）
- 🔧 进行中：qymon/qyview 启动器点击拉起的 VM 实测收尾
- 📋 下一步：
  1. 系统级完善：polkit/elogind、服务管理（qyinit 单元依赖可视化）
  2. 12 类最小集补齐（剩 音频播放器/视频播放器/文本终端增强/压缩管理器 等）
  3. qyfiles 图标视图 + qyview 缩略图浏览模式
  4. 安装器（ISO → 硬盘装机）

---

## v1.6.0（2026-10-06）

**qysudo 权限提升 + 用户管理**：

- **qysudo**（setuid-root C 程序）：/etc/qysudoers 授权（用户或 %wheel 组）→ /etc/shadow 密码校验（crypt_r SHA512，3 次重试）→ 提权执行；PATH 重置防注入；root 免密
- **用户体系**：/etc/shadow 落地（root:600）；wheel 组；qyuseradd 脚本（创建用户+home+入 wheel）
- **实测**：chroot 中 tester(wheel) 输密码 → qysudo id → uid=0(root) ✅
- 教训：/etc/shadow 里 root 为 `!`（锁定）时 sshd 拒绝一切认证（"account is locked"）→ root 必须有真实密码 hash（默认 qiyuan-root，README 提醒用户改）

下一步：统一图标主题、声音/亮度设置页、SQUASHFS_ZSTD 内核重配、qyuseradd GUI。

## v1.5.1（2026-10-06）

**qysetup 系统安装器 GUI**（应用菜单第 9 项「系统安装」）：

- 磁盘枚举（/sys/block，过滤小盘/sr），二次确认对话框，实时安装日志（g_child_watch + GIOChannel 管道），进度条
- 后端调 qyinstall CLI（已实测的安装逻辑）
- live 环境实测：GUI 正确列出 /dev/vda 8.0GB 并成功启动；硬盘引导环境正确报「未找到 live 介质」错误处理路径
- scripts/ 固化全部 ISO 构建脚本（mkiso/build-bootefi/build-live-initramfs/build-install-initramfs/live-init.sh），修复 /tmp 剪枝导致的构建脚本丢失

下一步：qysudo、用户管理、统一图标主题、声音/亮度设置页。

## v1.5.0（2026-10-06，QEMU 全链实测）

**系统安装器 qyinstall 落地 —— 启元可安装到硬盘独立引导**：

- `qyinstall /dev/vda`：GPT 分区（256M EFI + 剩余 ext4）→ mkfs → cp -a 复制系统 → 重新生成 SSH host key → fstab(UUID) → 安装版 initramfs（root=LABEL 直挂，非 live overlay）→ EFI 系统分区放 standalone GRUB（内嵌 cfg，serial console）
- **安装端到端实测**：空白 8G 盘 → live 引导 → qyinstall → 拔掉 ISO → OVMF UEFI 纯盘引导 → SSH 登入安装版系统，根分区 /dev/vda2 ext4（7.7G）
- ISO 修复：rootfs 改 gzip 压缩（内核 CONFIG_SQUASHFS_ZSTD 未开，zstd squashfs 挂载失败进救援 shell —— 教训入 README）

![安装后 UEFI 独立引导桌面](docs/screenshots/installed-desktop.png)

*硬盘安装版：qyfiles 回收站视图 + qymon CPU 曲线 + 终端，UEFI(OVMF) 纯盘引导，SSH 实测根分区 /dev/vda2 ext4*

下一步：qyinstall GUI 前端（qysettings 页）、qysudo、用户管理、统一图标主题。

## v1.4.2（2026-10-05，QEMU 实测）

**qyview 图片查看器修复**：

- dir_files GPtrArray 未初始化 → g_ptr_array 断言失败、窗口不显示 → scan_dir 前惰性创建
- 实测：SSH 拉起 qyview 打开 qiyuan.png，窗口「启元图片查看器」图片完整渲染

下一步：安装器（ISO→硬盘）、qysudo、用户管理、统一图标主题。

## v1.4.1（2026-10-05，QEMU 实测）

**qyarc 压缩管理器修复版**：

- **g_spawn_command_line_sync 不是 shell**：管道/重定向/|| 被当普通参数 → 改经 /bin/sh -c 执行（run_shell_sync）
- tar 列表解析重写：兼容 GNU tar 与 busybox tar（busybox -tv 输出 6 字段，原 7 字段 sscanf 整行解析失败 → 列表空白）
- tar 配方 --without-selinux（修 VM 内 GNU tar 缺 libselinux）
- 测试截图：tgz 双文件列表（测试A.txt/dataB.bin）GUI 实证

下一步：安装器（ISO→硬盘）、qysudo、用户管理、qyview 实测、统一图标主题。

## 桌面环境 v1.4.0（2026-10-05，QEMU 实测）

本轮把启元从"能跑桌面"推进到**"有系统管理能力的发行版"**——补齐了操作系统层面的
服务管理、网络自启、远程登录三条主干，并修掉一个会静默损坏系统文件的打包大坑。

### 新增：操作系统层能力

| 能力 | 实现 | 实测 |
|---|---|---|
| 服务管理 CLI `qyctl` | 无 dbus/polkit 依赖的自研 C 程序（list/status/start/stop/restart/enable/disable）；与 qyinit 通过 `/run/qyinit/units/<name>.pid` 契约协作 | SSH 进 VM 执行 `qyctl list` 输出 9 个单元 ✅ |
| 网络开机自启 `qynet` | `start-qynet.sh` + qynet.unit：busybox `udhcpc` DHCP，失败自动静态兜底（slirp 10.0.2.15） | VM 内 `10.0.2.15/24 scope global enp0s3` ✅ |
| 远程登录 | sshd 服务单元 + host key + 特权分离目录自建 | 宿主 `ssh -p 2222 root@127.0.0.1` 返回 `SSH-OK` / `uname -r = 6.16.1` ✅ |
| 开机自检 `qyselftest` | 每次启动把 uname/服务表/网络/磁盘/内存/进程数打到串口 | 串口输出 `===QYSELFTEST===` 全项 ✅ |
| 压缩管理器 `qyarc` | GTK3 图形化：打开/查看条目/解压到/新建/删除；后端 7za + tar | 7za 打包/列表在 VM 内实测 ✅（截图见下） |
| 应用菜单扩至 8 项 | 新增"压缩管理" | ✅ |

### 修复：一个会静默损坏系统的打包缺陷

`mksquashfs` 以普通用户身份运行，**读不到 root:600 的文件，却会静默打成 0 字节**。
受害文件包括 `/etc/ssh/ssh_host_*_key`（表现为 sshd 报 `no hostkeys available -- exiting`）。
修法：打包改用 `sudo mksquashfs ... -all-root`。
本项目的教训写进规矩：**任何"非 root 进程读写 root-only 文件"的打包步骤，都必须验证产物字节数，而不是看命令退出码。**

### 架构与语言选型（本轮成文）

写入 `doc_架构与语言选型.md`。核心结论：

| 层 | 语言 | 理由 |
|---|---|---|
| init / 服务 CLI / 桌面 / 应用 | C | 零运行时依赖、可审计、启动快；最小 rootfs 不装解释器 |
| 构建系统 / 包管理（开发机） | Python 3 | 依赖图求解与配方元编程，开发效率优先，不进目标系统 |
| 打包格式 / 脚本 | .qyp 数据格式 / POSIX sh | 无语言属性；脚本只用 busybox 支持的子集 |

明确不引入：systemd、polkit、PulseAudio、目标系统内的 Python 运行时。

### 测试截图

![启元桌面 v1.4.0](docs/screenshots/qymon-running.png)

*桌面实况：左侧「启元文件管理器」**回收站视图**（notes.txt / 报告草稿.txt 带"类型/原位置"列），
中上「启元系统监视器」CPU 5% 实时曲线（含负载尖峰）与 MEM 曲线，左下角终端。*

![回收站修复实证](docs/screenshots/qyfiles-trash-ok.png)

### 开发进度

| 项 | 状态 |
|---|---|
| 服务管理器 qyctl（9 单元） | ✅ 实测 |
| 网络 DHCP 自启 | ✅ 实测（10.0.2.15） |
| SSH 远程登录 | ✅ 实测（宿主→VM） |
| 开机自检输出 | ✅ 实测 |
| 压缩管理器 qyarc | ✅ GUI 实测（7za -slt 列表/中文名/解压） |
| squashfs 权限缺陷 | ✅ 已修 |
| 安装器 qysetup GUI（v1.5.1） | ✅ 实测（磁盘枚举/确认/日志/进度条） |
| 权限提升 qysudo + 用户管理 qyuseradd（v1.6.0） | ✅ 实测（wheel 组/shadow 密码校验/提权 uid=0） |
| 统一图标主题（v1.7） | ✅ 实测（cairo 圆角色块 9 色板 + 标签深灰高对比） |
| 声音/亮度设置页实际生效（v1.7.0） | ✅ 实测（amixer Master 读写 / backlight 写入；内核开 SND_HDA_GENERIC → QEMU 声卡 HDA Intel 识别，音量 55% 回读一致） |
| 版本号同步 | ✅ /etc/qiyuan-release 0.9 → 1.7，关于页显示正确 |
| 用户管理 GUI qyusers（v1.7.1） | ✅ 实测（列表/新建/改密/删除/[wheel] 标记；修 atoi 解析 bug） |
| SQUASHFS_ZSTD（v1.7.2） | ✅ 实测（内核开 ZSTD+SQUASHFS_ZSTD；rootfs 355MB zstd；**ISO 449→407MB -9.4%**；live VM 全功能正常） |
| **端到端装机（v1.7.3）** | ✅ **里程碑**：live ISO → qyinstall 写盘（GPT/EFI+ext4）→ OVMF 从硬盘引导 → 完整桌面系统（rootfstype=ext4 rw，qyuseradd 实测）。修 install initramfs 缺 bin/busybox 致 kernel panic 落 shell 的 bug |
| **首启向导 qywelcome（v1.8.0）** | ✅ 实测（装机后首启弹窗：主机名/用户/密码/时区 → 应用 → /etc/.qywelcomed 标记后不再弹） |
| **普通用户自动登录（v1.8.1）** | ✅ 实测（/etc/qyautologin 写用户名 → 桌面以该用户运行 ps 验证；wayland socket 权限共享方案） |
| **安装器集成用户预创建（v1.8.2）** | ✅ 实测（qysetup 安装时弹"初始用户"表单 → qyinstall --user 直接写目标盘 passwd/shadow/wheel/autologin → 从盘引导桌面以该用户运行；密码经 qyinit 首启 hook 用 busybox chpasswd 设置；修 busybox 无 cryptpw/VM 无 python3 的哈希生成死路） |

### 下一步开发

1. **qyarc GUI 桌面点击实测** + tar 后端兜底（系统 tar 缺 libselinux，先用 busybox tar）
2. **开机动画与 plymouth 级体验**（内核 fb 动画 / 简易 qyboot splash）
3. **多语言**：qydesktop 系列应用中文之外增加英文切换
4. **qysudo 策略增强**：按命令白名单（sudoers 子集语法）
5. **软件中心**：qypkg GUI（浏览/安装/卸载仓库包）
