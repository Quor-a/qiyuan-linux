# 交叉编译实测矩阵

版本 1.9.0（2026-10-08）

## 工具链从哪来

`apt-get install gcc-aarch64-linux-gnu` **在这台机器上装不上**
（源 403 / 未签名，包不存在）。所以改用 **zig**（`pip install ziglang`），
它自带各目标的 libc，不需要系统包管理器。

`tools/cross.sh` 的查找顺序：`${TRIPLET}-gcc` → `${TRIPLET}-clang` → `zig cc`。
都没有时仍生成 C 源码并给出安装提示，不假装成功。

## 实测结果（全部真编出来了）

| 目标 | 产物类型 | 状态 |
|---|---|---|
| `aarch64-linux-musl` | ELF ARM aarch64 静态 | ✅ |
| `riscv64-linux-musl` | ELF RISC-V 静态 | ✅ |
| `x86_64-linux-musl` | ELF x86-64 静态 | ✅ **本机实跑，退出码 30** |
| `x86_64-windows-gnu` | PE32+ Windows | ✅ |
| `aarch64-macos` | Mach-O arm64 | ✅ |
| `wasm32-wasi` | WebAssembly | ✅ |
| `aarch64-freestanding` | ELF ARM64 无 libc | ✅ |
| `riscv64-freestanding` | ELF RISC-V 无 libc | ✅ |
| `x86_64-freestanding` | ELF x86-64 无 libc | ✅ **本机实跑，打印 + 退出码 7** |

另外 musl 目标还试过并成功：`powerpc64`、`s390x`、`loongarch64`、
`x86(32位)`。`mips64` 与 `arm(32位)` 的 libc zig 未自带，会明确报错。

**Android 的 `aarch64-linux-android` zig 不提供 libc** —— 所以 Android 走
`tools/android.sh` 的 java / ndk / web 三条路径，而不是直接交叉编译。

## freestanding 后端（新增）

```bash
./bin/mo2x app.mo cfs            # x86_64，无 libc
./bin/mo2x app.mo cfs-aarch64
./bin/mo2x app.mo cfs-riscv64
```

系统调用用**内联汇编**直接陷入内核，架构各自的约定：

| 架构 | 调用号 | 参数 | 指令 |
|---|---|---|---|
| x86-64 | rax | rdi rsi rdx r10 r8 r9 | `syscall` |
| ARM64 | x8 | x0–x5 | `svc #0` |
| RISC-V | a7 | a0–a5 | `ecall` |

入口是自己写的 `_start`，不经过 crt。

**这一步的真正意义**：freestanding 产物不依赖任何 libc，
所以在**任意**有对应内核的 Linux 上都能跑 —— 包括 Android
（Android 内核就是 Linux 内核，系统调用号与 ARM64 Linux 一致）。
这是绕开 NDK 的一条现实路径。

## 修掉的一个致命 bug

初版把 x86-64 的**系统调用号放进了 r8**，第一个参数放进了 rax。
于是实际执行的系统调用号 = 第一个参数的值。

`write(1, ...)` 恰好"碰巧正确"（号=1，参数也对），所以能打印；
但 `exit(60)` 变成"调用 7 号系统调用"，程序挂死。

> 这类 bug 最阴险的地方：症状是"打印正常但退不出"，
> 很容易被误判成别的问题。
