import "str.mo";

fn print(s: i64) -> i64 {
    syscall(1, 1, s, strlen(s), 0, 0, 0);
    return 0;
}

fn print_i64(v: i64) -> i64 {
    let buf: [24] i64 = 0;
    let i: i64 = 22;
    let neg: i64 = 0;
    if v < 0 {
        neg = 1;
        v = 0 - v;
    }
    if v == 0 {
        store8(&buf, 48);
        syscall(1, 1, &buf, 1, 0, 0, 0);
        return 0;
    }
    while v > 0 {
        store8(&buf + i, 48 + (v % 10));
        v = v / 10;
        i = i - 1;
    }
    if neg == 1 {
        store8(&buf + i, 45);
        i = i - 1;
    }
    syscall(1, 1, &buf + i + 1, 22 - i, 0, 0, 0);
    return 0;
}

fn print_nl() -> i64 {
    print("\n");
    return 0;
}

# 把无符号数按 base 进制写入 buf，返回字符串长度（不输出）
fn utoa(v: i64, buf: i64, base: i64) -> i64 {
    let tmp: [24] i64 = 0;
    let n: i64 = 0;
    let neg: i64 = 0;
    # 负数：先输出 '-' 再按绝对值转换。
    # 原来直接 while v > 0，负数一律走空循环，结果输出空串。
    if v < 0 {
        neg = 1;
        store8(buf, 45);
        v = 0 - v;
    }
    if v == 0 {
        store8(buf + neg, 48);
        store8(buf + neg + 1, 0);
        return neg + 1;
    }
    while v > 0 {
        let d: i64 = v % base;
        if d < 10 {
            store8(&tmp + n, 48 + d);
        } else {
            store8(&tmp + n, 87 + d);
        }
        v = v / base;
        n = n + 1;
    }
    let i: i64 = 0;
    while i < n {
        store8(buf + neg + i, load8(&tmp + (n - 1 - i)));
        i = i + 1;
    }
    store8(buf + neg + n, 0);
    return neg + n;
}

fn print_hex(v: i64) -> i64 {
    let buf: [24] i64 = 0;
    utoa(v, &buf, 16);
    print(&buf);
    return 0;
}
