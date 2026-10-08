# 墨语言入门教程

目标：**30 分钟跑通第一个程序**。
假设你会一点 C / Python / Go，但没接触过墨语言。

---

## 第 1 步：构建编译器（3 分钟）

```bash
cd mo
make
```

这会做三件事：汇编出引导编译器 → 用它编译出墨语言编译器 → 跑自举验证与全部测试。
看到 `✅ 自举闭环成立` 就成功了。

产物：

- `bin/seed` —— 手写汇编的引导编译器
- `bin/moc` —— 墨语言编译器（用墨语言自己写的）

日常只用 `bin/moc`。

---

## 第 2 步：第一个程序（2 分钟）

新建 `hello.mo`：

```mo
fn main() -> i64 {
    print("hello, mo\n");
    return 0;
}
```

等等——`print` 需要引入标准库。正确写法：

```mo
import "io.mo";

fn main() -> i64 {
    print("hello, mo\n");
    return 0;
}
```

编译并运行：

```bash
./bin/moc hello.mo hello.elf
chmod +x hello.elf
./hello.elf
```

输出 `hello, mo`。

**为什么 `import` 能找到 `io.mo`？** 编译器依次尝试：
相对当前文件的路径 → `lib/<文件名>` → `../lib/<文件名>`。
所以 `import "io.mo"` 会找到 `lib/io.mo`。

---

## 第 3 步：变量、函数与控制流（5 分钟）

```mo
import "io.mo";

fn fib(n: i64) -> i64 {
    if n < 2 {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

fn main() -> i64 {
    let i: i64 = 0;
    while i < 10 {
        print_i64(fib(i));
        print_nl();
        i += 1;
    }
    return 0;
}
```

要点：

- `let` 声明局部变量，`var` 声明全局变量
- 所有变量都要写类型（`i64` / `byte` / `ptr` / 数组 / 结构体）
- `if` 和 `while` 的花括号**不能省略**
- 支持 `break` / `continue`，只作用于最内层循环
- `i += 1` 等价于 `i = i + 1`，还有 `-=` `*=` `/=` `%=` `&=` `|=` `^=`
- 定义顺序无所谓：可以用了再定义，跨文件也行

---

## 第 4 步：数组与字符串（5 分钟）

```mo
import "io.mo";
import "str.mo";

var buf: [64] byte = 0;

fn main() -> i64 {
    # 数组
    let a: [5] i64;
    let i: i64 = 0;
    while i < 5 {
        a[i] = i * i;
        i += 1;
    }
    print_i64(a[3]);          # 9
    print_nl();

    # 字符串：类型是 ptr，逐字节访问
    let s: ptr = "hello";
    print_i64(strlen(s));     # 5
    print_nl();
    print_i64(s[1]);          # 101（'e'）
    print_nl();

    # 字符串可以直接下标
    print_i64("hello"[1]);    # 101
    print_nl();

    return 0;
}
```

**越界会被拦住**：`a[100]` 在运行时终止程序（退出码 1），
如果是常量下标则在**编译期**就报错。

字符字面量 `'a'` 的值就是字符编码，判断字符类别时不用背数字。

---

## 第 5 步：用标准库写一个真实工具（10 分钟）

我们来写 `wc`——统计行数、词数、字符数。

```mo
import "fs.mo";
import "io.mo";

var buf: [65536] byte = 0;

fn main() -> i64 {
    if argc() < 2 {
        print("usage: wc <file>\n");
        return 2;
    }
    let n: i64 = read_file(argv(1), &buf, 65536);
    if n < 0 {
        print("wc: cannot open\n");
        return 1;
    }
    let lines: i64 = 0;
    let words: i64 = 0;
    let inword: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let c: i64 = buf[i];
        if c == 10 { lines += 1; }
        if c == 32 || c == 10 || c == 9 {
            if inword == 1 { inword = 0; }
        } else {
            if inword == 0 { words += 1; inword = 1; }
        }
        i += 1;
    }
    print_i64(lines);
    print(" lines, ");
    print_i64(words);
    print(" words, ");
    print_i64(n);
    print(" chars\n");
    return 0;
}
```

运行：

```bash
./bin/moc wc.mo wc.elf && chmod +x wc.elf
printf 'hello mo world\nmo is a language\n' > demo.txt
./wc.elf demo.txt
# 2 lines, 7 words, 32 chars
```

注意 `read_file` 的第三个参数是缓冲区容量，**超过容量会失败返回 -1**——
这是当前没有动态扩容的直接后果，写工具时要自己估算。

---

## 第 6 步：动态数组（5 分钟）

固定容量不够用时，用 `vec`：

```mo
import "io.mo";
import "mem.mo";
import "vec.mo";

fn main() -> i64 {
    heap_init();
    let v: i64 = vec_new();

    let i: i64 = 0;
    while i < 1000 {
        vec_push(v, i * 2);
        i += 1;
    }

    print_i64(vec_len(v));    # 1000
    print_nl();
    print_i64(vec_get(v, 5)); # 10
    print_nl();
    return 0;
}
```

`vec` 能存任何 8 字节的值——整数或指针都行。
句柄内部是 {数据指针, 长度, 容量}，扩容时只重分配数据区、
句柄地址不变，所以可以随便传。

**注意**：`vec_get` 越界返回 0，不报错。要严格检查就先看 `vec_len`。

---

## 第 7 步：常见错误与排查

| 现象 | 原因 |
|---|---|
| `undefined symbol 'xxx'` | 没声明，或忘了 `import` |
| `cannot open import: xxx.mo` | 找不到文件，检查是不是该写 `lib/xxx.mo` |
| `missing return statement` | 函数末尾没写 `return` |
| `index out of bounds` | 下标越界。运行时是终止程序，编译期是报错 |
| `cannot assign to an array` | 数组不能整体赋值，要逐元素 |
| 程序结果不对但不报错 | 多半是缓冲区不够大，或越界读返回了 0 |

**调试**：加上 `-g` 编译，就能用 gdb 按源码行下断点：

```bash
./bin/moc prog.mo -g prog.elf
gdb ./prog.elf
(gdb) break prog.mo:10
```

---

## 下一步

- 完整语法与内建函数：看 `docs/language.md`
- 真实示例：`examples/` 下有 wc / grep / sort / freq 四个可直接编译运行的程序
- 想改编译器：看 `CONTRIBUTING.md`，尤其注意"改代码生成必须改两遍"那条规矩

---

## 一个提醒

墨语言目前只有整数类型，没有浮点和布尔（用 `i64` 的 0/1）。
字符串是 `ptr`，以 0 结尾，没有长度信息——所以 `p[i]` 不做越界检查。
这些不是疏漏，是 1.x 阶段有意的取舍。
