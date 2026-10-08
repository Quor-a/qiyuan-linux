# 墨语言 Mo —— 一门从零自举的原创编程语言

一门静态类型、编译到原生 x86-64 机器码的系统级小语言，编译器**用墨语言自身写成**，
并完成 Stage 0 → 1 → 2 → 3 完整自举闭环。

## 已完成（截至 2026-10-08）

| 里程碑 | 状态 |
|---|---|
| Stage 0：手写 x86-64 汇编版编译器 `bin/seed` | ✅ 约 2100 行汇编 |
| Stage 1：墨语言版编译器 `src/compiler.mo`（1329 行） | ✅ |
| Stage 2：墨编译器编译自身 | ✅ |
| Stage 3：产物与上一版**字节完全一致**（`md5 b7f2be32…`） | ✅ |
| 92 项测试全通过（58 正常 + 23 编译错误 + 多文件/标准库/工具链/排序） | ✅ |
| 格式化工具 `tools/fmt.mo`（墨语言自写，代码段字节不变） | ✅ |
| 性能基准套件 `bench/`（5 个基准，可存档基线对比） | ✅ |
| 栈顶缓存：首个寄存器分配（array -14% / str -33%） | ✅ |
| 动态数组 `lib/vec.mo` + 字符串键映射 `lib/map.mo` | ✅ |
| 入门教程 `docs/tutorial.md` | ✅ |
| 未使用变量检查（警告，不阻断编译） | ✅ |
| 完整寄存器分配 | ❌ 需先有 IR，见 `docs/regalloc_design.md` |
| SHA-256 / CRC32 / Base64 / ChaCha20 | ✅ |
| tar 打包解压 + gzip（系统工具可读） | ✅ |
| JSON 解析、编辑器高亮、CI 配置 | ✅ |
| 交叉编译 / APK / 多架构 / GPU | ❌ 需新后端，见 `docs/capability_matrix.md` |
| 复合赋值 `+=` `-=` `*=` `/=` `%=` `&=` `|=` `^=` | ✅ |
| 常量下标越界在编译期拦截（`a[9]` 直接报错） | ✅ |
| `byte`（1 字节）与 `ptr`（字节指针）类型，字符串可写 `s[i]` | ✅ |
| 数组越界检查：`a[i]` 越界不再静默破坏内存，报错并以 1 退出 | ✅ |
| `else if` 链（迭代式，整条链共用一个出口标签） | ✅ |
| 五个真实程序：bubble_sort / wc / grep / sort / freq | ✅ |
| 字符串字面量直接下标 `"hello"[1]` | ✅ |
| CHANGELOG + VERSION 0.1.0 | ✅ |
| 字符字面量 `'a'` / `'\n'`，seed 与 moc 均已支持 | ✅ |
| `break` / `continue`（含嵌套循环），seed 与 moc 均已支持 | ✅ |
| 文件 IO 标准库 + 两个真实程序（wc / grep） | ✅ |
| import 搜索路径：写 `import "io.mo"` 即可用标准库，不必手工拷贝 | ✅ |
| 代码生成优化六项：常量窄化 / disp8 / push 折叠 / 右操作数常量化 / 2 的幂移位 / 死跳转消除，代码体积 -30.4% | ✅ |
| 新增诊断：缺少 return 检查（漏写 return 不再静默返回垃圾值） | ✅ |
| 阶段一「语言内核补强」验收通过 | ✅ |
| 阶段二「类型系统与诊断」验收通过 | ✅ |

## 目录

```
src/asm/*.s        Stage 0 编译器：手写 GNU as 汇编（base/lex/sym/expr/stmt/main）
src/compiler.mo    墨语言写的墨语言编译器（自举主体）
src/mo/            拆分的编译器源码（part1~part5，cat 后即 compiler.mo）
verify_bootstrap.sh 自举闭环验证脚本
bin/seed           汇编版编译器
bin/moc_seed       由 seed 编译出的墨编译器
bin/moc_self       由 moc_seed 编译出的墨编译器（与 moc_seed 字节一致）
tests/*.mo         26 个单文件测试 + run.sh
tests/*/           多文件测试（含循环 import）与标准库测试
tests/errors/      16 个编译错误用例，验证诊断确实拦得住
lib/               标准库：io.mo（print / print_i64 / print_hex）、str.mo（strlen / streq /
                   strcpy / strcmp / memset / memcpy / strcat / strchr / atoi）、mem.mo（bump 分配器）、
                   fs.mo（fopen / fread / fwrite / fclose / read_file）、assert.mo（断言框架）
CONTRIBUTING.md    如何改编译器：seed/mo 双改规则、自举回归、调试技巧
Makefile           make / make test / make boot / make all
tools/mobuild.sh   构建脚本：递归收集 import、打印依赖图、调 moc 编译
tools/codesize.sh  统计各程序代码段字节数，用于对比代码生成优化收益
examples/          冒泡排序（结构体 + 数组 + 全局量）、wc.mo（行/词/字符统计）、
                   grep.mo（子串搜索，用 break + 文件 IO）、sort.mo（文本行排序）、
                   freq.mo（词频统计，用 byte 数组 + ptr 下标）
docs/language.md   语言参考（类型、语法、内建、已知限制）
bench/             性能基准套件
tools/fmt.mo       格式化工具（墨语言自写）
CHANGELOG.md       版本历史；VERSION 记录当前版本号
docs/              数组 / 结构体 / 多文件 / 类型系统 / 工具链 / 代码生成优化设计文档
PROGRESS.md        与 26 周计划的进度对照
build.sh           构建入口
```

## 快速开始

```bash
./build.sh all                # 汇编 seed，再由 seed 编译 compiler.mo → bin/moc
bash verify_bootstrap.sh      # 验证自举闭环：三个 Stage 产物字节一致
bash tests/run.sh bin/moc     # 跑 47 项测试
```

`verify_bootstrap.sh` 会依次做三次编译并比对 md5：

```
Stage1 (seed 编译):  b7f2be32eb88d961fa6648e145f2975a
Stage2 (moc  编译):  b7f2be32eb88d961fa6648e145f2975a
Stage3 (moc  再编):  b7f2be32eb88d961fa6648e145f2975a
✅ 自举闭环成立：三个 Stage 产物字节完全一致
```

单独编译一个墨程序：

```bash
mkdir -p /tmp/w && cp your.mo /tmp/w/test.mo
cd /tmp/w && /data/workspace/mo/bin/moc_self   # 产出 out.elf
chmod +x out.elf && ./out.elf
```

## 语言速览

```mo
# 注释以 # 开头
var counter: i64 = 0;                 # 全局变量

fn fib(n: i64) -> i64 {               # 函数，最多 6 个参数
    if n < 2 {
        return n;
    }
    return fib(n - 1) + fib(n - 2);   # 递归 / 互递归均可
}

fn main() -> i64 {
    let i: i64 = 0;                   # 局部变量
    while i < 10 {
        counter = counter + fib(i);
        i = i + 1;
    }
    syscall(1, 1, "hi\n", 3, 0, 0, 0);  # 内建：Linux 系统调用
    return counter;                     # 退出码（仅低 8 位可见）
}
```

### 已支持

- 类型：`i64`（当前唯一类型，指针即整数）
- 运算：`+ - * / % & | ^ ~ ! << >> < <= > >= == != && ||`、一元 `&` 取地址
- 语句：`let` / 赋值 / `if`-`else` / `while` / `return` / 表达式语句
- 数组：`var g: [8] i64 = 0;`、`let a: [16] i64;`，下标 `a[i]` 读写
- 结构体：`struct P { x: i64; y: i64; }`，支持嵌套字段 `o.in.v` 与结构体数组 `a[0].v`
- 模块化：`import "lib.mo";`，多文件共享符号表，支持互相调用与链式引用
- 字面量：十进制、十六进制 `0x`、字符串（支持 `\n \t \r \0 \\ \"`）
- 内建：`load8` `load64` `store8` `store64` `syscall`
- 字符串字面量求值即数据段地址，可直接当缓冲区用
- 诊断：错误带 `文件名:行:列` + 源码行 + 列指示符
- 编译期检查：实参个数、下标/字段访问对象、赋值兼容、重复定义、数组长度、空 return、缺少 return
- 命令行：`moc <输入.mo> [输出名]`，程序内可用 `argc()` / `argv(i)`
- 循环控制：`break` / `continue`（支持嵌套）
- 分支链：`if` / `else if` / `else`
- 字符字面量：`'a'` `'\n'` `'\t'` `'\0'`（值即字符编码）
- 文件 IO：`import "fs.mo"` 后可用 `read_file` / `fopen` / `fread` / `fwrite`

```mo
struct Point {
    x: i64;
    y: i64;
}

struct Box {
    v: i64;
    w: i64;
}

fn main() -> i64 {
    let p: Point;
    p.x = 3;
    p.y = 4;

    let a: [3] Box;                  # 结构体数组
    a[0].v = 10;
    a[2].w = 2;

    return p.x + p.y + a[0].v + a[2].w;   # 19
}
```

命令行：

```
moc prog.mo prog.elf        # 省略则退回 test.mo / out.elf
tools/mobuild.sh main.mo -o app.elf   # 并打印 import 依赖图
```

```mo
var g: [8] i64 = 0;

fn sum(p: i64, n: i64) -> i64 {      # 数组经 & 取地址传入
    let s: i64 = 0;
    let i: i64 = 0;
    while i < n {
        s = s + load64(p + i * 8);   # 指针算术按字节
        i = i + 1;
    }
    return s;
}

fn main() -> i64 {
    let a: [5] i64;
    a[0] = 1; a[1] = 2; a[2] = 3; a[3] = 4; a[4] = 5;
    return sum(&a, 5);               # 15
}
```

### 计算库

| 文件 | 提供 |
|---|---|
| `lib/matrix.mo` | 定点矩阵：乘法 / 转置 / 行列式 |
| `lib/stat.mo` | 均值 / 方差 / 标准差 / 协方差 / 相关系数 / 线性回归 / 中位数 |
| `examples/calc.mo` | 表达式计算器（调度场算法，+ - * / % ^ 与括号） |
| `examples/plot.mo` | 终端 ASCII 折线图 |

墨语言没有浮点类型，矩阵与统计全部用 **SCALE=1000 定点数**。

### 容量限制（不假装无限）

- `archive.mo`：单个文件 64KB
- `dir.mo`：目录遍历缓冲 64KB
- `strcat`：不检查目标缓冲区容量
- `atoi`：不做溢出检查

### 尚未支持（后续路线图）

byte/bool/float 等机器类型、返回值非空检查、内建函数签名检查、
构建/测试/格式化工具、调试信息、寄存器分配与优化、包管理；
结构体支持整体赋值 `a = b`（逐字段深拷贝），但仍不支持按值传参。
详见「墨语言完整实现路线图」与 `docs/`。

## 产物格式

`bin/moc` 直接写出 **ELF64 静态可执行文件**（两个 PT_LOAD：R+X 代码段 @0x400000，
R+W 数据段 @0x10000000），不依赖 libc 与任何外部链接器。
