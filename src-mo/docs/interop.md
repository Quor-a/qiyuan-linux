# 与其它语言互相调用

版本 1.8.0

## 一、从宿主语言调用墨语言

墨语言原生后端产出**静态 ELF**，不依赖 libc，因此：

| 宿主 | 方式 |
|---|---|
| C / C++ | `moc x.mo x.elf` 本身就是可执行文件；若要当库用，用 C 后端生成 `.c` 一起编译 |
| Python | `subprocess.run(["./x.elf"])`，或用生成的 `.c` 编 `.so` 后 ctypes 加载 |
| JS / Node | `child_process.execFile("./x.elf")`，或用 JS 后端直接在进程内跑 |
| Java | `ProcessBuilder`，或用 Java 后端直接编进应用 |
| Shell | 直接执行 |

**最干净的方式是 C 后端**：`mo2x x.mo c` 得到的 `.c` 可以编成 `.so`，
然后任何有 FFI 的语言都能加载它（Python ctypes、Java JNI、Node ffi）。

## 二、从墨语言调用外部

| 能力 | 做法 |
|---|---|
| 系统调用 | `syscall(n, a, b, c, d, e, f)` —— 直接陷入内核，无需 libc |
| 文件 | `lib/fs.mo` |
| 网络 | `lib/net.mo`（socket/bind/listen/accept/send/recv 全是 syscall） |
| 动态内存 | `lib/mem.mo`（bump 分配器） |
| 子进程 | `lib/pty.mo` 的 `execve` / `waitpid` / `kill` |

墨语言**没有**通用的 C ABI 调用能力（不能 `dlopen` + 按 C 约定传参）。
要调外部动态库，得自己用汇编/syscall 搭，这是当前明确的边界。

## 三、标准库在各后端的可用性

| 库 | 原生 | C | JS | Python | Perl | Java/Go/… |
|---|---|---|---|---|---|---|
| io / str / mem / vec / map | ✅ | ✅ | 部分 | 部分 | ❌ | ❌ |
| fs / net / dir / crypto / hmac | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| log / matrix / stat | ✅ | ✅ | 部分 | ✅ | 部分 | 部分 |

❌ 的原因：这些库依赖 `syscall` / 指针 / `load8` 等线性内存能力，
而 JS / Python / Perl 后端没有线性内存语义。
要给它们做内存，需要模拟一整块字节数组并把指针运算改写成索引 ——
那是另一个量级的工作，目前明确不做。
