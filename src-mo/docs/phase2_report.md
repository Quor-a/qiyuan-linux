# 阶段二 验收报告：类型系统与诊断

周期：2026-10-08（第 6-11 周任务集中完成）
状态：**通过**

## 通过标准核对

| 通过标准 | 结果 | 证据 |
|---|---|---|
| 类型系统能表达 int/ptr/array/struct 并做赋值兼容检查 | ✅ | `docs/type_system_design.md` + `ty_*` 实现 |
| 函数调用检查实参个数 | ✅ | 错误用例 e01 / e02 |
| 错误输出 file:line:col + 源码行 + 列指示符 | ✅ | 全部错误用例均输出三行 |
| 每步自举回归通过 | ✅ | 每次改动后 `verify_bootstrap.sh` 三级 md5 一致 |

## 已拦下的错误（16 类）

| 用例 | 触发 | 诊断消息 |
|---|---|---|
| e01 / e02 | 实参个数不符 | `wrong number of arguments` |
| e03 | 对非数组取下标 | `subscript on non-array type` |
| e04 | 对非结构体取字段 | `field access on non-struct type` |
| e05 | 整体赋值给数组 | `cannot assign to an array` |
| e06 | 使用未声明标识符 | `undefined symbol 'xxx'` |
| e07 | 字段类型不存在 | `unknown type` |
| e08 | 整体赋值给结构体 | `cannot assign a struct value` |
| e09 | 局部变量重名 | `duplicate definition` |
| e10 | 全局变量重名 | `duplicate definition` |
| e11 | 函数重名 | `duplicate definition` |
| e12 | 形参重名 | `duplicate definition` |
| e13 | 结构体字段重名 | `duplicate definition` |
| e14 / e16 | 数组长度为 0 | `array length must be a positive constant` |
| e15 | 空 `return;` | `return with no value in a function returning i64` |

诊断样例：

```
test.mo:6:17: error: wrong number of arguments
        return add(1);
                    ^
```

## 类型系统实现

`docs/type_system_design.md` 定的类型表已落地：

| 区域 | 内容 |
|---|---|
| `O_TK/O_TA/O_TB` | 类型表：kind / aux1 / aux2，最多 512 个，构造时去重 |
| `O_STY[sym]` | 变量类型 id |
| `O_STFT[si*32+fi]` | 结构体字段类型 id |
| `O_FRT` / `O_FPT` | 函数返回类型 / 形参类型（当前全为 int，已铺好结构） |

kind：`0` int、`1` void、`2` struct、`3` array、`4` ptr。
`ty_new` 线性查重，同一类型在任何地方都是同一个 id，判等即整数比较。

表达式类型通过全局变量 `R_ETY` 传播（墨语言没有结构体返回值，
这是编译器内部一贯的做法）。

## 实现中踩的坑

### 坑 1：seed 的 `r12` 被破坏（跨阶段遗留，本轮修掉）

`sym_lookup` / `sym_lookup_func` 用 `r12` 当临时寄存器但没保存。
`parse_block` 也用 `r12` 保存 `cur_depth`，于是深层嵌套的块结束后
`cur_depth` 被写坏 → 变量作用域错乱 → 明明声明过的变量突然「未定义」。

只在深层嵌套里偶发，之前一直没暴露。用逐行删减（delta debugging）
逼出最小复现后定位到根因，加 `pushq/popq %r12` 修好。

**这是本轮最有价值的修复**：它让 seed 编译器本身变健壮了，
否则后面每写一个复杂函数都可能随机踩雷。

### 坑 2：`err_at2` 会直接退出进程

`err_at2` 末尾是 `syscall(60, ...)`。最初 `err_atp` 写成
「先 `err_at2` 再 `err_src`」，结果源码行永远打不出来。

修法：`err_atp` 自己拼头部三行，再调 `err_src`，最后才退出。

### 坑 3：形参个数回填时机

`parse_func` 原先在函数体编译完才回填形参个数，
而函数体里的递归调用在那之前就要查个数 → 误报
`wrong number of arguments`。

修法：在 `g_prologue()` 之前就回填。
同时给 `predeclare` 加了「扫描 `(` 到 `)` 数逗号」的形参计数，
让跨文件、前向引用的调用也能拿到正确个数。

### 坑 4：数组符号类型写错

迁移到类型表时，`parse_let` 的两个数组分支漏了改，
写进去的是元素类型 `et` 而不是 `ty_array(et, n)`，
导致所有局部数组都被当成标量 → 5 个测试编译失败。

## 数字

```
测试：      46 / 46 通过（30 个正常用例 + 16 个错误用例）
自举：      Stage1 = Stage2 = Stage3，md5 一致
compiler.mo：约 2050 行（阶段二起点约 1750 行）
```

## 遗留（不阻断阶段三）

| 项 | 影响 | 计划 |
|---|---|---|
| 只有 int 一种机器类型 | 无 byte/bool/float | 后续版本 |
| 不做返回值非空检查 | 函数末尾无 return 不报错 | 阶段三诊断增强 |
| 实参类型不做逐个检查 | 只查了个数 | 待 `R_ETY` 覆盖更完整后开 |
| `syscall`/`load8` 等内建不做签名检查 | 参数写错不报错 | 阶段三 |
| 无 `help:` 建议行 | 诊断只有源码行 | 阶段三 |

## 结论

阶段二目标——「让编译器能拦住真实错误」——已达成。
16 类错误全部有明确消息、准确行列和源码上下文。
进入阶段三：标准库与工具链。
