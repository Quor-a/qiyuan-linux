
# ==========================================================================
#  词法分析
# ==========================================================================
# 读取「当前文件」的第 i 个字节（支持 import 多文件）
fn sbyte(i: i64) -> i64 {
    return load8(heap + gv(K_SRCBASE) + i);
}

fn is_alpha(c: i64) -> i64 {
    if c >= 97 {
        if c <= 122 { return 1; }
    }
    if c >= 65 {
        if c <= 90 { return 1; }
    }
    return 0;
}

fn is_digit(c: i64) -> i64 {
    if c >= 48 {
        if c <= 57 { return 1; }
    }
    return 0;
}

fn is_alnum(c: i64) -> i64 {
    if is_alpha(c) == 1 { return 1; }
    if is_digit(c) == 1 { return 1; }
    if c == 95 { return 1; }
    return 0;
}

fn hexval(c: i64) -> i64 {
    if c >= 48 {
        if c <= 57 { return c - 48; }
    }
    if c >= 97 {
        if c <= 102 { return c - 87; }
    }
    if c >= 65 {
        if c <= 70 { return c - 55; }
    }
    return -1;
}

# 跳过空白与 '#' 注释，返回下一个有效字符位置
fn skip_comment(p: i64) -> i64 {
    let n: i64 = gv(K_SRCLEN);
    while p < n {
        if sbyte(p) == 10 { return p + 1; }
        p = p + 1;
    }
    return p;
}

fn skip_ws() -> i64 {
    let p: i64 = gv(K_POS);
    let n: i64 = gv(K_SRCLEN);
    while p < n {
        let c: i64 = sbyte(p);
        if c == 35 {
            p = skip_comment(p);
        } else {
            if c == 32 { p = p + 1; }
            else {
                if c == 9 { p = p + 1; }
                else {
                    if c == 10 { p = p + 1; }
                    else {
                        if c == 13 { p = p + 1; }
                        else { return p; }
                    }
                }
            }
        }
    }
    return p;
}

fn tokbuf() -> i64 {
    return heap + O_SCAL + K_TOKBUF;
}

fn lex_ident(p: i64) -> i64 {
    let i: i64 = 0;
    let b: i64 = tokbuf();
    while is_alnum(sbyte(p + i)) == 1 {
        store8(b + i, sbyte(p + i));
        i = i + 1;
    }
    store8(b + i, 0);
    sv(K_POS, p + i);
    sv(K_TKIND, 1);
    return 0;
}

fn lex_hex(p: i64) -> i64 {
    let v: i64 = 0;
    let h: i64 = hexval(sbyte(p));
    while h >= 0 {
        v = v * 16 + h;
        p = p + 1;
        h = hexval(sbyte(p));
    }
    sv(K_POS, p);
    sv(K_TKIND, 2);
    sv(K_TIVAL, v);
    store8(tokbuf(), 0);
    return 0;
}

fn lex_number(p: i64) -> i64 {
    if sbyte(p) == 48 {
        if sbyte(p + 1) == 120 { return lex_hex(p + 2); }
        if sbyte(p + 1) == 88 { return lex_hex(p + 2); }
    }
    let v: i64 = 0;
    while is_digit(sbyte(p)) == 1 {
        v = v * 10 + (sbyte(p) - 48);
        p = p + 1;
    }
    # 小数点 → f64 字面量（TKIND=5，TIVAL 存 IEEE754 位模式）
    if sbyte(p) == 46 {
        if is_digit(sbyte(p + 1)) == 1 {
            let q: i64 = p + 1;
            let fv: i64 = 0;
            let fd: i64 = 1;
            while is_digit(sbyte(q)) == 1 {
                fv = fv * 10 + (sbyte(q) - 48);
                fd = fd * 10;
                q = q + 1;
            }
            # 位模式 = f64(v + fv/fd)：用整数部分 exp + 小数逼近
            let bits: i64 = dtoi_f64(v, fv, fd, 0);
            p = q;
            sv(K_POS, p);
            sv(K_TKIND, 5);
            sv(K_TIVAL, bits);
            sv(K_TFVAL, bits);
            store8(tokbuf(), 0);
            return 0;
        }
    }
    sv(K_POS, p);
    sv(K_TKIND, 2);
    sv(K_TIVAL, v);
    store8(tokbuf(), 0);
    return 0;
}

# 整数+小数 → IEEE754 位模式（逐位长除法，避免 num<<52 溢出）
fn dtoi_f64(iv: i64, fv: i64, fd: i64, neg: i64) -> i64 {
    let num: i64 = iv * fd + fv;
    if num == 0 { return 0; }
    let e: i64 = 0;
    let den: i64 = 0;
    if num < fd {
        # 值 < 1：倍增 num 直至 [fd, 2fd)（value*2^j 归一到 [1,2)），E = -j
        # 此前直接走 t 循环会得到 den > num → r 为负 → 位模式垃圾（0.25 类全错）
        let j: i64 = 0;
        let n2: i64 = num;
        while n2 < fd {
            n2 = n2 * 2;
            j = j + 1;
        }
        e = 0 - j;
        den = fd;
        num = n2;
    } else {
        let t: i64 = fd;
        while t <= num {
            t = t * 2;
            e = e + 1;
        }
        e = e - 1;
        den = t / 2;
    }
    let r: i64 = num - den;
    let frac: i64 = 0;
    let k: i64 = 0;
    while k < 52 {
        r = r * 2;
        frac = frac * 2;
        if r >= den {
            r = r - den;
            frac = frac + 1;
        }
        k = k + 1;
    }
    if r * 2 >= den { frac = frac + 1; }
    if frac >= 4503599627370496 {
        frac = frac - 4503599627370496;
        e = e + 1;
    }
    let bits: i64 = (e + 1023) * 4503599627370496 + frac;
    if neg == 1 { bits = bits - 9223372036854775808; }
    return bits;
}
fn bits_frac52(v: i64) -> i64 { return v & 4503599627370495; }
fn bits_exp52(v: i64) -> i64 { return (v >> 52) & 2047; }
fn int_to_f64(n: i64) -> i64 {
    if n == 0 { return 0; }
    let e: i64 = 62;
    while e >= 0 {
        if (n >> e) & 1 == 1 { break; }
        e = e - 1;
    }
    let frac: i64 = 0;
    if e <= 52 {
        frac = (n - (1 << e)) << (52 - e);
    } else {
        frac = (n - (1 << e)) >> (e - 52);
    }
    return (e + 1023) * 4503599627370496 + frac;
}

# 字符串字面量：内容写入输出数据段（供生成的程序用），
# 同时拷贝一份到编译器侧字符串池 O_STRS（供编译器自身读取）
fn lex_string(p: i64) -> i64 {
    p = p + 1;
    let addr: i64 = 268435456 + gv(K_DLEN);
    let so: i64 = gv(K_NSTR);
    sv(K_STROFF, so);
    while sbyte(p) != 34 {
        let c: i64 = sbyte(p);
        if c == 92 {
            p = p + 1;
            c = sbyte(p);
            if c == 110 { c = 10; }
            else {
                if c == 116 { c = 9; }
                else {
                    if c == 114 { c = 13; }
                    else {
                        if c == 48 { c = 0; }
                    }
                }
            }
        }
        dbyte(c);
        store8(heap + O_STRS + so, c);
        so = so + 1;
        p = p + 1;
    }
    p = p + 1;
    dbyte(0);
    store8(heap + O_STRS + so, 0);
    so = so + 1;
    sv(K_NSTR, so);
    sv(K_POS, p);
    sv(K_TKIND, 3);
    sv(K_TIVAL, addr);
    store8(tokbuf(), 0);
    return 0;
}

# 当前字符串字面量在编译器侧的可读地址
fn strpool() -> i64 {
    return heap + O_STRS + gv(K_STROFF);
}

fn set_tok(a: i64, b: i64, adv: i64, p: i64) -> i64 {
    let t: i64 = tokbuf();
    store8(t, a);
    store8(t + 1, b);
    store8(t + 2, 0);
    sv(K_POS, p + adv);
    sv(K_TKIND, 4);
    return 0;
}

# 三字符 token（<<= >>=）。与 set_tok 同构，只是多写一个字节、多吃一个字符。
fn set_tok3(a: i64, b: i64, c: i64, p: i64) -> i64 {
    let t: i64 = tokbuf();
    store8(t, a);
    store8(t + 1, b);
    store8(t + 2, c);
    store8(t + 3, 0);
    sv(K_POS, p + 3);
    sv(K_TKIND, 4);
    return 0;
}

fn lex_punct(p: i64) -> i64 {
    let c: i64 = sbyte(p);
    let d: i64 = sbyte(p + 1);
    if c == 61 {
        if d == 61 { return set_tok(61, 61, 2, p); }
    }
    # 复合赋值：+= -= *= /= %= &= |= ^=
    # 必须比单字符更早匹配，否则 '+=' 会被当成 '+' 再跟一个 '='
    if c == 43 {
        if d == 61 { return set_tok(43, 61, 2, p); }
        if d == 43 { return set_tok(43, 43, 2, p); }
    }
    if c == 42 {
        if d == 61 { return set_tok(42, 61, 2, p); }
    }
    if c == 47 {
        if d == 61 { return set_tok(47, 61, 2, p); }
    }
    if c == 37 {
        if d == 61 { return set_tok(37, 61, 2, p); }
    }
    if c == 94 {
        if d == 61 { return set_tok(94, 61, 2, p); }
    }
    if c == 33 {
        if d == 61 { return set_tok(33, 61, 2, p); }
    }
    if c == 60 {
        # 三字符必须先试：'<' '<' '=' 若按两字符匹配会切成 "<<" + "="
        if d == 60 {
            if sbyte(p + 2) == 61 { return set_tok3(60, 60, 61, p); }
            return set_tok(60, 60, 2, p);
        }
        if d == 61 { return set_tok(60, 61, 2, p); }
    }
    if c == 62 {
        if d == 62 {
            if sbyte(p + 2) == 61 { return set_tok3(62, 62, 61, p); }
            return set_tok(62, 62, 2, p);
        }
        if d == 61 { return set_tok(62, 61, 2, p); }
    }
    if c == 38 {
        if d == 38 { return set_tok(38, 38, 2, p); }
        if d == 61 { return set_tok(38, 61, 2, p); }
    }
    if c == 124 {
        if d == 124 { return set_tok(124, 124, 2, p); }
        if d == 61 { return set_tok(124, 61, 2, p); }
    }
    if c == 45 {
        if d == 62 { return set_tok(45, 62, 2, p); }
        if d == 61 { return set_tok(45, 61, 2, p); }
        if d == 45 { return set_tok(45, 45, 2, p); }
    }
    return set_tok(c, 0, 1, p);
}

# 字符字面量 'a' / '\n' / '\\' / '\'' —— 值就是一个整数
fn lex_char(p: i64) -> i64 {
    p = p + 1;
    let c: i64 = sbyte(p);
    if c == 92 {
        p = p + 1;
        c = sbyte(p);
        if c == 110 { c = 10; }
        else {
            if c == 116 { c = 9; }
            else {
                if c == 114 { c = 13; }
                else {
                    if c == 48 { c = 0; }
                }
            }
        }
    }
    p = p + 1;
    # 允许但不强制闭合引号：吃掉它（存在就吃）
    if sbyte(p) == 39 { p = p + 1; }
    sv(K_POS, p);
    sv(K_TKIND, 2);
    sv(K_TIVAL, c);
    store8(tokbuf(), 0);
    return 0;
}

fn next_token() -> i64 {
    let p: i64 = skip_ws();
    sv(K_PLINE, gv(K_LINE));
    sv(K_PCOL, gv(K_COL));
    sv(K_PPOS, gv(K_TOKPOS));
    advance_lc(p);
    sv(K_POS, p);
    sv(K_TOKPOS, p);
    if p >= gv(K_SRCLEN) {
        sv(K_TKIND, 0);
        return 0;
    }
    let c: i64 = sbyte(p);
    if is_alpha(c) == 1 { return lex_ident(p); }
    if c == 95 { return lex_ident(p); }
    if is_digit(c) == 1 { return lex_number(p); }
    if c == 34 { return lex_string(p); }
    if c == 39 { return lex_char(p); }
    return lex_punct(p);
}

fn set_pos(p: i64) -> i64 {
    sv(K_POS, p);
    sv(K_CPOS, 0);
    sv(K_LINE, 1);
    sv(K_COL, 1);
    next_token();
    return 0;
}

fn tok_is(s: i64) -> i64 {
    if gv(K_TKIND) == 0 { return 0; }
    return streq(tokbuf(), s);
}

fn expect(s: i64) -> i64 {
    if tok_is(s) == 0 { return syntax_error(); }
    next_token();
    return 0;
}

fn accept(s: i64) -> i64 {
    if tok_is(s) == 0 { return 0; }
    next_token();
    return 1;
}
