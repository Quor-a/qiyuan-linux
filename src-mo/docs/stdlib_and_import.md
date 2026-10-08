# 标准库与 import 搜索路径

状态：已实现
日期：2026-10-08

## 1. 标准库现状

| 文件 | 提供 |
|---|---|
| `lib/io.mo` | `print` / `print_i64` / `print_nl` / `utoa` / `print_hex` |
| `lib/str.mo` | `strlen` / `streq` / `strcpy` / `memset` / `memcpy` / `strcat` / `memcmp` / `strchr` / `is_digit` / `atoi` |
| `lib/mem.mo` | `heap_init` / `alloc` / `alloc8` / `heap_used` / `heap_reset` |
| `lib/assert.mo` | `assert_eq` / `assert_true` / `test_done` |

全部用墨语言自身写成。

### 命名约定

标准库函数名沿用 C 的习惯（`strlen` / `atoi` / `memcpy`），
理由是墨语言的目标场景是系统编程，读者对这套名字有肌肉记忆。
等有模块系统之后再考虑归类。

## 2. import 搜索路径

原先 `import "io.mo";` 只按原样打开，
于是 `examples/` 下的程序必须写 `import "../lib/io.mo";`，
或者把标准库手工拷到旁边——都很别扭。

现在依次尝试：

1. 原样
2. `lib/<basename>`
3. `../lib/<basename>`

于是 `examples/wc.mo` 写 `import "io.mo";` 就能直接用标准库：

```
$ ./bin/moc examples/wc.mo /tmp/wc.elf && /tmp/wc.elf
2 lines, 7 words, 32 chars
```

### 两个踩坑

#### 坑 1：新增全局变量要小心

第一版用 `var SP_BUF: i64 = 8500000;` 当路径拼接缓冲，
**一走搜索路径就段错误**。

一开始怀疑缓冲区地址与其他区域冲突，换到 `heap + O_SCAL + 3000`
仍然段错误——说明不是地址问题。

最终改成**不用全局变量**，直接在函数里取
`heap + O_SCAL + 3000`（O_SCAL 中段是空闲区），一切正常。

教训：`src/compiler.mo` 里能不加全局变量就不加，
优先用 scratch 区或局部常量。这文件已经 2000+ 行，
每多一个全局槽位都可能是新的耦合点。

#### 坑 2：硬编码路径会让所有 import 打开同一个文件

调试时为了排除干扰，临时把搜索写成
`return syscall(2, "lib/io.mo", 0, 0, 0, 0, 0);`——
结果 `import "str.mo"` 也去读了 `lib/io.mo`。

于是 io.mo 的内容被当成 str.mo 编了一遍，
报错信息是 `str.mo:4:30: undefined symbol 'syscall'`——
**文件名和代码内容对不上**，非常有迷惑性。

这个错是我调试版本自己的问题，不是编译器的，
但它说明一件事：**报错里的 INPATH 可能是误导的**，
排查 import 相关问题时，先确认每个 import 实际打开的是哪个文件。

## 3. 真实程序：examples/wc.mo

统计行数、词数、字符数。用到了：

- 全局变量累加器（`lines` / `words` / `chars`）
- 字符串遍历（`while load8(s+i) != 0`）
- 状态机（词内/词外，靠 `inword` 标志）
- 标准库 `io.mo` 的 `print` / `print_i64`

```mo
fn count(s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        let c: i64 = load8(s + i);
        chars = chars + 1;
        if c == 10 { lines = lines + 1; }
        if is_space(c) == 1 { inword = 0; }
        else {
            if inword == 0 { words = words + 1; }
            inword = 1;
        }
        i = i + 1;
    }
    return i;
}
```

它同时验证了搜索路径、标准库、全局量、数组访问四条链路。

目前从内建字符串读入；读真实文件需要补 `open`/`read` 系统调用封装，
等有文件 IO 标准库再做。

## 4. 遗留

| 项 | 说明 |
|---|---|
| 无文件 IO | 标准库还没有 `open` / `read` / `write` 封装 |
| 无动态字符串 | `strcat` 不检查目标缓冲区容量 |
| `atoi` 不做溢出检查 | 超长数字会静默回绕 |
| 标准库无命名空间 | 名字可能与用户函数冲突 |
