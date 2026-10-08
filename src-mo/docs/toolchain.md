# 墨语言工具链

状态：已实现（阶段三 · 第 12-17 周）
日期：2026-10-08

## 1. 命令行参数

`moc` 现在接受命令行参数：

```
moc <输入.mo> [输出名]
```

省略时退回 `test.mo` / `out.elf`（兼容既有测试脚本）。

### 实现：argc() / argv() 内建

启动代码 `_start` 在调用 `main` 之前，把 `argc` 与 `argv` 存进
**数据段头 16 字节**：

```
[rsp]            -> [0x10000000]     argc
lea rcx,[rsp+8]  -> [0x10000008]     argv 基址
```

因此所有程序的全局变量都从 `0x10000010` 开始。
**seed 与 moc 都必须预留这 16 字节**，否则会覆盖第一个全局变量。

`argc()` / `argv(i)` 是内建，在 `parse_primary` 里于 `parse_call` 之前处理。

### 为什么必须在 parse_primary 里处理

最初放在 `parse_call` 里，用 `cscratch()` 保存函数名。
但嵌套调用会覆盖它：`load8(argv(1))` 中，内层 `argv(1)` 解析完后
`cscratch` 已变成 `"argv"`，导致外层 `load8` 也被当成 `argv` 处理，
生成两段 argv 代码、丢掉 `load8` 的 load —— 运行即 SIGSEGV。

改到 `parse_primary` 里、名字还在 `scratch1()` 中时判断，就没有这个问题。

## 2. 构建脚本 mobuild.sh

```
tools/mobuild.sh <主文件.mo> [-o 输出名]
```

做三件事：

1. **递归收集 import 依赖**并打印拓扑序，缺失文件提前报错。
2. 把所有依赖拷进临时目录，调 `moc` 编译。
3. 输出产物大小。

`moc` 本身就能递归处理 import，这个脚本的价值在于把依赖图显式化：
能一眼看出编进去了哪些文件，循环依赖和缺失文件也能提前发现。

```
$ tools/mobuild.sh tests/stdlib/main.mo -o /tmp/app.elf
mobuild: 主文件 main.mo
mobuild: 依赖 2 个
  main.mo
  io.mo
  str.mo
mobuild: 输出 /tmp/app.elf（4154 字节）
```

## 3. 标准库

| 文件 | 提供 |
|---|---|
| `lib/io.mo` | `print` / `print_i64` / `print_nl` |
| `lib/str.mo` | `strlen` / `streq` / `strcpy` / `memset` / `memcpy` |
| `lib/mem.mo` | `heap_init` / `alloc` / `alloc8` / `heap_used` / `heap_reset` |
| `lib/assert.mo` | `assert_eq` / `assert_true` / `test_done` |

全部用墨语言自身写成，靠 `import` 引入。

### 分配器

bump 分配器，只增不减，16 字节对齐。
`heap_init` 用 `brk(0)` 取当前断点，`alloc` 用 `brk(pos+4096)` 扩展。
没有 free —— 需要回收时整体 `heap_reset()`。

### 测试框架

```
assert_eq("name", got, want);   # 不等则打印 FAIL 行
test_done();                    # 打印 ran/failed，返回失败数
```

配合 `tests/run.sh` 用退出码当断言结果。

## 4. 本次踩的坑

| 坑 | 现象 | 修法 |
|---|---|---|
| `emit4` 的入参在 `%edi` 不在 `%eax` | `imul rax,rax,<垃圾>` | 改用 `movl $8, %edi` |
| `movabs` 只发了 4 字节立即数 | 后续指令字节被当成 imm64 吃掉 | 改用 `emit8` |
| REX 前缀算错 | `mov [r11],rax` 写成 `4d 89 03`（实为 `mov [r11],r8`） | 改成 `49 89 03` |
| 嵌套调用覆盖 `cscratch()` | `load8(argv(1))` 生成两段 argv 代码 | 移到 `parse_primary` 判断 |

前三个都属于「手写 x86 编码」的典型失误，靠 `objdump` 逐字节对照抓出来。
第四个是作用域问题，靠最小复现抓出来。

**教训**：自举闭环是最好的回归测试。seed 与 moc 产物只要差一个字节，
`verify_bootstrap.sh` 就会报「自举不一致」——这三个编码错误全是它逼出来的。
