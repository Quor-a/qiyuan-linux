# 调试信息（-g）

状态：已实现（0.8.0）；默认关闭

## 用法

```bash
moc prog.mo -g prog.elf
```

之后 gdb 可以按源码行下断点。只生成最小可用集：一个 CU DIE + 行号表。
**不含**变量、类型、栈帧信息 —— 能下断点、能看行号，不能 `print 变量名`。

## 为什么默认关闭

自举要求 seed 与 moc 对 `src/compiler.mo` 产出逐字节相同的产物。
seed（手写汇编的引导编译器）不实现调试信息，所以：

- 不开 `-g` → 两者都不生成调试节 → 字节一致 ✓
- 开 `-g` → 只有 moc 生成 → 字节不一致 ✗

因此 `-g` 默认关闭，且 `verify_bootstrap.sh` 不开它。

## 生成了什么

| 节 | 内容 |
|---|---|
| `.debug_info` | 一个 CU DIE：name / low_pc / high_pc / stmt_list / producer / language |
| `.debug_abbrev` | 该 DIE 的属性表 |
| `.debug_line` | 行号程序：源码行 -> 代码地址 |
| `.shstrtab` | 节名字符串表 |
| 节头表 | 7 项 |

行号程序只用三种最保守的操作：
`DW_LNS_advance_line` / `DW_LNS_advance_pc` / `DW_LNS_copy`。
不用 special opcode —— 它要靠 line_base / line_range 计算，
算错会让整张表错位。

## 行号怎么来的

`dbg_mark()` 在 `parse_stmt` 开头记录 `(当前 code_len, 当前行)`。
同一地址不重复记录。**只记主文件**：`parse_import` 会在解析子文件期间
把 `K_DBG` 临时置 0，`dbg_mark` 于是直接返回；退出时恢复原值。

代价：import 进来的标准库代码没有行号。

## 三个坑

1. **调试缓冲区被字符串池覆盖**：最早放在 `heap + 27MB`，编译自身时
   读出来全是字符串内容（字符串池会涨过 5MB）。挪到 60MB 仍被盖。
   最终用 `brk` 在主堆之后单独申请 4MB。教训：不要靠估算偏移避让，要真隔离。
2. **8 参数函数让 seed 生成错误代码**：见 CHANGELOG 0.8.0。
3. **内建函数调用的实参里不能再嵌函数调用**：编译器用同一缓冲区存
   「当前被调函数名」，嵌套调用会覆盖它。

## 遗留

| 项 | 说明 |
|---|---|
| 没有变量与类型信息 | gdb 不能 print 变量名 |
| import 的文件没有行号 | — |
| 没有 CFI | 回溯不可靠 |
| 行号记录上限 60000 条 | 超出后静默停止 |
