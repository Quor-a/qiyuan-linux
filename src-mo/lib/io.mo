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

# f64 位模式 → 十进制打印（软件解析，无 SSE 依赖）
# 输出格式：整数部分.小数部分（默认 6 位，去尾零）
fn f64_parts(v: i64, out: i64) -> i64 {
    # 返回 out[0]=符号, out[1]=整数, out[2]=小数*1e6
    let sign: i64 = 0;
    if v < 0 { sign = 1; v = v + 9223372036854775808 + 9223372036854775808; }
    let e: i64 = ((v >> 52) & 2047) - 1023;
    let frac: i64 = v & 4503599627370495;
    if e == 1024 {
        store64(out, 2);          # inf/nan 标记
        return 0;
    }
    if e == -1023 {
        if frac == 0 { store64(out, 3); return 0; }   # 零
        e = -1022;                # 非规格化按规格化下限近似
    }
    let num: i64 = frac + 4503599627370496;   # 1.frac * 2^52
    # v = num * 2^(e-52)
    if e >= 52 {
        store64(out, sign);
        store64(out + 8, num << (e - 52));
        store64(out + 16, 0);
        return 0;
    }
    if e >= 0 {
        let ip: i64 = num >> (52 - e);
        store64(out, sign);
        store64(out + 8, ip);
        let fp: i64 = num - (ip << (52 - e));
        # fp/2^(52-e) * 1e6 —— 先移位降量级再乘，避免 i64 溢出
        let sh2: i64 = 52 - e;
        let f6: i64 = 0;
        # 丢 21 位乘 1e6 后四舍五入（误差 <0.5 个 1e-6 单位）
        if sh2 > 21 {
            f6 = ((fp >> 21) * 1000000 + (1 << (sh2 - 22))) / (1 << (sh2 - 21));
        } else {
            f6 = (fp << (21 - sh2)) * 1000000 >> 21;
        }
        # 999999.99 类四舍五入到 1000000 → 必须向整数部分进位
        if f6 >= 1000000 {
            f6 = f6 - 1000000;
            store64(out + 8, ip + 1);
        }
        store64(out + 16, f6);
        return 0;
    }
    # e < 0：v = num / 2^(52-e)
    let sh: i64 = 52 - e;
    if sh >= 63 {
        store64(out, sign);
        store64(out + 8, 0);
        store64(out + 16, 0);
        return 0;
    }
    store64(out, sign);
    store64(out + 8, 0);
    let f6b: i64 = 0;
    if sh > 21 {
        f6b = ((num >> 21) * 1000000 + (1 << (sh - 22))) / (1 << (sh - 21));
    } else {
        f6b = (num << (21 - sh)) * 1000000 >> 21;
    }
    if f6b >= 1000000 {
        f6b = f6b - 1000000;
        store64(out + 8, 1);
    }
    store64(out + 16, f6b);
    return 0;
}

var fpbuf: [3] i64 = 0;

fn print_f64(v: i64) -> i64 {
    f64_parts(v, &fpbuf);
    let kind: i64 = fpbuf[0];
    if kind == 2 { print("inf"); return 0; }
    if kind == 3 { print("0.0"); return 0; }
    if fpbuf[1] < 0 { fpbuf[1] = 0 - fpbuf[1]; }
    let fd: i64 = fpbuf[2];
    if fd >= 1000000 {
        fd = fd - 1000000;
        fpbuf[1] = fpbuf[1] + 1;
    }
    if kind == 1 { print("-"); }
    print_i64(fpbuf[1]);
    if fd != 0 {
        let db: [8] i64 = 0;
        let i: i64 = 6;
        while i > 0 {
            i = i - 1;
            store8(&db + i, 48 + (fd % 10));
            fd = fd / 10;
        }
        let n: i64 = 6;
        while n > 1 {
            if load8(&db + n - 1) != 48 { break; }
            n = n - 1;
        }
        print(".");
        syscall(1, 1, &db, n, 0, 0, 0);
    }
    return 0;
}
# 旧版留档（局部数组不可靠，见 qyps/qycp 教训）
fn print_f64_old_unused(v: i64) -> i64 {
    let p: [3] i64 = 0;
    f64_parts(v, &p);
    let kind: i64 = p[0];
    if kind == 2 { print("inf"); return 0; }
    if kind == 3 { print("0.0"); return 0; }
    if p[1] < 0 { p[1] = 0 - p[1]; }
    if kind == 1 { print("-"); }
    print_i64(p[1]);
    # 小数 6 位去尾零
    let fd: i64 = p[2];
    if fd != 0 {
        let db: [8] i64 = 0;
        let i: i64 = 6;
        while i > 0 {
            i = i - 1;
            store8(&db + i, 48 + (fd % 10));
            fd = fd / 10;
        }
        i = 6;
        while i > 1 {
            if load8(&db + i - 1) != 48 { i = 0; } else { i = i - 1; }
        }
        print(".");
        syscall(1, 1, &db, i, 0, 0, 0);
    }
    return 0;
}
