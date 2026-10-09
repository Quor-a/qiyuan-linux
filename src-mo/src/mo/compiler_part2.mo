
# ==========================================================================
#  x86-64 指令发射
# ==========================================================================
fn ops2(a: i64, b: i64) -> i64 {
    emit1(a);
    emit1(b);
    return 0;
}

fn ops3(a: i64, b: i64, c: i64) -> i64 {
    emit1(a);
    emit1(b);
    emit1(c);
    return 0;
}

fn ops4(a: i64, b: i64, c: i64, d: i64) -> i64 {
    emit1(a);
    emit1(b);
    emit1(c);
    emit1(d);
    return 0;
}

# mov rax, imm
#   小常量（0 <= v < 2^32）用 mov eax, imm32（B8 imm32，5 字节）
#   而不是 movabs rax, imm64（48 B8 imm64，10 字节）——省 5 字节
#   注意：需要 8 字节回填的调用点走 emit_call_patch，不走这里
# ============ 调试信息缓冲（-g 专用）============
# 所有 debug section 共用 O_DBG，用 K_DBBASE 区分段落。
# 不开启 -g 时这些函数完全不会被调用。

fn store32(p: i64, v: i64) -> i64 {
    store8(p, v & 255);
    store8(p + 1, (v / 256) & 255);
    store8(p + 2, (v / 65536) & 255);
    store8(p + 3, (v / 16777216) & 255);
    return 0;
}

fn store16(p: i64, v: i64) -> i64 {
    store8(p, v & 255);
    store8(p + 1, (v / 256) & 255);
    return 0;
}

# 注意：store8 的实参里不能再嵌 gv(K_DBBASE) 之类的函数调用。
# 编译器用同一个缓冲区存「当前被调函数名」，实参里的嵌套调用会把它覆盖掉，
# 于是外层的 store8 变成去调别的函数（踩过，现象是写进来的全是 0）。
# 规矩：内建函数调用的实参必须是常量或局部变量。
fn db_u8(b: i64) -> i64 {
    let n: i64 = gv(K_DBGLEN);
    let bs: i64 = gv(K_DBBASE);
    store8(DBG + O_DBG + bs + n, b);
    sv(K_DBGLEN, n + 1);
    return 0;
}

fn db_u16(v: i64) -> i64 {
    db_u8(v & 255);
    db_u8((v / 256) & 255);
    return 0;
}

fn db_u32(v: i64) -> i64 {
    db_u8(v & 255);
    db_u8((v / 256) & 255);
    db_u8((v / 65536) & 255);
    db_u8((v / 16777216) & 255);
    return 0;
}

fn db_u64(v: i64) -> i64 {
    let i: i64 = 0;
    while i < 8 {
        db_u8((v / (1 << (i * 8))) & 255);
        i = i + 1;
    }
    return 0;
}

# 回填：把 v 写到当前段落的偏移 p 处（unit_length 要先占位后填）
fn db_poke32(p: i64, v: i64) -> i64 {
    let bs: i64 = gv(K_DBBASE);
    let b: i64 = DBG + O_DBG + bs;
    store8(b + p, v & 255);
    store8(b + p + 1, (v / 256) & 255);
    store8(b + p + 2, (v / 65536) & 255);
    store8(b + p + 3, (v / 16777216) & 255);
    return 0;
}

# ULEB128：只用于非负数（地址、长度、文件号）
fn db_uleb(v: i64) -> i64 {
    while v > 127 {
        db_u8((v & 127) | 128);
        v = v / 128;
    }
    db_u8(v & 255);
    return 0;
}

# SLEB128：行号增量可正可负
fn db_sleb(v: i64) -> i64 {
    while 1 {
        let b: i64 = v & 127;
        v = v / 128;
        if v == 0 {
            if (b & 64) == 0 {
                db_u8(b);
                return 0;
            }
        } else {
            if v == 0 - 1 {
                if (b & 64) != 0 {
                    db_u8(b);
                    return 0;
                }
            }
        }
        db_u8(b | 128);
    }
    return 0;
}

fn db_str(s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        db_u8(load8(s + i));
        i = i + 1;
    }
    db_u8(0);
    return 0;
}

fn g_movabs_rax(v: i64) -> i64 {
    if v < 0 {
        ops2(0x48, 0xb8);
        emit8(v);
        # 8 字节形式不进折叠缓存：K_LASTR 是 32 位形式的陈旧长度，
        # f64 位模式（大数/负数）会令 try_fold_rhs 回退出错误长度
        sv(K_LAST, 0);
        return 0;
    }
    if v > 4294967295 {
        ops2(0x48, 0xb8);
        emit8(v);
        sv(K_LAST, 0);
        return 0;
    }
    emit1(0xb8);
    emit4(v);
    sv(K_LAST, 1);
    sv(K_LASTV, v);
    sv(K_LASTR, 5);
    return 0;
}

fn g_movabs_r11(v: i64) -> i64 {
    ops2(0x49, 0xbb);
    emit8(v);
    return 0;
}

# 局部量一律以 [rbp+off] 寻址。off 落在 -128..127 时用 disp8 编码（4 字节），
# 否则退回 disp32（7 字节）。函数帧很大时才走 disp32 分支。
fn g_load_local(off: i64) -> i64 {
    if off < -128 { ops3(0x48, 0x8b, 0x85); emit4(off); sv(K_LAST, 2); sv(K_LASTV, off); sv(K_LASTR, 7); return 0; }
    if off > 127 { ops3(0x48, 0x8b, 0x85); emit4(off); sv(K_LAST, 2); sv(K_LASTV, off); sv(K_LASTR, 7); return 0; }
    ops2(0x48, 0x8b);
    emit1(0x45);
    emit1(off & 255);
    sv(K_LAST, 2);
    sv(K_LASTV, off);
    sv(K_LASTR, 4);
    return 0;
}

fn g_store_local(off: i64) -> i64 {
    if off < -128 { ops3(0x48, 0x89, 0x85); emit4(off); return 0; }
    if off > 127 { ops3(0x48, 0x89, 0x85); emit4(off); return 0; }
    ops2(0x48, 0x89);
    emit1(0x45);
    emit1(off & 255);
    return 0;
}

# lea rax, [rbp+off]  —— 取局部量（含数组基址）的地址
# ---- 结构体整体拷贝原语 ----
fn g_lea_rsi_local(off: i64) -> i64 {
    ops2(0x48, 0x8d);
    emit1(0x75);
    emit1(off & 255);
    return 0;
}
fn g_movabs_rsi(a: i64) -> i64 { ops2(0x48, 0xbe); emit8(a); return 0; }
fn g_rbx_from_rsi() -> i64 { ops3(0x48, 0x8b, 0x1e); return 0; }
fn g_rbx_to_rax() -> i64 { ops3(0x48, 0x89, 0x18); return 0; }
fn g_add_rax8() -> i64 { ops3(0x48, 0x83, 0xc0); emit1(8); return 0; }
fn g_add_rsi8() -> i64 { ops3(0x48, 0x83, 0xc6); emit1(8); return 0; }
fn g_addr_sym_rax(s: i64) -> i64 {
    if sym_kind(s) == 1 { return g_lea_local(sym_addr(s)); }
    return g_movabs_rax(sym_addr(s));
}
fn g_addr_sym_rsi(s: i64) -> i64 {
    if sym_kind(s) == 1 { return g_lea_rsi_local(sym_addr(s)); }
    return g_movabs_rsi(sym_addr(s));
}
fn g_copy_words(n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        g_rbx_from_rsi();
        g_rbx_to_rax();
        if i < n - 1 { g_add_rax8(); g_add_rsi8(); }
        i = i + 1;
    }
    return 0;
}
fn g_lea_local(off: i64) -> i64 {
    if off < -128 { ops3(0x48, 0x8d, 0x85); emit4(off); return 0; }
    if off > 127 { ops3(0x48, 0x8d, 0x85); emit4(off); return 0; }
    ops2(0x48, 0x8d);
    emit1(0x45);
    emit1(off & 255);
    return 0;
}

# mov rax, [rax]
# 按 1 字节加载并零扩展：movzx eax, byte [rax]
fn g_load_at_b() -> i64 {
    ops2(0x0f, 0xb6);
    emit1(0x00);
    sv(K_LAST, 0);
    return 0;
}
# 只写低 1 字节：mov byte [rcx], al
fn g_store_at_b() -> i64 {
    ops2(0x88, 0x01);
    return 0;
}
fn g_load_at() -> i64 {
    ops3(0x48, 0x8b, 0x00);
    return 0;
}

# mov [rcx], rax
fn g_store_at() -> i64 {
    ops3(0x48, 0x89, 0x01);
    return 0;
}

# shl rax, 3  —— 下标换算成字节偏移
fn g_shl3() -> i64 {
    ops3(0x48, 0xc1, 0xe0);
    emit1(3);
    return 0;
}

# 判断 v 是否为 2 的幂，是则返回 log2(v)，否则返回 -1
fn log2p2(v: i64) -> i64 {
    if v <= 0 { return -1; }
    let s: i64 = 0;
    let x: i64 = v;
    while x > 1 {
        if (x & 1) == 1 { return -1; }
        x = x / 2;
        s = s + 1;
    }
    return s;
}

# rax *= v。v 是 2 的幂时改用 shl（4 字节，比 imul 的 6 字节短），
# v == 1 时什么都不发。数组/结构体下标换算几乎总落在 8 或 16 上。
fn g_mul_imm(v: i64) -> i64 {
    let s: i64 = log2p2(v);
    if s == 0 { return 0; }
    if s > 0 {
        ops3(0x48, 0xc1, 0xe0);
        emit1(s);
        return 0;
    }
    ops3(0x48, 0x69, 0xc0);
    emit4(v);
    return 0;
}

# ---- byte 宽度（1 字节）的加载 / 存储 ----
# byte 变量本身仍占 8 字节（栈帧与数据段布局不变），
# 只有读写指令的宽度是 1 字节：加载零扩展，存储截断到低 8 位。
fn g_load_local_b(off: i64) -> i64 {
    if off < -128 { ops2(0x0f, 0xb6); emit1(0x85); emit4(off); sv(K_LAST, 0); return 0; }
    if off > 127 { ops2(0x0f, 0xb6); emit1(0x85); emit4(off); sv(K_LAST, 0); return 0; }
    ops2(0x0f, 0xb6);
    emit1(0x45);
    emit1(off & 255);
    sv(K_LAST, 0);
    return 0;
}
fn g_store_local_b(off: i64) -> i64 {
    if off < -128 { emit1(0x88); emit1(0x85); emit4(off); return 0; }
    if off > 127 { emit1(0x88); emit1(0x85); emit4(off); return 0; }
    emit1(0x88);
    emit1(0x45);
    emit1(off & 255);
    return 0;
}

fn g_load_global(a: i64) -> i64 {
    g_movabs_r11(a);
    ops3(0x49, 0x8b, 0x03);
    return 0;
}

fn g_store_global(a: i64) -> i64 {
    g_movabs_r11(a);
    ops3(0x49, 0x89, 0x03);
    return 0;
}
fn g_load_global_b(a: i64) -> i64 {
    g_movabs_r11(a);
    ops3(0x49, 0x0f, 0xb6);
    emit1(0x03);
    sv(K_LAST, 0);
    return 0;
}
fn g_store_global_b(a: i64) -> i64 {
    g_movabs_r11(a);
    ops3(0x49, 0x88, 0x03);
    return 0;
}

# 按符号的实际类型选择读写宽度。byte 用 1 字节指令，其余仍按 8 字节。
fn load_sym(s: i64) -> i64 {
    store64(heap + O_SU + s * 8, 1);
    if ty_kind(sym_type(s)) == 5 {
        if sym_kind(s) == 1 { return g_load_local_b(sym_addr(s)); }
        return g_load_global_b(sym_addr(s));
    }
    if sym_kind(s) == 1 { return g_load_local(sym_addr(s)); }
    return g_load_global(sym_addr(s));
}

fn store_sym(s: i64) -> i64 {
    store64(heap + O_SU + s * 8, 1);
    if ty_kind(sym_type(s)) == 5 {
        if sym_kind(s) == 1 { return g_store_local_b(sym_addr(s)); }
        return g_store_global_b(sym_addr(s));
    }
    if sym_kind(s) == 1 { return g_store_local(sym_addr(s)); }
    return g_store_global(sym_addr(s));
}

# push rax。若 rax 里的值刚由「常量加载」或「局部量加载」产生，
# 就回退那条指令、直接 push 源操作数，省掉一次中转。
# ============ 栈顶缓存 ============
# 二元运算的左右操作数靠 push/pop 传递，每次都是两次内存访问。
# rbx 在 SysV ABI 里是 callee-saved，而被我们生成的代码不使用，
# 于是可以拿它缓存「最后一次 push」的值，把 push/pop 换成寄存器传送。
#
# 不变式：K_CRBX == 1  <=>  最后一次 push 的值在 rbx 里。
# 要维持它，任何新的 push 都必须先 spill（把 rbx 里的旧值落栈）。
# 于是栈序天然正确：先 pop 的一定是最后 push 的那个。
fn spill_cache() -> i64 {
    if gv(K_CRBX) == 1 {
        emit1(0x53);          # push rbx
        sv(K_CRBX, 0);
    }
    return 0;
}

# 用 rbx 缓存 rax 里的值（代替 push rax）
fn g_cache_rbx() -> i64 {
    emit1(0x48);
    emit1(0x89);
    emit1(0xc3);              # mov rbx, rax
    sv(K_CRBX, 1);
    return 0;
}

fn g_push_rax() -> i64 {
    let k: i64 = gv(K_LAST);
    sv(K_LAST, 0);
    # 注意：spill 必须放在「回退字节」之后。
    # 折叠路径要回退刚发的常量加载（LASTR 字节），若先 spill 再回退，
    # 回退掉的会是 push rbx + 常量加载的后半段 —— 指令直接错位。
    # 所以每条路径各自在回退之后再 spill。
    if k == 1 {
        let v: i64 = gv(K_LASTV);
        if v >= 0 {
            if v <= 127 {
                sv(K_CLEN, gv(K_CLEN) - gv(K_LASTR));
                spill_cache();
                emit1(0x6a);
                emit1(v & 255);
                return 0;
            }
            # push imm32 会符号扩展；v >= 2^31 时与 mov eax,imm32（零扩展）不等价
            if v <= 2147483647 {
                sv(K_CLEN, gv(K_CLEN) - gv(K_LASTR));
                spill_cache();
                emit1(0x68);
                emit4(v);
                return 0;
            }
        }
        spill_cache();
        g_cache_rbx();
        return 0;
    }
    if k == 2 {
        let off: i64 = gv(K_LASTV);
        sv(K_CLEN, gv(K_CLEN) - gv(K_LASTR));
        spill_cache();
        if off >= -128 {
            if off <= 127 {
                emit1(0xff);
                emit1(0x75);
                emit1(off & 255);
                return 0;
            }
        }
        emit1(0xff);
        emit1(0xb5);
        emit4(off);
        return 0;
    }
    spill_cache();
    g_cache_rbx();
    return 0;
}
fn g_pop_rax() -> i64 { spill_cache(); emit1(0x58); return 0; }
fn g_pop_rbx() -> i64 { spill_cache(); emit1(0x5b); return 0; }
# pop rcx。rcx 拿到左操作数后 rax 仍持有右操作数，
# 所以这里记下「右操作数是不是编译期常量」，供随后的运算指令折叠用。
fn g_pop_rcx() -> i64 {
    if gv(K_CRBX) == 1 {
        sv(K_CRBX, 0);
        sv(K_PL, 0);
        emit1(0x48);
        emit1(0x89);
        emit1(0xd9);          # mov rcx, rbx
        return 0;
    }
    if gv(K_LAST) == 1 {
        sv(K_PL, 1);
        sv(K_PLV, gv(K_LASTV));
        sv(K_PLR, gv(K_LASTR));
    } else {
        sv(K_PL, 0);
    }
    emit1(0x59);
    return 0;
}

# 右操作数是常量时，回退它的 mov eax,imm32（紧接着的 pop rcx 由调用方重发）。
# 返回 1 表示已回退，常量值在 K_PLV；返回 0 表示照旧。
# 上限 2^31-1：立即数形式会做符号扩展，超过就与 mov eax,imm32 的零扩展不等价。
fn try_fold_rhs() -> i64 {
    if gv(K_PL) == 0 { return 0; }
    if gv(K_PLV) > 2147483647 { sv(K_PL, 0); return 0; }
    sv(K_PL, 0);
    # 回退「常量加载 + 紧随其后的 pop rcx」；调用方会重发所需的 pop
    sv(K_CLEN, gv(K_CLEN) - gv(K_PLR) - 1);
    return 1;
}

# rax <op>= imm（Group1 形状：imm8 用 83 /reg，imm32 用独立操作码）
fn g_imm_g1(m8: i64, op32: i64) -> i64 {
    let v: i64 = gv(K_PLV);
    if v <= 127 {
        ops3(0x48, 0x83, m8);
        emit1(v & 255);
        return 0;
    }
    ops2(0x48, op32);
    emit4(v);
    return 0;
}
fn g_pop_rdx() -> i64 { spill_cache(); emit1(0x5a); return 0; }
fn g_pop_rsi() -> i64 { spill_cache(); emit1(0x5e); return 0; }
fn g_pop_rdi() -> i64 { spill_cache(); emit1(0x5f); return 0; }
fn g_pop_r10() -> i64 { spill_cache(); ops2(0x41, 0x5a); return 0; }
fn g_pop_r8() -> i64 { spill_cache(); ops2(0x41, 0x58); return 0; }
fn g_pop_r9() -> i64 { spill_cache(); ops2(0x41, 0x59); return 0; }

fn g_mov_rbx_rax() -> i64 { ops3(0x48, 0x89, 0xc3); return 0; }
fn g_mov_rax_rcx() -> i64 { ops3(0x48, 0x89, 0xc8); return 0; }
fn g_mov_rcx_rbx() -> i64 { ops3(0x48, 0x89, 0xd9); return 0; }
fn g_mov_rax_rdx() -> i64 { ops3(0x48, 0x89, 0xd0); return 0; }

fn g_add() -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x58);
        g_imm_g1(0xc0, 0x05);
        return 0;
    }
    ops3(0x48, 0x01, 0xc8);
    return 0;
}
fn g_and() -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x58);
        g_imm_g1(0xe0, 0x25);
        return 0;
    }
    ops3(0x48, 0x21, 0xc8);
    return 0;
}
fn g_or() -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x58);
        g_imm_g1(0xc8, 0x0d);
        return 0;
    }
    ops3(0x48, 0x09, 0xc8);
    return 0;
}
fn g_xor() -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x58);
        g_imm_g1(0xf0, 0x35);
        return 0;
    }
    ops3(0x48, 0x31, 0xc8);
    return 0;
}
fn g_imul() -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x58);
        let v: i64 = gv(K_PLV);
        if v <= 127 {
            ops3(0x48, 0x6b, 0xc0);
            emit1(v & 255);
            return 0;
        }
        ops3(0x48, 0x69, 0xc0);
        emit4(v);
        return 0;
    }
    ops4(0x48, 0x0f, 0xaf, 0xc1);
    return 0;
}
fn g_neg() -> i64 { ops3(0x48, 0xf7, 0xd8); return 0; }
fn g_not() -> i64 { ops3(0x48, 0xf7, 0xd0); return 0; }
fn g_syscall() -> i64 { ops2(0x0f, 0x05); return 0; }

# rax = rcx - rax
fn g_sub() -> i64 {
    ops3(0x48, 0x29, 0xc1);
    g_mov_rax_rcx();
    return 0;
}

# rax = rcx / rax ; rax = rcx % rax
fn g_idiv(mode: i64) -> i64 {
    # 除法用 rbx 当除数，必须先让缓存落栈，否则左操作数就丢了
    spill_cache();
    g_mov_rbx_rax();
    g_mov_rax_rcx();
    ops2(0x48, 0x99);
    ops3(0x48, 0xf7, 0xfb);
    if mode == 1 {
        g_mov_rax_rdx();
    }
    return 0;
}

fn g_shl() -> i64 {
    g_mov_rbx_rax();
    g_mov_rax_rcx();
    g_mov_rcx_rbx();
    ops3(0x48, 0xd3, 0xe0);
    return 0;
}

fn g_sar() -> i64 {
    g_mov_rbx_rax();
    g_mov_rax_rcx();
    g_mov_rcx_rbx();
    ops3(0x48, 0xd3, 0xf8);
    return 0;
}

# 比较 rcx 与 rax，结果 0/1 放 rax
fn g_setcc(cc: i64) -> i64 {
    ops2(0x0f, cc);
    emit1(0xc0);
    ops4(0x48, 0x0f, 0xb6, 0xc0);
    return 0;
}

# 比较 rcx（左）与 rax（右）。右操作数是常量时直接用 cmp rcx, imm
# —— 标志位语义与 cmp rcx,rax 完全一致（都是 left - right），可以放心换。
fn g_cmp_set(cc: i64) -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x59);
        let v: i64 = gv(K_PLV);
        if v <= 127 {
            ops3(0x48, 0x83, 0xf9);
            emit1(v & 255);
            g_setcc(cc);
            return 0;
        }
        ops3(0x48, 0x81, 0xf9);
        emit4(v);
        g_setcc(cc);
        return 0;
    }
    ops3(0x48, 0x39, 0xc1);
    g_setcc(cc);
    return 0;
}

fn g_cmp_rax_0() -> i64 {
    ops4(0x48, 0x83, 0xf8, 0x00);
    return 0;
}

fn g_lnot() -> i64 {
    g_cmp_rax_0();
    ops3(0x0f, 0x94, 0xc0);
    ops4(0x48, 0x0f, 0xb6, 0xc0);
    return 0;
}

fn g_zero_rax() -> i64 { ops2(0x31, 0xc0); return 0; }

fn g_epilogue() -> i64 {
    ops3(0x48, 0x89, 0xec);
    ops2(0x5d, 0xc3);
    return 0;
}

fn g_prologue() -> i64 {
    ops3(0x55, 0x48, 0x89);
    emit1(0xe5);
    ops3(0x48, 0x81, 0xec);
    sv(K_FPATCH, gv(K_CLEN));
    emit4(0);
    return 0;
}

# mov [rbp+off], <argreg i>
# 把第 i 个参数存到 [rbp+off]。
# 前 6 个参数走寄存器；第 7 个起由调用者压栈，需从栈上取。
# 调用方按正序压栈（arg0 先压），故 arg[i] 落在 [rbp + 16 + (na-1-i)*8]。
# 原先只有 6 个寄存器的分支，i>=6 时会越界取到垃圾字节——
# 表现为函数序言里冒出一条 jne（0x75），程序一跑就段错误。
fn emit_store_arg(off: i64, i: i64, na: i64) -> i64 {
    if i >= 6 {
        let d: i64 = 16 + (na - 1 - i) * 8;
        ops2(0x48, 0x8b);
        if d > 127 {
            emit1(0x85);
            emit4(d);
        } else {
            emit1(0x45);
            emit1(d & 255);
        }
        ops2(0x48, 0x89);
        if off < -128 {
            emit1(0x85);
            emit4(off);
        } else {
            emit1(0x45);
            emit1(off & 255);
        }
        return 0;
    }
    if i == 0 { ops3(0x48, 0x89, 0x7d); emit1(off); return 0; }
    if i == 1 { ops3(0x48, 0x89, 0x75); emit1(off); return 0; }
    if i == 2 { ops3(0x48, 0x89, 0x55); emit1(off); return 0; }
    if i == 3 { ops3(0x48, 0x89, 0x4d); emit1(off); return 0; }
    if i == 4 { ops3(0x4c, 0x89, 0x45); emit1(off); return 0; }
    ops3(0x4c, 0x89, 0x4d);
    emit1(off);
    return 0;
}

# movabs rax, <addr>; call rax  并记录回填
fn emit_call_patch(sym: i64) -> i64 {
    ops2(0x48, 0xb8);
    let k: i64 = gv(K_NFNP);
    if k >= 16384 { return die("too many call sites (limit 16384)"); }
    store64(heap + O_FP + k * 8, gv(K_CLEN));
    store64(heap + O_FS + k * 8, sym);
    sv(K_NFNP, k + 1);
    emit8(0);
    # 调用前必须先落栈：被调函数里的 push 会 spill 调用者缓存在 rbx 里的值，
    # 把它压进被调函数的栈帧，调用者返回后取回的就是错的
    spill_cache();
    ops2(0xff, 0xd0);
    return 0;
}

# ---------------------------- 标签与跳转 ----------------------------
fn new_label() -> i64 {
    let k: i64 = gv(K_NLAB);
    if k >= 4096 { return die("too many labels (limit 4096)"); }
    sv(K_NLAB, k + 1);
    return k;
}

# 放置标签。若上一条指令是无条件 jmp 且它跳的正是这里、中间又没夹任何字节，
# 那这条 jmp 是死跳转（跳到下一条指令），整条删掉——省 5 字节。
# `if` 没有 else 分支时正是这种情况：jmp end 之后紧跟着就是 end 标签。
fn place_label(l: i64) -> i64 {
    let pj: i64 = gv(K_PJMP);
    if pj > 0 {
        if gv(K_PJLBL) == l {
            if gv(K_CLEN) == gv(K_PJEND) {
                let old: i64 = gv(K_PJEND);
                let nw: i64 = old - 5;
                sv(K_CLEN, nw);
                sv(K_NJMP, pj - 1);
                sv(K_PJMP, 0);
                # 已经落在 old 处的标签（典型的是 if 的 else 标签，它
                # 比 end 早一步放置）必须跟着回退。否则它们仍指向
                # 被删掉那 5 字节之后——跳进下一段指令的中间。
                let i: i64 = 0;
                let nn: i64 = gv(K_NLAB);
                while i < nn {
                    if load64(heap + O_LB + i * 8) == old {
                        store64(heap + O_LB + i * 8, nw);
                    }
                    i = i + 1;
                }
            }
        }
    }
    store64(heap + O_LB + l * 8, gv(K_CLEN));
    return 0;
}

# ---------------------------- 循环标签栈 ----------------------------
# break/continue 要跳到「当前所在的那一层循环」。嵌套循环时靠栈记住
# 每层的 continue 标签（循环头）与 break 标签（循环出口）。
# 存在 O_LB 之后的区域，最多 32 层。
var O_LSTK: i64 = 7417360;

fn loop_push(cnt: i64, brk: i64, stp: i64) -> i64 {
    let i: i64 = gv(K_LTOP);
    store64(heap + O_LSTK + i * 24, cnt);
    store64(heap + O_LSTK + i * 24 + 8, brk);
    store64(heap + O_LSTK + i * 24 + 16, stp);
    sv(K_LTOP, i + 1);
    return 0;
}

fn loop_pop() -> i64 {
    sv(K_LTOP, gv(K_LTOP) - 1);
    return 0;
}

# 取当前循环的 continue / break 标签；不在循环里返回 -1
fn loop_cnt() -> i64 {
    let i: i64 = gv(K_LTOP);
    if i <= 0 { return -1; }
    return load64(heap + O_LSTK + (i - 1) * 24);
}

# for 的步进标签；while 为 -1（表示 continue 直接跳循环头）
fn loop_stp() -> i64 {
    let i: i64 = gv(K_LTOP);
    if i <= 0 { return -1; }
    return load64(heap + O_LSTK + (i - 1) * 24 + 16);
}

fn loop_brk() -> i64 {
    let i: i64 = gv(K_LTOP);
    if i <= 0 { return -1; }
    return load64(heap + O_LSTK + (i - 1) * 24 + 8);
}

fn emit_jcc(cc: i64, l: i64) -> i64 {
    ops2(0x0f, cc);
    let k: i64 = gv(K_NJMP);
    store64(heap + O_JP + k * 8, gv(K_CLEN));
    store64(heap + O_JL + k * 8, l);
    sv(K_NJMP, k + 1);
    emit4(0);
    return 0;
}

fn emit_jmp(l: i64) -> i64 {
    emit1(0xe9);
    let k: i64 = gv(K_NJMP);
    store64(heap + O_JP + k * 8, gv(K_CLEN));
    store64(heap + O_JL + k * 8, l);
    sv(K_NJMP, k + 1);
    emit4(0);
    # 记下这条 jmp，供 place_label 判断是否为死跳转。
    # 必须在 emit4 之后设置——emit1/emit4 会清标记。
    sv(K_PJMP, k + 1);
    sv(K_PJLBL, l);
    sv(K_PJEND, gv(K_CLEN));
    return 0;
}

# ============================ f64 / SSE ============================
# 约定：f64 值以 64 位模式经 rax 传递；二元运算左操作数在 rcx。

fn g_movq_rcx_xmm0() -> i64 { ops4(0x66, 0x48, 0x0f, 0x6e); emit1(0xc1); return 0; }
fn g_movq_rax_xmm1() -> i64 { ops4(0x66, 0x48, 0x0f, 0x6e); emit1(0xc8); return 0; }
fn g_movq_xmm0_rax() -> i64 { ops4(0x66, 0x48, 0x0f, 0x7e); emit1(0xc0); return 0; }
fn g_addsd()  -> i64 { ops4(0xf2, 0x0f, 0x58, 0xc1); return 0; }
fn g_subsd()  -> i64 { ops4(0xf2, 0x0f, 0x5c, 0xc1); return 0; }
fn g_mulsd()  -> i64 { ops4(0xf2, 0x0f, 0x59, 0xc1); return 0; }
fn g_divsd()  -> i64 { ops4(0xf2, 0x0f, 0x5e, 0xc1); return 0; }
# int(rcx) → xmm0 双精度
fn g_cvtsi2sd_rcx() -> i64 { ops4(0xf2, 0x48, 0x0f, 0x2a); emit1(0xc1); return 0; }
# xmm0 → rax 位模式
fn g_cvtsd2si() -> i64 { ops4(0xf2, 0x48, 0x0f, 0x2c); emit1(0xc0); return 0; }

# rax = f64(rcx) op f64(rax)
fn g_fop(op: i64) -> i64 {
    spill_cache();
    g_movq_rcx_xmm0();
    g_movq_rax_xmm1();
    if op == 0 { g_addsd(); }
    if op == 1 { g_subsd(); }
    if op == 2 { g_mulsd(); }
    if op == 3 { g_divsd(); }
    g_movq_xmm0_rax();
    return 0;
}

# 混合 int/f64 提升：任一侧 f64 → 都转 f64
# 返回 1 = 本运算按 f64 做（结果在 rax 为位模式）
fn f_bin_promote(lt: i64, rt: i64) -> i64 {
    if ty_kind(lt) == 6 { return 1; }
    if ty_kind(rt) == 6 { return 1; }
    return 0;
}

# rcx 中的值按类型 lt 进入 xmm0：f64 位模式 movq；int 先 cvt
fn g_fint2f(lt: i64) -> i64 {
    if ty_kind(lt) == 6 {
        g_movq_rcx_xmm0();
    } else {
        g_cvtsi2sd_rcx();
    }
    return 0;
}

# rax 中的值按类型 rt 进入 xmm1（经 rcx 转接：先 save rax→rcx? 不能破坏左值已在 xmm0）
# 方案：rax 值先mov 到 r11，再从 r11 载入 xmm1
fn g_fint2f_r(rt: i64) -> i64 {
    ops3(0x49, 0x89, 0xc3);   # mov r11, rax
    if ty_kind(rt) == 6 {
        ops4(0x66, 0x49, 0x0f, 0x6e);   # movq xmm1, r11
        emit1(0xcb);
    } else {
        ops3(0x4c, 0x89, 0xd8);         # mov rax, r11
        ops4(0xf2, 0x48, 0x0f, 0x2a);   # cvtsi2sd xmm1, rax
        emit1(0xc8);
    }
    return 0;
}

# rax ^= 1<<63（f64 符号位翻转）
fn g_xor_imm63() -> i64 {
    ops2(0x49, 0xb8);          # movabs r8, 0x8000000000000000
    emit8(0 - 9223372036854775807 - 1);
    ops3(0x4c, 0x31, 0xc0);    # xor rax, r8
    return 0;
}

# f64 比较：ucomisd xmm0(左),xmm1(右) → setcc
# ucomisd: 66 0F 2E C1
fn g_ucomisd() -> i64 { ops4(0x66, 0x0f, 0x2e, 0xc1); return 0; }

# rax = (f64)rcx OP (f64)rax 的 0/1
# 注意 ucomisd 的无序(NaN)置 CF=ZF=PF=1：
#   < : CF=1   ≤: CF=1|ZF=1   > : 左>右 = !(CF|ZF)   ≥ = !(CF)
# setcc 直接支持 b/ba/e/ne（<,>,=,!=）；le/ge 用 setnbe 组合：
#   ≤ : setbe(0x96)  ≥ : setae(0x93)（CF=0）
fn g_fcmp_set(cc: i64) -> i64 {
    g_movq_rcx_xmm0();
    g_movq_rax_xmm1();
    g_ucomisd();
    ops2(0x0f, cc);
    emit1(0xc0);
    ops4(0x48, 0x0f, 0xb6, 0xc0);
    return 0;
}
