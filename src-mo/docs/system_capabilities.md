# 系统能力：目录、终端、签名、安装器与工具链

版本 1.5.0（2026-10-08）

---

## 一、做完的 ✅

| 需求 | 交付 |
|---|---|
| 目录 | `lib/dir.mo`：遍历（getdents64）、stat 大小/模式、mkdir/rename/unlink/chmod |
| 元数据 / 版本 / 魔数 | `lib/binfmt.mo`：识别 ELF/gzip/tar/PNG/ZIP/PDF/JPEG/BMP/WASM/脚本/文本；
读出 ELF 的 class / machine / entry / shnum |
| PTY | `lib/pty.mo`：伪终端主从端、窗口大小、fork/exec/wait/kill |
| Root | 走 `syscall` 直达内核；`getpid`、`kill`、`chmod` 都可用。**不做提权** |
| 签名 | `lib/hmac.mo`：HMAC-SHA256（RFC 4231 向量校验）+ 常量时间比较 |
| 日志 | `lib/log.mo`：级别过滤、文件输出、环形缓冲回看 |
| 脚本 | `tools/mo.sh run` —— 编译并立即运行，脚本式体验 |
| 安装器 | `tools/install.sh`：装 moc / mo / 标准库到 PREFIX |
| 声明 / 元数据 | `tools/manifest.mo` + `tools/project.mo.example`（`mo.mod` 清单） |
| 构建 / 工具链 | `tools/mo.sh`（build/run/test/boot/fmt/size/info/version/clean） |
| 内核 | `uname` / `sysinfo`（内存总量、运行时长） |

### 签名这块要说清楚

**做不了真正的非对称签名**（RSA / Ed25519）——需要大数运算，
单轮做不完且极易出错。

提供的是 **HMAC-SHA256**：双方共享密钥时能验证「消息没被篡改、
确实来自持钥方」。它解决不了「验签方可以公开验证」，
那是非对称签名的场景。若要公开验签，需要再加 RSA 或 Ed25519。

`mac_eq` 用**常量时间比较**——不能用 `strcmp` 提前退出，
那会泄漏"前几位是对的"的信息。

---

## 二、UI / 界面 / 图标 / 渲染 / 组件：做不到 ❌

| 需求 | 为什么 |
|---|---|
| UI / 界面 | 需要窗口系统（X11/Wayland）协议客户端，或终端 UI 库 |
| 图标 | 需要图像编解码（PNG 解码可做，图标渲染需要图形栈） |
| 渲染 | 需要 GPU 或 framebuffer 驱动接口 |
| 组件 | 组件模型依赖上面的 UI 框架 |

**这不是"加个库"**：墨语言只有一个 x86-64 Linux 后端，
且完全不链接 libc。要画图，得先能跟显示服务器对话——
那是一个新的协议/驱动层，和写 ARM64 后端是同一量级。

终端内的文本 UI（TUI）**可以做**：已经有 PTY 和终端能力，
用 ANSI 转义序列画框是纯文本输出。如果下一步要做界面，
这是最现实的路径。

---

## 三、这一轮踩到的坑

### 1. 运算符优先级：`==` 比 `&` 结合更紧

```mo
if (m / 4096) & 15 == 8 { ... }     # 错！
```

被解析成 `(m / 4096) & (15 == 8)`，而 `15 == 8` 是 0，
所以整个表达式恒为 0 —— `is_file` / `is_dir` 永远返回假。

**这类 bug 不报错、不崩溃，只是判断永远不成立。**
修法是显式加括号 `((m / 4096) & 15) == 8`。

### 2. ioctl 号手算错

`TIOCGPTN` 我写成 `2147757104`，正确是 `2147767344`；
`TIOCSWINSZ` 我也把类型字段写成了小写 't'。

症状是 `ioctl` 返回 -1，`pty_master` 直接失败。
**教训：ioctl 号用 `_IOC(dir,type,nr,size)` 算出来，不要手写十进制。**

### 3. 测试污染仓库根目录

`run.sh` 在 `/tmp/mot` 里编译，却在**仓库根目录**运行产物。
凡是碰文件系统的用例（mkdir / 写文件）都会把垃圾留在仓库里，
而且**第二次跑必然失败**（mkdir 返回 EEXIST 被当成错误）。

这是个 hiding bug：第一次跑全绿，第二次才红。
已改成在 `/tmp/mot` 里运行。

> **测试必须能在干净环境里反复跑。**
> 第一次通过不算通过，第二次通过才算。

### 4. ELF 元数据缓冲太小

`MAGIC` 一开始只有 16 字节，但要读 ELF 头（64 字节）
和 tar 的 257 偏移，直接越界报错。改成 512。

---

## 四、数字

```
测试：94 / 94
自举：Stage1 = Stage2 = Stage3
新增库：dir / binfmt / pty / log / hmac / manifest（约 700 行）
工具：  mo.sh（9 个子命令）、install.sh、info.mo
```
