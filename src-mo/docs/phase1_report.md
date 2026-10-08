# 阶段一 验收报告：语言内核补强

周期：2026-10-08 ~ 2026-10-08（第 1-5 周任务集中完成）
状态：**通过**

## 通过标准核对

| 通过标准 | 结果 | 证据 |
|---|---|---|
| 数组 / 指针 / 多文件程序能编译并运行 | ✅ | 测试 11-17、dup_import、mutual_import、chain_import、cyclic_import |
| 语法错误输出 file:line:col | ✅ | `test.mo:3:19: error: undefined symbol 'qq'` |
| 每步自举回归通过 | ✅ | 每次改动后 `verify_bootstrap.sh` 三级 md5 一致 |

额外完成：结构体（`struct`）与结构体数组，超出原定第 4-5 周范围。

## 交付内容

### 语法增量

| 特性 | 示例 | 实现位置 |
|---|---|---|
| 数组（全局/局部） | `var g: [8] i64 = 0;` `let a: [16] i64;` | parse_global / parse_let |
| 局部数组常量填充 | `let a: [4] i64 = 5;` | parse_let |
| 下标读写 | `a[i+1] = a[i] + a[i-1]` | index_addr |
| 一元取地址 | `sum(&a, 5)` | parse_addr |
| 多文件 | `import "lib.mo";` | compile_file / parse_import |
| 结构体 | `struct P { x: i64; y: i64; }` | parse_struct |
| 嵌套结构体 | `o.in.v = 7` | field_chain |
| 结构体数组 | `let a: [3] Box;` `a[0].v = 10` | ty_size + index_addr |

### 基础设施增量

| 设施 | 说明 |
|---|---|
| 行列诊断 | `advance_lc` 增量维护，`err_at2` 输出 `文件:行:列: error: ...` |
| 编译器侧字符串池 `O_STRS` | 让编译器能读被编译程序里的字符串字面量（import 路径） |
| 源码基址 `K_SRCBASE` | 切换文件只改一个变量，词法层无感知 |
| 结构体表 + 类型编码 | `O_STN/O_STF/O_STFLD/O_STFT/O_STY` |
| import 去重 `O_IMP` | 重复与循环 import 均安全 |

## 代码规模

```
src/compiler.mo          约 1750 行（阶段一起点 1329 行）
src/asm/*.s              约 2100 行（未改动）
tests/                   30 个用例全通过（26 单文件 + 4 多文件）
examples/                bubble_sort.mo：结构体 + 数组 + 全局量综合程序
```

## 测试

```
bash tests/run.sh bin/moc     # 通过 30 / 失败 0
bash verify_bootstrap.sh      # 三级 md5 一致
```

## 遗留（不阻断阶段二）

| 项 | 影响 | 计划 |
|---|---|---|
| 结构体不能按值传参 | 只能传指针 | 阶段二类型系统统一处理 |
| 无 `->` 运算符 | 指针访问字段要手写偏移 | 阶段二 |
| 结构体不能整体赋值 | `a = b` 报错 | 阶段二拷贝语义 |
| import 无命名空间 | 重名会覆盖 | 阶段二符号冲突检测 |
| 无数组/下标越界检查 | 越界静默 | 阶段二诊断 |
| 单类型 i64 | 无 bool/byte/float | 阶段二类型系统引入 |

## 真实程序验证

`examples/bubble_sort.mo`：8 元素冒泡排序，用结构体 `Stat` 统计交换次数与趟数，
用全局数组存数据，用局部数组做数字转字符串的缓冲区。

```
$ ./moc && ./out.elf
sorted: 01 21 30 48 67 70 87 88
$ echo $?
8          # 排序趟数
```

说明阶段一语法已足以写出带数据结构、多函数、循环的完整程序。

## 结论

阶段一的目标——「补齐写真实程序必需的语法」——已达成。
现在用墨语言可以写出带结构体、数组、多文件模块的完整程序。
进入阶段二：类型系统与诊断。
