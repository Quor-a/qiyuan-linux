# ==========================================================================
#  compiler.mo  --  墨语言编译器（用墨语言自身实现）
#  读取 .mo 源码，输出 ELF64 静态可执行文件（x86-64 / Linux）
# ==========================================================================

# ---------------------------- 内存布局 ----------------------------
var heap:  i64 = 0;
var INPATH: i64 = 0;
var O_SRC: i64 = 0;
var O_CODE: i64 = 4194304;
var O_DATA: i64 = 5242880;
var O_NAMES: i64 = 6291456;
var O_SYN:  i64 = 6815744;
var K_WARN:   i64 = 464;   # 0=关闭未使用变量警告（有误报，见 docs）
var O_SU:   i64 = 9000000;   # 符号是否被读过（未使用检查，见 K_WARN）
var O_SK:   i64 = 6832128;
var O_SA:   i64 = 6848512;
var O_SP:   i64 = 6864896;
var O_SD:   i64 = 6881280;
var O_FP:   i64 = 6897664;
var O_FS:   i64 = 7028736;
var O_JP:   i64 = 7160800;
var O_JL:   i64 = 7291872;
var O_LB:   i64 = 7324640;
var O_SCAL: i64 = 7357408;
var O_FILES: i64 = 12582912;
var O_STRS:  i64 = 22020096;
# 结构体表：最多 32 个结构体，每个最多 32 个字段
var O_STN:   i64 = 8388608;    # 结构体名（intern 偏移）
var O_STF:   i64 = 8388864;    # 字段个数
var O_STFLD: i64 = 8389120;    # 字段名 id：idx = si*32 + fi
var O_STFT:  i64 = 8404992;    # 字段类型 id：0=i64，>=1 为结构体索引+1
var O_STY:   i64 = 8420864;    # 变量类型：0=i64/数组，>=1 为结构体索引+1
var O_IMP:   i64 = 8437760;    # 已导入文件路径（intern 偏移），用于去重与环检测
# 类型表：最多 512 个类型
var O_TK:    i64 = 8445952;    # kind: 0=int 1=void 2=struct 3=array 4=ptr
var O_TA:    i64 = 8450048;    # aux1: si(结构体) / 元素或指向类型
var O_TB:    i64 = 8454144;    # aux2: 数组元素个数
var O_FRT:   i64 = 8458240;    # 函数返回类型 id
var O_FPT:   i64 = 8462336;    # 形参类型：fidx*8 + pi
# 调试信息专用缓冲（都在 O_STRS 之后，堆空间充裕）
# 调试数据放在主堆之后单独申请的一块内存里（DBG 为基址，下列为相对偏移）。
# 早先直接放在 heap + 大偏移处，结果被字符串池覆盖——行号表读出来是字符串内容。
# 单独申请能彻底避开与主堆各区域的冲突。
var DBG:     i64 = 0;
var O_LM:    i64 = 0;          # 行号表：每条 16 字节 (code_len, line)
var O_DBG:   i64 = 1048576;    # DWARF 数据缓冲（各 section 分段使用）
var O_SHSTR: i64 = 2097152;    # section 名字符串表
var O_SHDR:  i64 = 2098176;    # section header 表

# ---------------------------- 标量槽 ----------------------------
var K_SRCLEN: i64 = 0;
var K_POS:    i64 = 8;
var K_TOKPOS: i64 = 16;
var K_CLEN:   i64 = 24;
var K_DLEN:   i64 = 32;
var K_NLEN:   i64 = 40;
var K_TKIND:  i64 = 48;
var K_TIVAL:  i64 = 56;
var K_NSYM:   i64 = 64;
var K_DEPTH:  i64 = 72;
var K_CUROFF: i64 = 80;
var K_NFNP:   i64 = 88;
var K_NJMP:   i64 = 96;
var K_NLAB:   i64 = 104;
var K_FPATCH: i64 = 112;
var K_TOKBUF: i64 = 128;
var K_LINE:  i64 = 176;
var K_COL:   i64 = 184;
var K_CPOS:  i64 = 192;
var K_PLINE: i64 = 200;
var K_PCOL:  i64 = 208;
var K_SRCBASE: i64 = 216;
var K_NFILE: i64 = 224;
var K_NSTR:  i64 = 232;
var K_STROFF: i64 = 240;
var K_NSTRUCT: i64 = 248;
var K_NIMP:   i64 = 256;
var K_NTYPE:  i64 = 264;
var K_PPOS:   i64 = 272;
var K_LAST:   i64 = 280;    # 0=无 1=rax 里是刚发的常量 2=rax 里是刚发的 [rbp+off]
var K_LASTV:  i64 = 288;
var K_LASTR:  i64 = 296;    # 折叠时要回退的字节数
var K_HASRET: i64 = 328;
var K_LDEPTH: i64 = 336;   # 循环标签栈深度
var K_LTOP:   i64 = 344;   # 栈顶索引
var K_PANIC:  i64 = 352;   # 越界处理例程的标签 id；-1 表示还没有数组访问
var K_PJMP:   i64 = 360;   # 上一条无条件 jmp 在跳转表里的下标+1；0 表示没有
var K_PJLBL:  i64 = 368;   # 那条 jmp 的目标标签
var K_PJEND:  i64 = 376;
# --- 调试信息（-g）：默认关闭。开启时才生成 DWARF，
#     不开启时输出字节完全不变，因此不影响自举 ---
var K_DBG:      i64 = 384;   # 0/1 是否开启 -g
var K_NLM:      i64 = 392;   # 行号表条数
var K_DBGLEN:   i64 = 408;   # 当前 debug section 已写长度
var K_DBBASE:   i64 = 416;   # 当前 debug section 在 O_DBG 里的起点
var K_INFOLEN:  i64 = 424;
var K_ABBRLEN:  i64 = 432;
var K_LINELEN:  i64 = 440;
var K_SHSTRLEN: i64 = 448;
var K_CRBX:    i64 = 456;   # rbx 里是否缓存着「最后一次 push」的值   # 那条 jmp 结束时的 code_len（若标签紧接着就落在这里）   # 当前函数体里是否出现过 return
var K_PL:    i64 = 304;    # 上一句 pop rcx 弹出的左操作数是否为常量
var K_PLV:   i64 = 312;
var K_PLR:   i64 = 320;

# ---------------------------- 标量访问 ----------------------------
fn gv(k: i64) -> i64 {
    return load64(heap + O_SCAL + k);
}

fn sv(k: i64, v: i64) -> i64 {
    store64(heap + O_SCAL + k, v);
    return 0;
}

# ---------------------------- 字节发射 ----------------------------
# 所有字节发射的唯一出口。顺带清掉「rax 刚由常量/局部量产生」的标记：
# 任何后续发射都意味着那个来源信息已经失效。
fn emit1(b: i64) -> i64 {
    sv(K_LAST, 0);
    sv(K_PJMP, 0);
    let n: i64 = gv(K_CLEN);
    store8(heap + O_CODE + n, b);
    sv(K_CLEN, n + 1);
    return 0;
}

fn emit4(v: i64) -> i64 {
    emit1(v & 255);
    emit1((v >> 8) & 255);
    emit1((v >> 16) & 255);
    emit1((v >> 24) & 255);
    return 0;
}

fn emit8(v: i64) -> i64 {
    emit1(v & 255);
    emit1((v >> 8) & 255);
    emit1((v >> 16) & 255);
    emit1((v >> 24) & 255);
    emit1((v >> 32) & 255);
    emit1((v >> 40) & 255);
    emit1((v >> 48) & 255);
    emit1((v >> 56) & 255);
    return 0;
}

fn dbyte(b: i64) -> i64 {
    let n: i64 = gv(K_DLEN);
    store8(heap + O_DATA + n, b);
    sv(K_DLEN, n + 1);
    return 0;
}

fn dquad(v: i64) -> i64 {
    let i: i64 = 0;
    while i < 8 {
        dbyte((v >> (i * 8)) & 255);
        i = i + 1;
    }
    return 0;
}

# ---------------------------- 字符串工具 ----------------------------
fn strlen(s: i64) -> i64 {
    let n: i64 = 0;
    while load8(s + n) != 0 {
        n = n + 1;
    }
    return n;
}

fn streq(a: i64, b: i64) -> i64 {
    let i: i64 = 0;
    while 1 {
        let ca: i64 = load8(a + i);
        if ca != load8(b + i) {
            return 0;
        }
        if ca == 0 {
            return 1;
        }
        i = i + 1;
    }
    return 0;
}

fn memcpy(d: i64, s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        store8(d + i, load8(s + i));
        i = i + 1;
    }
    store8(d + i, 0);
    return 0;
}

# 名字池
fn intern(s: i64) -> i64 {
    let off: i64 = gv(K_NLEN);
    let i: i64 = 0;
    while load8(s + i) != 0 {
        store8(heap + O_NAMES + off + i, load8(s + i));
        i = i + 1;
    }
    store8(heap + O_NAMES + off + i, 0);
    sv(K_NLEN, off + i + 1);
    return off;
}

fn name_at(i: i64) -> i64 {
    return heap + O_NAMES + load64(heap + O_SYN + i * 8);
}

# ---------------------------- 错误与退出 ----------------------------
# 输出十进制整数到 stderr
fn emit_dec(v: i64) -> i64 {
    let p: i64 = heap + O_SCAL + 1400;
    let i: i64 = 0;
    if v == 0 {
        store8(p, 48);
        syscall(1, 2, p, 1, 0, 0, 0);
        return 0;
    }
    while v > 0 {
        store8(p + i, 48 + (v % 10));
        v = v / 10;
        i = i + 1;
    }
    let j: i64 = 0;
    while j < i / 2 {
        let t: i64 = load8(p + j);
        store8(p + j, load8(p + i - 1 - j));
        store8(p + i - 1 - j, t);
        j = j + 1;
    }
    syscall(1, 2, p, i, 0, 0, 0);
    return 0;
}

# 把 K_LINE / K_COL 推进到源码位置 p（增量维护）
fn advance_lc(p: i64) -> i64 {
    let c: i64 = gv(K_CPOS);
    while c < p {
        if sbyte(c) == 10 {
            sv(K_LINE, gv(K_LINE) + 1);
            sv(K_COL, 1);
        } else {
            sv(K_COL, gv(K_COL) + 1);
        }
        c = c + 1;
    }
    sv(K_CPOS, c);
    return 0;
}

# 带 文件:行:列 的错误输出并退出
# 带 文件:行:列 的错误输出（可指定行列，用于指向上一个 token）
fn err_at2(msg: i64, ln: i64, cl: i64) -> i64 {
    syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(ln);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(cl);
    syscall(1, 2, ": error: ", 9, 0, 0, 0);
    syscall(1, 2, msg, strlen(msg), 0, 0, 0);
    syscall(1, 2, "\n", 1, 0, 0, 0);
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn err_at(msg: i64) -> i64 {
    return err_at2(msg, gv(K_LINE), gv(K_COL));
}

# 打印出错源码行与列指示符（p 为出错位置，cl 为列号）
fn err_src(p: i64, cl: i64) -> i64 {
    let b: i64 = p;
    let go: i64 = 1;
    while go == 1 {
        if b <= 0 {
            go = 0;
        } else {
            if sbyte(b - 1) == 10 {
                go = 0;
            } else {
                b = b - 1;
            }
        }
    }
    let e: i64 = p;
    let n: i64 = gv(K_SRCLEN);
    go = 1;
    while go == 1 {
        if e >= n {
            go = 0;
        } else {
            if sbyte(e) == 10 {
                go = 0;
            } else {
                e = e + 1;
            }
        }
    }
    syscall(1, 2, "    ", 4, 0, 0, 0);
    syscall(1, 2, heap + gv(K_SRCBASE) + b, e - b, 0, 0, 0);
    syscall(1, 2, "\n", 1, 0, 0, 0);
    syscall(1, 2, "    ", 4, 0, 0, 0);
    let i: i64 = 1;
    while i < cl {
        syscall(1, 2, " ", 1, 0, 0, 0);
        i = i + 1;
    }
    syscall(1, 2, "^\n", 2, 0, 0, 0);
    return 0;
}

# 带源码行输出的报错（自己拼头部，不能调 err_at2 —— 它会直接退出进程）
fn err_atp(msg: i64, ln: i64, cl: i64, p: i64) -> i64 {
    syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(ln);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(cl);
    syscall(1, 2, ": error: ", 9, 0, 0, 0);
    syscall(1, 2, msg, strlen(msg), 0, 0, 0);
    syscall(1, 2, "\n", 1, 0, 0, 0);
    err_src(p, cl);
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn die(msg: i64) -> i64 {
    syscall(1, 2, msg, strlen(msg), 0, 0, 0);
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn syntax_error() -> i64 {
    return err_at("syntax error");
}

# ---------------------------- 类型表 ----------------------------
#  id 0 = int,  id 1 = void，其余由 ty_new 按需分配并去重
fn ty_int() -> i64  { return 0; }
fn ty_void() -> i64 { return 1; }
fn ty_byte() -> i64 { return 2; }

# 预置 id 0 = int, id 1 = void
fn ty_init() -> i64 {
    store64(heap + O_TK + 0, 0);
    store64(heap + O_TA + 0, 0);
    store64(heap + O_TB + 0, 0);
    store64(heap + O_TK + 8, 1);
    # id 2 = byte（kind 5，1 字节无符号，加载时零扩展）
    store64(heap + O_TK + 16, 5);
    store64(heap + O_TA + 16, 0);
    store64(heap + O_TB + 16, 0);
    store64(heap + O_TA + 8, 0);
    store64(heap + O_TB + 8, 0);
    sv(K_NTYPE, 3);
    return 0;
}

fn ty_new(kind: i64, a: i64, b: i64) -> i64 {
    let n: i64 = gv(K_NTYPE);
    let i: i64 = 2;
    while i < n {
        if load64(heap + O_TK + i * 8) == kind {
            if load64(heap + O_TA + i * 8) == a {
                if load64(heap + O_TB + i * 8) == b { return i; }
            }
        }
        i = i + 1;
    }
    store64(heap + O_TK + n * 8, kind);
    store64(heap + O_TA + n * 8, a);
    store64(heap + O_TB + n * 8, b);
    sv(K_NTYPE, n + 1);
    return n;
}

fn ty_struct(si: i64) -> i64 { return ty_new(2, si, 0); }
fn ty_array(el: i64, n: i64) -> i64 { return ty_new(3, el, n); }
fn ty_ptr(to: i64) -> i64 { return ty_new(4, to, 0); }

fn ty_kind(t: i64) -> i64 { return load64(heap + O_TK + t * 8); }
fn ty_a(t: i64) -> i64 { return load64(heap + O_TA + t * 8); }
fn ty_b(t: i64) -> i64 { return load64(heap + O_TB + t * 8); }

fn ty_eq(x: i64, y: i64) -> i64 {
    if x == y { return 1; }
    return 0;
}

# 结构体类型的 aux1 里存的是结构体索引
fn ty_si(t: i64) -> i64 { return load64(heap + O_TA + t * 8); }

fn ty_size(t: i64) -> i64 {
    let k: i64 = ty_kind(t);
    if k == 5 { return 1; }
    if k == 2 { return 8 * st_nfields(ty_a(t)); }
    if k == 3 { return ty_b(t) * ty_size(ty_a(t)); }
    return 8;
}

# 下标访问的元素类型（数组与指针都按指向/元素类型步进）
fn elem_type(t: i64) -> i64 {
    let k: i64 = ty_kind(t);
    if k == 3 { return ty_a(t); }
    if k == 4 { return ty_a(t); }
    return ty_int();
}

fn elem_size(t: i64) -> i64 {
    let k: i64 = ty_kind(t);
    if k == 3 { return ty_size(ty_a(t)); }
    if k == 4 { return ty_size(ty_a(t)); }
    return 8;
}

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
        return 0;
    }
    if v > 4294967295 {
        ops2(0x48, 0xb8);
        emit8(v);
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
    sv(K_POS, p);
    sv(K_TKIND, 2);
    sv(K_TIVAL, v);
    store8(tokbuf(), 0);
    return 0;
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

# ==========================================================================
#  符号表
#    kind 0 = 函数   1 = 局部   2 = 全局
# ==========================================================================
var R_SYM:   i64 = 0;
var R_NARG:  i64 = 0;
var R_L1:    i64 = 0;
var R_L2:    i64 = 0;
var R_BASE:  i64 = 0;
var R_AFTER: i64 = 0;

fn scratch1() -> i64 { return heap + O_SCAL + 400; }
fn scratch2() -> i64 { return heap + O_SCAL + 700; }
fn scratch3() -> i64 { return heap + O_SCAL + 1000; }

# 按调用深度分配的暂存区，避免嵌套调用互相覆盖
var CALLD:  i64 = 0;
var R_ETY:  i64 = 0;      # 最近一个表达式的类型 id
var O_SCR:  i64 = 7454720;

fn cscratch() -> i64 {
    return heap + O_SCR + CALLD * 256;
}

# 同作用域内是否已存在同名符号（用于重复定义检查）
fn sym_dup(name: i64) -> i64 {
    let i: i64 = gv(K_NSYM);
    while i > 0 {
        i = i - 1;
        if sym_kind(i) != 0 {
            if load64(heap + O_SD + i * 8) == gv(K_DEPTH) {
                if streq(name_at(i), name) == 1 { return i; }
            }
        }
    }
    return -1;
}

# 符号区容量。各区间隔 16384 字节 = 2048 个符号。
# 超过就**明确报错**：此前没有检查，溢出会静默覆盖相邻的符号类型区，
# 表现为"崩在一个完全无关的简单函数里"，极难定位（mo2x 就栽在这上面）。
fn sym_add(name: i64, kind: i64, addr: i64, npar: i64) -> i64 {
    let i: i64 = gv(K_NSYM);
    if i >= 2048 { return die("too many symbols (limit 2048)"); }
    let no: i64 = intern(name);
    store64(heap + O_SYN + i * 8, no);
    store64(heap + O_SK + i * 8, kind);
    store64(heap + O_SA + i * 8, addr);
    store64(heap + O_SP + i * 8, npar);
    store64(heap + O_SD + i * 8, gv(K_DEPTH));
    store64(heap + O_SU + i * 8, 0);
    sv(K_NSYM, i + 1);
    return i;
}

fn sym_kind(i: i64) -> i64 { return load64(heap + O_SK + i * 8); }
fn sym_addr(i: i64) -> i64 { return load64(heap + O_SA + i * 8); }

fn sym_lookup(name: i64) -> i64 {
    let i: i64 = gv(K_NSYM);
    while i > 0 {
        i = i - 1;
        if sym_kind(i) != 0 {
            if streq(name_at(i), name) == 1 { return i; }
        }
    }
    return -1;
}

fn sym_lookup_func(name: i64) -> i64 {
    let i: i64 = gv(K_NSYM);
    while i > 0 {
        i = i - 1;
        if sym_kind(i) == 0 {
            if streq(name_at(i), name) == 1 { return i; }
        }
    }
    return -1;
}

# ==========================================================================
#  结构体表
#    O_STN[si]                 结构体名（intern 偏移）
#    O_STF[si]                 字段个数
#    O_STFLD[si*32+fi]         字段名 id
#    O_STFT[si*32+fi]          字段类型：0=i64，>=1 为结构体索引+1
# ==========================================================================
fn st_add(name: i64) -> i64 {
    let i: i64 = gv(K_NSTRUCT);
    store64(heap + O_STN + i * 8, intern(name));
    store64(heap + O_STF + i * 8, 0);
    sv(K_NSTRUCT, i + 1);
    return i;
}

fn st_lookup(name: i64) -> i64 {
    let i: i64 = gv(K_NSTRUCT);
    while i > 0 {
        i = i - 1;
        if streq(heap + O_NAMES + load64(heap + O_STN + i * 8), name) == 1 { return i; }
    }
    return -1;
}

fn st_nfields(si: i64) -> i64 { return load64(heap + O_STF + si * 8); }

fn st_add_field(si: i64, fname: i64, ftype: i64) -> i64 {
    if st_field(si, fname) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let fi: i64 = load64(heap + O_STF + si * 8);
    store64(heap + O_STFLD + (si * 32 + fi) * 8, intern(fname));
    store64(heap + O_STFT + (si * 32 + fi) * 8, ftype);
    store64(heap + O_STF + si * 8, fi + 1);
    return fi;
}

# 在结构体 si 中查找字段，返回索引或 -1
fn st_field(si: i64, fname: i64) -> i64 {
    let n: i64 = load64(heap + O_STF + si * 8);
    let i: i64 = 0;
    while i < n {
        if streq(heap + O_NAMES + load64(heap + O_STFLD + (si * 32 + i) * 8), fname) == 1 {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn st_field_type(si: i64, fi: i64) -> i64 {
    return load64(heap + O_STFT + (si * 32 + fi) * 8);
}

fn sym_type(i: i64) -> i64 { return load64(heap + O_STY + i * 8); }
fn sym_npar(i: i64) -> i64 { return load64(heap + O_SP + i * 8); }

# 两个类型是否可以在赋值/传参中互换
# 当前机器层都是 8 字节；禁止的是把数组或结构体当标量用
fn ty_compat(a: i64, b: i64) -> i64 {
    if ty_eq(a, b) == 1 { return 1; }
    let ka: i64 = ty_kind(a);
    let kb: i64 = ty_kind(b);
    if ka == 3 { return 0; }
    if kb == 3 { return 0; }
    if ka == 2 { return 0; }
    if kb == 2 { return 0; }
    return 1;
}

# 解析 .field 链：进入时当前 token 为 '.'，rax 已持有基址，ty 为基址类型
# 返回最终字段类型（0=i64，>=1 结构体索引+1）；rax 中留下该字段的地址
fn field_chain(ty: i64) -> i64 {
    while tok_is(".") == 1 {
        next_token();
        if gv(K_TKIND) != 1 { return syntax_error(); }
        memcpy(scratch1(), tokbuf());
        next_token();
        if ty_kind(ty) != 2 { return err_atp("field access on non-struct type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let si: i64 = ty_a(ty);
        let fi: i64 = st_field(si, scratch1());
        if fi < 0 { return undef_err(scratch1()); }
        if fi > 0 {
            g_push_rax();
            g_movabs_rax(fi * 8);
            g_pop_rcx();
            g_add();
        }
        ty = st_field_type(si, fi);
    }
    return ty;
}

# 从符号 sy 取基址并解析 .field 链
fn field_addr(sy: i64) -> i64 {
    if sym_kind(sy) == 1 {
        g_lea_local(sym_addr(sy));
    } else {
        g_movabs_rax(sym_addr(sy));
    }
    return field_chain(sym_type(sy));
}

# 打印一行警告。与 undef_err 不同：不退出，编译继续。
fn warn_unused_at(name: i64) -> i64 {
    syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
    syscall(1, 2, ": warning: unused variable '", 28, 0, 0, 0);
    syscall(1, 2, name, strlen(name), 0, 0, 0);
    syscall(1, 2, "'\n", 2, 0, 0, 0);
    return 0;
}

# 未使用变量检查：只报警告，不影响编译成功。
# 选警告而不是错误，是因为它不该挡住编译 —— 而且这条诊断只在 moc 实现，
# seed 不实现它。保持它是警告的第二个理由：万一误报，
# 代价只是多打几行字，不是编译不过。
fn warn_unused(d: i64) -> i64 {
    let i: i64 = gv(K_NSYM);
    while i > 0 {
        let k: i64 = i - 1;
        if load64(heap + O_SD + k * 8) < d {
            return 0;
        }
        # 只查局部变量（kind==1）：全局量可能只被别的文件用
        if load64(heap + O_SK + k * 8) == 1 {
            if load64(heap + O_SU + k * 8) == 0 {
                warn_unused_at(name_at(k));
            }
        }
        i = i - 1;
    }
    return 0;
}

fn sym_pop_scope(d: i64) -> i64 {
    let i: i64 = gv(K_NSYM);
    while i > 0 {
        if load64(heap + O_SD + (i - 1) * 8) < d {
            sv(K_NSYM, i);
            return 0;
        }
        i = i - 1;
    }
    sv(K_NSYM, 0);
    return 0;
}

# ==========================================================================
#  表达式
# ==========================================================================
fn parse_expr() -> i64 { return parse_or(); }

fn parse_or() -> i64 {
    parse_and();
    while accept("||") == 1 {
        let a: i64 = new_label();
        let b: i64 = new_label();
        g_cmp_rax_0();
        emit_jcc(0x85, a);
        parse_and();
        g_cmp_rax_0();
        emit_jcc(0x85, a);
        g_movabs_rax(0);
        emit_jmp(b);
        place_label(a);
        g_movabs_rax(1);
        place_label(b);
    }
    return 0;
}

fn parse_and() -> i64 {
    parse_bor();
    while accept("&&") == 1 {
        let a: i64 = new_label();
        let b: i64 = new_label();
        g_cmp_rax_0();
        emit_jcc(0x84, a);
        parse_bor();
        g_cmp_rax_0();
        emit_jcc(0x84, a);
        g_movabs_rax(1);
        emit_jmp(b);
        place_label(a);
        g_movabs_rax(0);
        place_label(b);
    }
    return 0;
}

fn parse_bor() -> i64 {
    parse_bxor();
    while accept("|") == 1 {
        g_push_rax();
        parse_bxor();
        g_pop_rcx();
        g_or();
    }
    return 0;
}

fn parse_bxor() -> i64 {
    parse_band();
    while accept("^") == 1 {
        g_push_rax();
        parse_band();
        g_pop_rcx();
        g_xor();
    }
    return 0;
}

fn parse_band() -> i64 {
    parse_eq();
    while accept("&") == 1 {
        g_push_rax();
        parse_eq();
        g_pop_rcx();
        g_and();
    }
    return 0;
}

fn parse_eq() -> i64 {
    parse_rel();
    while 1 {
        if accept("==") == 1 {
            g_push_rax();
            parse_rel();
            g_pop_rcx();
            g_cmp_set(0x94);
        } else {
            if accept("!=") == 1 {
                g_push_rax();
                parse_rel();
                g_pop_rcx();
                g_cmp_set(0x95);
            } else {
                return 0;
            }
        }
    }
    return 0;
}

fn parse_rel() -> i64 {
    parse_shift();
    while 1 {
        if accept("<") == 1 {
            g_push_rax();
            parse_shift();
            g_pop_rcx();
            g_cmp_set(0x9c);
        } else {
            if accept("<=") == 1 {
                g_push_rax();
                parse_shift();
                g_pop_rcx();
                g_cmp_set(0x9e);
            } else {
                if accept(">") == 1 {
                    g_push_rax();
                    parse_shift();
                    g_pop_rcx();
                    g_cmp_set(0x9f);
                } else {
                    if accept(">=") == 1 {
                        g_push_rax();
                        parse_shift();
                        g_pop_rcx();
                        g_cmp_set(0x9d);
                    } else {
                        return 0;
                    }
                }
            }
        }
    }
    return 0;
}

fn parse_shift() -> i64 {
    parse_add();
    while 1 {
        if accept("<<") == 1 {
            g_push_rax();
            parse_add();
            g_pop_rcx();
            g_shl();
            R_ETY = ty_int();
        } else {
            if accept(">>") == 1 {
                g_push_rax();
                parse_add();
                g_pop_rcx();
                g_sar();
            } else {
                return 0;
            }
        }
    }
    return 0;
}

fn parse_add() -> i64 {
    parse_mul();
    while 1 {
        if accept("+") == 1 {
            g_push_rax();
            parse_mul();
            g_pop_rcx();
            g_add();
            R_ETY = ty_int();
        } else {
            if accept("-") == 1 {
                g_push_rax();
                parse_mul();
                g_pop_rcx();
                g_sub();
            } else {
                return 0;
            }
        }
    }
    return 0;
}

fn parse_mul() -> i64 {
    parse_unary();
    while 1 {
        if accept("*") == 1 {
            g_push_rax();
            parse_unary();
            g_pop_rcx();
            g_imul();
            R_ETY = ty_int();
        } else {
            if accept("/") == 1 {
                g_push_rax();
                parse_unary();
                g_pop_rcx();
                g_idiv(0);
            } else {
                if accept("%") == 1 {
                    g_push_rax();
                    parse_unary();
                    g_pop_rcx();
                    g_idiv(1);
                } else {
                    return 0;
                }
            }
        }
    }
    return 0;
}

# 一元 & ：取变量 / 数组首元素的地址（指针即整数）
fn parse_addr() -> i64 {
    if gv(K_TKIND) != 1 { return syntax_error(); }
    memcpy(scratch1(), tokbuf());
    next_token();
    let sy: i64 = sym_lookup(scratch1());
    if sy < 0 { return undef_err(scratch1()); }
    if sym_kind(sy) == 1 {
        g_lea_local(sym_addr(sy));
    } else {
        g_movabs_rax(sym_addr(sy));
    }
    R_ETY = ty_ptr(elem_type(sym_type(sy)));
    return 0;
}

fn parse_unary() -> i64 {
    if accept("&") == 1 { return parse_addr(); }
    if accept("-") == 1 {
        parse_unary();
        g_neg();
        R_ETY = ty_int();
        return 0;
    }
    if accept("~") == 1 {
        parse_unary();
        g_not();
        R_ETY = ty_int();
        return 0;
    }
    if accept("!") == 1 {
        parse_unary();
        g_lnot();
        R_ETY = ty_int();
        return 0;
    }
    return parse_primary();
}

fn undef_err(name: i64) -> i64 {
    syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(gv(K_PLINE));
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(gv(K_PCOL));
    syscall(1, 2, ": error: undefined symbol '", 27, 0, 0, 0);
    syscall(1, 2, name, strlen(name), 0, 0, 0);
    syscall(1, 2, "'\n", 2, 0, 0, 0);
    err_src(gv(K_PPOS), gv(K_PCOL));
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn parse_primary() -> i64 {
    let k: i64 = gv(K_TKIND);
    if k == 2 {
        g_movabs_rax(gv(K_TIVAL));
        next_token();
        R_ETY = ty_int();
        return 0;
    }
    if k == 3 {
        g_movabs_rax(gv(K_TIVAL));
        next_token();
        R_ETY = ty_ptr(ty_byte());
        # 字符串字面量直接下标："hello"[1]
        # 以前必须先赋给 ptr 变量才能用下标，很别扭。
        # 这里就地处理：基址已在 rax，算偏移后按 1 字节加载。
        if tok_is("[") == 1 {
            next_token();
            parse_expr();
            expect("]");
            g_push_rax();
            g_pop_rcx();
            g_add();
            g_load_at_b();
            R_ETY = ty_byte();
        }
        return 0;
    }
    if k == 4 {
        if accept("(") == 1 {
            parse_expr();
            expect(")");
            return 0;
        }
        return syntax_error();
    }
    if k == 1 {
        memcpy(scratch1(), tokbuf());
        next_token();
        if tok_is("(") == 1 {
            if streq(scratch1(), "argc") == 1 {
                next_token();
                expect(")");
                g_movabs_rax(268435456);
                g_load_at();
                R_ETY = ty_int();
                return 0;
            }
            if streq(scratch1(), "argv") == 1 {
                next_token();
                parse_expr();
                expect(")");
                g_push_rax();
                g_pop_rax();
                g_mul_imm(8);
                g_push_rax();
                g_movabs_rax(268435464);
                g_load_at();
                g_pop_rcx();
                g_add();
                g_load_at();
                R_ETY = ty_int();
                return 0;
            }
            return parse_call();
        }
        let sy: i64 = sym_lookup(scratch1());
        # 标记「被引用」。必须在解析处标记，不能只在 load_sym 里标：
        # 数组几乎都通过 &arr 使用，参数也常直接进内建函数实参，
        # 这两条路都不走 load_sym —— 放在那里标记会大量误报。
        if sy >= 0 {
            store64(heap + O_SU + sy * 8, 1);
        }
        if sy < 0 { return undef_err(scratch1()); }
        if tok_is("[") == 1 {
            index_addr(sy);
            let e2: i64 = elem_type(sym_type(sy));
            if tok_is(".") == 1 {
                let ft: i64 = field_chain(e2);
                if ty_kind(ft) != 2 {
                    if ty_kind(ft) == 5 { g_load_at_b(); } else { g_load_at(); }
                }
                return 0;
            }
            # 元素宽度决定加载宽度：byte 元素必须按 1 字节零扩展，
            # 否则 s[i] 会一次读进 8 个字节。
            if ty_kind(e2) == 5 { g_load_at_b(); } else { g_load_at(); }
            R_ETY = e2;
            return 0;
        }
        if tok_is(".") == 1 {
            let ft: i64 = field_addr(sy);
            if ty_kind(ft) != 2 { g_load_at(); }
            R_ETY = ft;
            return 0;
        }
        load_sym(sy);
        R_ETY = sym_type(sy);
        return 0;
    }
    return syntax_error();
}

# 生成 a[i] 的地址到 rax（s 为数组符号索引）；进入时当前 token 为 '['
# 越界处理：所有下标检查跳转到的公共例程标签（按需创建）
fn panic_label() -> i64 {
    let l: i64 = gv(K_PANIC);
    if l < 0 {
        l = new_label();
        sv(K_PANIC, l);
    }
    return l;
}

# 把 "mo: index out of bounds\n"（24 字节）写进输出数据段，返回地址。
# 刻意用字符字面量逐字节写，而不是字符串字面量：
# 被编译程序里的字符串编译器读不到——那片虚拟地址在 moc 进程里
# 映射的是 moc 自己的数据段，读到的是垃圾。
fn panic_msg() -> i64 {
    let addr: i64 = 268435456 + gv(K_DLEN);
    dbyte('m'); dbyte('o'); dbyte(':'); dbyte(' ');
    dbyte('i'); dbyte('n'); dbyte('d'); dbyte('e'); dbyte('x');
    dbyte(' '); dbyte('o'); dbyte('u'); dbyte('t'); dbyte(' ');
    dbyte('o'); dbyte('f'); dbyte(' '); dbyte('b'); dbyte('o');
    dbyte('u'); dbyte('n'); dbyte('d'); dbyte('s'); dbyte('\n');
    dbyte(0);
    return addr;
}

# 在代码段末尾生成越界处理例程：打印消息并以 1 退出。
# 放在末尾而不是每个检查点内联，是为了让检查点只有 12 字节。
fn emit_panic() -> i64 {
    let l: i64 = gv(K_PANIC);
    if l < 0 { return 0; }
    place_label(l);
    # write(2, msg, 24)
    ops3(0x48, 0xc7, 0xc0); emit4(1);
    ops3(0x48, 0xc7, 0xc7); emit4(2);
    ops2(0x48, 0xbe); emit8(panic_msg());
    ops3(0x48, 0xc7, 0xc2); emit4(24);
    ops2(0x0f, 0x05);
    # exit(1)
    ops3(0x48, 0xc7, 0xc0); emit4(60);
    ops3(0x48, 0xc7, 0xc7); emit4(1);
    ops2(0x0f, 0x05);
    return 0;
}

# 记录「代码位置 -> 源码行」映射，供 -g 生成 DWARF 行号表。
# 每条 16 字节：(code_len, line)。
# 只记主文件（fileidx==0）的行号；import 进来的文件也记 fileidx，
# 生成时跳过——它们的行号属于别的源文件，混进主文件的行号表会错乱。
# 记录「代码位置 -> 源码行」映射，供 -g 生成 DWARF 行号表。
# 每条 16 字节：(code_len, line)。
#
# 只记主文件：parse_import 会在解析子文件期间把 K_DBG 临时置 0，
# 于是 dbg_mark 直接返回。用开关而不是给每条记录打文件号，
# 是因为后者依赖一个「当前文件索引」全局量，而那个量在实测中
# 读出来是脏值——与其追它，不如用一条本来就存在的开关。
fn dbg_mark() -> i64 {
    if gv(K_DBG) == 0 { return 0; }
    let n: i64 = gv(K_NLM);
    if n >= 60000 { return 0; }
    let a: i64 = gv(K_CLEN);
    # 同一地址不重复记录（多条语句可能在同一地址开始）
    if n > 0 {
        if load64(DBG + O_LM + (n - 1) * 16) == a { return 0; }
    }
    let ln0: i64 = gv(K_LINE);
    store64(DBG + O_LM + n * 16, a);
    store64(DBG + O_LM + n * 16 + 8, ln0);
    sv(K_NLM, n + 1);
    return 0;
}

fn index_addr(s: i64) -> i64 {
    let st: i64 = sym_type(s);
    let k: i64 = ty_kind(st);
    if k != 3 {
        if k != 4 {
            return err_atp("subscript on non-array type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
        }
    }
    expect("[");
    # 编译期常量下标：a[9] 这种一眼就看得出越界的，不必等到运行时。
    # 做法是先试探性地多读一个 token 看是不是 ']'，再 set_pos 退回去
    # 走正常的 parse_expr 路径。set_pos 会把 LINE/COL 也重算一遍，
    # 所以回退后行列信息依然正确。
    let cidx: i64 = -1;          # >=0 表示下标是编译期常量
    if gv(K_TKIND) == 2 {
        let iv: i64 = gv(K_TIVAL);
        let back: i64 = gv(K_TOKPOS);
        next_token();
        if tok_is("]") == 1 {
            cidx = iv;
            if k == 3 {
                let ne: i64 = ty_b(st);
                if iv < 0 {
                    return err_atp("index out of bounds: negative constant index", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
                if iv >= ne {
                    return err_atp("index out of bounds: constant index >= array length", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
            }
        }
        set_pos(back);
    }
    parse_expr();
    expect("]");
    # 越界检查：只对「编译期已知长度」的数组做。
    # 用无符号比较 cmp rax, n / jae —— 负数作为无符号是超大值，
    # 于是一条 cmp + 一条 jae 同时拦住了负下标与上界。
    # cmp 不破坏 rax，下标值还能继续用于下面的地址计算。
    if k == 3 {
        if cidx < 0 {
            let ne: i64 = ty_b(st);
            if ne <= 2147483647 {
                ops2(0x48, 0x3d);
                emit4(ne);
                emit_jcc(0x83, panic_label());
            }
        }
    }
    g_mul_imm(elem_size(st));
    g_push_rax();
    # 数组变量：变量所在的地址就是数组基址 —— 取地址（lea / 绝对地址）
    # 指针变量：变量的值是地址 —— 必须加载它的值
    # 这两者弄混的话，p[1] 会去读「指针变量本身的第 1 个字节」，
    # 也就是指针值的高位字节，而不是它指向的内容。
    if ty_kind(st) == 4 {
        load_sym(s);
    } else {
        if sym_kind(s) == 1 {
            g_lea_local(sym_addr(s));
        } else {
            g_movabs_rax(sym_addr(s));
        }
    }
    g_pop_rcx();
    g_add();
    return 0;
}

# argc() / argv(i)：读取启动时存进数据段头部的 argc / argv
fn is_argc() -> i64 {
    if streq(cscratch(), "argc") == 1 { return 1; }
    return 0;
}

fn parse_call() -> i64 {
    CALLD = CALLD + 1;
    memcpy(cscratch(), scratch1());
    expect("(");
    let na: i64 = 0;
    while tok_is(")") == 0 {
        parse_expr();
        g_push_rax();
        na = na + 1;
        if accept(",") == 0 {
            if tok_is(")") == 0 { CALLD = CALLD - 1; return syntax_error(); }
        }
    }
    expect(")");
    if streq(cscratch(), "load8") == 1 {
        g_pop_rax();
        ops3(0x0f, 0xb6, 0x00);
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "load64") == 1 {
        g_pop_rax();
        ops3(0x48, 0x8b, 0x00);
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "store8") == 1 {
        g_pop_rbx();
        g_pop_rcx();
        ops2(0x88, 0x19);
        g_zero_rax();
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "store64") == 1 {
        g_pop_rbx();
        g_pop_rcx();
        ops3(0x48, 0x89, 0x19);
        g_zero_rax();
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "syscall") == 1 {
        if na >= 7 { g_pop_r9(); }
        if na >= 6 { g_pop_r8(); }
        if na >= 5 { g_pop_r10(); }
        if na >= 4 { g_pop_rdx(); }
        if na >= 3 { g_pop_rsi(); }
        if na >= 2 { g_pop_rdi(); }
        g_pop_rax();
        g_syscall();
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "syscall") == 0 {
        if streq(cscratch(), "load8") == 0 {
            if streq(cscratch(), "load64") == 0 {
                if streq(cscratch(), "store8") == 0 {
                    if streq(cscratch(), "store64") == 0 {
                        R_SYM = sym_lookup_func(cscratch());
                        if R_SYM >= 0 {
                            if sym_npar(R_SYM) != na {
                                return err_atp("wrong number of arguments", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                            }
                        }
                    }
                }
            }
        }
    }
    if na >= 6 { g_pop_r9(); }
    if na >= 5 { g_pop_r8(); }
    if na >= 4 { g_pop_rcx(); }
    if na >= 3 { g_pop_rdx(); }
    if na >= 2 { g_pop_rsi(); }
    if na >= 1 { g_pop_rdi(); }
    R_SYM = sym_lookup_func(cscratch());
    if R_SYM < 0 { CALLD = CALLD - 1; return undef_err(cscratch()); }
    emit_call_patch(R_SYM);
    CALLD = CALLD - 1;
    return 0;
}

# ==========================================================================
#  语句
# ==========================================================================
fn parse_block(d: i64) -> i64 {
    let prev: i64 = gv(K_DEPTH);
    sv(K_DEPTH, d);
    expect("{");
    while tok_is("}") == 0 {
        parse_stmt();
    }
    next_token();
    if gv(K_WARN) == 1 {
        warn_unused(d);
    }
    sym_pop_scope(d);
    sv(K_DEPTH, prev);
    return 0;
}

# break / continue：跳到当前循环的出口 / 循环头
fn parse_break() -> i64 {
    expect(";");
    let l: i64 = loop_brk();
    if l < 0 { return err_atp("break outside of a loop", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    emit_jmp(l);
    return 0;
}

fn parse_continue() -> i64 {
    expect(";");
    let sp: i64 = loop_stp();
    if sp >= 0 { emit_jmp(sp); return 0; }
    let l: i64 = loop_cnt();
    if l < 0 { return err_atp("continue outside of a loop", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    emit_jmp(l);
    return 0;
}

# 复合赋值运算符识别与运算分发。
# 编码：1=+ 2=- 3=* 4=/ 5=% 6=& 7=| 8=^
fn compound_op() -> i64 {
    if tok_is("+=") == 1 { return 1; }
    if tok_is("-=") == 1 { return 2; }
    if tok_is("*=") == 1 { return 3; }
    if tok_is("/=") == 1 { return 4; }
    if tok_is("%=") == 1 { return 5; }
    if tok_is("&=") == 1 { return 6; }
    if tok_is("|=") == 1 { return 7; }
    if tok_is("^=") == 1 { return 8; }
    # <<= >>= 是三字符 token，词法必须单独识别，
    # 否则会被切成 "<" 与 "<="，解析必然失败
    if tok_is("<<=") == 1 { return 9; }
    if tok_is(">>=") == 1 { return 10; }
    return 0;
}

# 此刻 rax = 右操作数，rcx = 左操作数（变量原值）。
# 直接复用二元运算的那套 g_* 函数，所以语义与 x = x OP e 完全一致，
# 包括不可交换的减法和除法。
fn g_compound(op: i64) -> i64 {
    if op == 1 { g_add(); return 0; }
    if op == 2 { g_sub(); return 0; }
    if op == 3 { g_imul(); return 0; }
    if op == 4 { g_idiv(0); return 0; }
    if op == 5 { g_idiv(1); return 0; }
    if op == 6 { g_and(); return 0; }
    if op == 7 { g_or(); return 0; }
    if op == 8 { g_xor(); return 0; }
    if op == 9 { g_shl(); return 0; }
    if op == 10 { g_sar(); return 0; }
    return 0;
}

fn parse_stmt() -> i64 {
    dbg_mark();
    if accept("break") == 1 { return parse_break(); }
    if accept("continue") == 1 { return parse_continue(); }
    if accept("let") == 1 { return parse_let(); }
    if accept("if") == 1 { return parse_if(); }
    if accept("while") == 1 { return parse_while(); }
    if accept("for") == 1 { return parse_for(); }
    if accept("return") == 1 { return parse_return(); }
    if gv(K_TKIND) == 1 {
        memcpy(scratch2(), tokbuf());
        let save: i64 = gv(K_TOKPOS);
        next_token();
        if tok_is("++") == 1 {
            next_token();
            expect(";");
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            let it: i64 = sym_type(R_SYM);
            if ty_kind(it) == 3 { return err_atp("cannot increment an array", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            if ty_kind(it) == 2 { return err_atp("cannot increment a struct value", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            load_sym(R_SYM);
            g_push_rax();
            g_movabs_rax(1);
            g_pop_rcx();
            g_add();
            store_sym(R_SYM);
            return 0;
        }
        if tok_is("--") == 1 {
            next_token();
            expect(";");
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            let dt: i64 = sym_type(R_SYM);
            if ty_kind(dt) == 3 { return err_atp("cannot decrement an array", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            if ty_kind(dt) == 2 { return err_atp("cannot decrement a struct value", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            load_sym(R_SYM);
            g_push_rax();
            g_movabs_rax(1);
            g_pop_rcx();
            g_sub();
            store_sym(R_SYM);
            return 0;
        }
        if compound_op() > 0 {
            let cop: i64 = compound_op();
            next_token();
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            let clt: i64 = sym_type(R_SYM);
            if ty_kind(clt) == 3 { return err_atp("cannot assign to an array", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            if ty_kind(clt) == 2 { return err_atp("cannot assign a struct value", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            # 先取原值入栈当作左操作数，再算右操作数，最后运算并存回
            load_sym(R_SYM);
            g_push_rax();
            parse_expr();
            expect(";");
            g_pop_rcx();
            g_compound(cop);
            store_sym(R_SYM);
            return 0;
        }
        if tok_is("=") == 1 {
            next_token();
            # 预读右边是否为「单个标识符」。结构体整体赋值需要右边的地址，
            # 所以只支持 标识符 = 标识符；其它形状仍然报错。
            let rhs: i64 = -1;
            if gv(K_TKIND) == 1 {
                memcpy(scratch3(), tokbuf());
                let save2: i64 = gv(K_TOKPOS);
                next_token();
                if tok_is(";") == 1 { rhs = sym_lookup(scratch3()); }
                set_pos(save2);
            }
            parse_expr();
            expect(";");
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            let lt: i64 = sym_type(R_SYM);
            if ty_kind(lt) == 3 { return err_atp("cannot assign to an array", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            if ty_kind(lt) == 2 {
                if rhs >= 0 {
                    if ty_kind(sym_type(rhs)) == 2 {
                        if ty_si(sym_type(rhs)) == ty_si(lt) {
                            g_addr_sym_rax(R_SYM);
                            g_addr_sym_rsi(rhs);
                            g_copy_words(st_nfields(ty_si(lt)));
                            R_ETY = lt;
                            return 0;
                        }
                    }
                    return err_atp("struct assignment requires the same type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
                return err_atp("cannot assign a struct value: right side must be a variable", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
            if ty_compat(lt, R_ETY) == 0 { return err_atp("incompatible assignment", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            store_sym(R_SYM);
            return 0;
        }
        if tok_is("[") == 1 {
            let sy: i64 = sym_lookup(scratch2());
            if sy < 0 { return undef_err(scratch2()); }
            index_addr(sy);
            let at: i64 = elem_type(sym_type(sy));
            if tok_is(".") == 1 {
                let ft: i64 = field_chain(at);
                if ty_kind(ft) == 2 { return err_at2("cannot assign a struct value", gv(K_LINE), gv(K_COL)); }
                at = ft;
            }
            if tok_is("++") == 1 {
                next_token();
                expect(";");
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(at) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                g_movabs_rax(1);
                g_pop_rcx();
                g_add();
                g_pop_rcx();
                if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            if tok_is("--") == 1 {
                next_token();
                expect(";");
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(at) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                g_movabs_rax(1);
                g_pop_rcx();
                g_sub();
                g_pop_rcx();
                if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            if compound_op() > 0 {
                let cop2: i64 = compound_op();
                next_token();
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(at) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                parse_expr();
                expect(";");
                g_pop_rcx();
                g_compound(cop2);
                g_pop_rcx();
                if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            g_push_rax();
            expect("=");
            parse_expr();
            expect(";");
            g_pop_rcx();
            if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
            return 0;
        }
        if tok_is(".") == 1 {
            let sy: i64 = sym_lookup(scratch2());
            if sy < 0 { return undef_err(scratch2()); }
            let ft: i64 = field_addr(sy);
            if ty_kind(ft) == 2 { return err_at2("cannot assign a struct value", gv(K_LINE), gv(K_COL)); }
            if tok_is("++") == 1 {
                next_token();
                expect(";");
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(ft) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                g_movabs_rax(1);
                g_pop_rcx();
                g_add();
                g_pop_rcx();
                if ty_kind(ft) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            if tok_is("--") == 1 {
                next_token();
                expect(";");
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(ft) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                g_movabs_rax(1);
                g_pop_rcx();
                g_sub();
                g_pop_rcx();
                if ty_kind(ft) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            if compound_op() > 0 {
                let cop3: i64 = compound_op();
                next_token();
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(ft) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                parse_expr();
                expect(";");
                g_pop_rcx();
                g_compound(cop3);
                g_pop_rcx();
                if ty_kind(ft) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            g_push_rax();
            expect("=");
            parse_expr();
            expect(";");
            g_pop_rcx();
            if ty_kind(ft) == 5 { g_store_at_b(); } else { g_store_at(); }
            return 0;
        }
        set_pos(save);
    }
    parse_expr();
    expect(";");
    return 0;
}

fn parse_let() -> i64 {
    memcpy(scratch2(), tokbuf());
    next_token();
    expect(":");
    if tok_is("i64") == 0 {
        if gv(K_TKIND) == 1 {
            let si: i64 = st_lookup(tokbuf());
            if si >= 0 {
                next_token();
                expect(";");
                let n: i64 = st_nfields(si);
                let addr: i64 = 268435456 + gv(K_DLEN);
                let j: i64 = 0;
                while j < n {
                    dquad(0);
                    j = j + 1;
                }
                if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                let id: i64 = sym_add(scratch2(), 2, addr, 0);
                store64(heap + O_STY + id * 8, ty_struct(si));
                return 0;
            }
        }
    }
    if tok_is("[") == 1 {
        let n: i64 = 0;
        next_token();
        if gv(K_TKIND) == 2 {
            n = gv(K_TIVAL);
        }
        next_token();
        expect("]");
        if n <= 0 { return err_atp("array length must be a positive constant", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let et: i64 = ty_int();
        if tok_is("i64") == 1 {
            next_token();
        } else {
            if tok_is("byte") == 1 {
                et = ty_byte();
                next_token();
            } else {
                if gv(K_TKIND) == 1 {
                    let si: i64 = st_lookup(tokbuf());
                    if si >= 0 {
                        et = ty_struct(si);
                        next_token();
                    } else {
                        return err_at2("unknown type", gv(K_LINE), gv(K_COL));
                    }
                } else {
                    return err_at2("expected a type", gv(K_LINE), gv(K_COL));
                }
            }
        }
        let esz: i64 = ty_size(et);
        let p: i64 = gv(K_CUROFF);
        let off: i64 = p - esz * (n - 1);
        # byte 数组必须把 K_CUROFF 压到 8 字节对齐。
        # 否则 [8] byte 占 [p-7, p]，而下一个 i64 变量拿到 off=p-8，
        # 占 [p-8, p-1] —— 两者重叠，i64 的写入会把数组内容冲掉。
        if esz == 1 {
            sv(K_CUROFF, ((p - esz * n) - 7) & -8);
        } else {
            sv(K_CUROFF, p - esz * n);
        }
        if accept("=") == 1 {
            if ty_kind(et) != 0 { if ty_kind(et) != 5 { return err_at2("cannot init a struct array this way", gv(K_LINE), gv(K_COL)); } }
            let v: i64 = gv(K_TIVAL);
            next_token();
            expect(";");
            if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            let id: i64 = sym_add(scratch2(), 1, off, 0);
            store64(heap + O_STY + id * 8, ty_array(et, n));
            let k: i64 = 0;
            while k < n {
                g_movabs_rax(v);
                if ty_kind(et) == 5 { g_store_local_b(off + k * esz); }
                else { g_store_local(off + k * esz); }
                k = k + 1;
            }
            return 0;
        }
        expect(";");
        if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let id: i64 = sym_add(scratch2(), 1, off, 0);
        store64(heap + O_STY + id * 8, ty_array(et, n));
        return 0;
    }
    # 标量声明：i64 / byte / ptr
    #   ptr 是「指向字节的指针」，专门用于字符串与字节缓冲区——
    #   有了它才能写 s[i]，否则字符串形参只能声明成 i64 然后用 load8 手算。
    let vt: i64 = ty_int();
    if accept("i64") == 1 {
        vt = ty_int();
    } else {
        if accept("byte") == 1 {
            vt = ty_byte();
        } else {
            if accept("ptr") == 1 {
                vt = ty_ptr(ty_byte());
            } else {
                return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
        }
    }
    expect("=");
    parse_expr();
    expect(";");
    let off: i64 = gv(K_CUROFF);
    sv(K_CUROFF, off - 8);
    if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let id: i64 = sym_add(scratch2(), 1, off, 0);
    store64(heap + O_STY + id * 8, vt);
    if ty_kind(vt) == 5 { g_store_local_b(off); }
    else { g_store_local(off); }
    return 0;
}

# if / else if / else 链。
# 用迭代而非递归：整条链共用一个出口标签 end，每一轮各有一个「下一分支」标签。
# 这样 else if 不会层层嵌套、也不会为每层多生成一对 jmp/label。
fn parse_if() -> i64 {
    let d: i64 = gv(K_DEPTH) + 1;
    let end: i64 = new_label();
    let more: i64 = 1;
    while more == 1 {
        parse_expr();
        g_cmp_rax_0();
        let els: i64 = new_label();
        emit_jcc(0x84, els);
        parse_block(d);
        emit_jmp(end);
        place_label(els);
        if accept("else") == 1 {
            if accept("if") == 1 {
                more = 1;
            } else {
                parse_block(d);
                more = 0;
            }
        } else {
            more = 0;
        }
    }
    place_label(end);
    return 0;
}

fn parse_while() -> i64 {
    let d: i64 = gv(K_DEPTH) + 1;
    let a: i64 = new_label();
    let b: i64 = new_label();
    loop_push(a, b, -1);
    place_label(a);
    parse_expr();
    g_cmp_rax_0();
    emit_jcc(0x84, b);
    parse_block(d);
    emit_jmp(a);
    place_label(b);
    loop_pop();
    return 0;
}

# for (init; cond; step) { body }
#   展开为：init; while (cond) { body; __step: step; }
# 关键点：continue 要跳到 step，不是跳到循环头 ——
# 否则 continue 会跳过 i++ 直接回到条件判断，造成死循环。
# 这正是循环栈要多存一个 stp 标签的原因。
# for 的步进子句：不以 ';' 结尾，所以不能直接用 parse_stmt。
# 支持 i++ / i-- / i OP= expr / i = expr，其余当表达式丢弃结果。
fn parse_for_step() -> i64 {
    if gv(K_TKIND) == 1 {
        memcpy(scratch2(), tokbuf());
        next_token();
        if tok_is("++") == 1 {
            next_token();
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            load_sym(R_SYM);
            g_push_rax();
            g_movabs_rax(1);
            g_pop_rcx();
            g_add();
            store_sym(R_SYM);
            return 0;
        }
        if tok_is("--") == 1 {
            next_token();
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            load_sym(R_SYM);
            g_push_rax();
            g_movabs_rax(1);
            g_pop_rcx();
            g_sub();
            store_sym(R_SYM);
            return 0;
        }
        if compound_op() > 0 {
            let fs: i64 = compound_op();
            next_token();
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            load_sym(R_SYM);
            g_push_rax();
            parse_expr();
            g_pop_rcx();
            g_compound(fs);
            store_sym(R_SYM);
            return 0;
        }
        if tok_is("=") == 1 {
            next_token();
            parse_expr();
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            store_sym(R_SYM);
            return 0;
        }
        set_pos(gv(K_TOKPOS));
    }
    parse_expr();
    return 0;
}

fn parse_for() -> i64 {
    expect("(");
    let d: i64 = gv(K_DEPTH) + 1;
    # init
    if tok_is(";") == 0 {
        if accept("let") == 1 { parse_let(); } else { parse_expr(); expect(";"); }
    } else {
        next_token();
    }
    let a: i64 = new_label();
    let b: i64 = new_label();
    let c: i64 = new_label();
    loop_push(a, b, c);
    place_label(a);
    # cond
    if tok_is(";") == 1 {
        g_movabs_rax(1);
    } else {
        parse_expr();
    }
    expect(";");
    g_cmp_rax_0();
    emit_jcc(0x84, b);
    # body
    parse_block(d);
    next_token();
    # step（continue 跳到这里）
    place_label(c);
    if tok_is(")") == 0 {
        parse_for_step();
    }
    expect(")");
    emit_jmp(a);
    place_label(b);
    loop_pop();
    return 0;
}

fn parse_return() -> i64 {
    sv(K_HASRET, 1);
    if tok_is(";") == 1 {
        return err_atp("return with no value in a function returning i64", gv(K_LINE), gv(K_COL), gv(K_TOKPOS));
    }
    parse_expr();
    expect(";");
    g_epilogue();
    return 0;
}

fn parse_global() -> i64 {
    next_token();
    memcpy(scratch2(), tokbuf());
    next_token();
    expect(":");
    if tok_is("i64") == 0 {
        if gv(K_TKIND) == 1 {
            let si: i64 = st_lookup(tokbuf());
            if si >= 0 {
                next_token();
                expect(";");
                let n: i64 = st_nfields(si);
                let addr: i64 = 268435456 + gv(K_DLEN);
                let j: i64 = 0;
                while j < n {
                    dquad(0);
                    j = j + 1;
                }
                let id: i64 = sym_add(scratch2(), 2, addr, 0);
                store64(heap + O_STY + id * 8, ty_struct(si));
                return 0;
            }
        }
    }
    if tok_is("[") == 1 {
        let n: i64 = 0;
        next_token();
        if gv(K_TKIND) == 2 {
            n = gv(K_TIVAL);
        }
        next_token();
        expect("]");
        if n <= 0 { return err_atp("array length must be a positive constant", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let et: i64 = ty_int();
        if tok_is("i64") == 1 {
            next_token();
        } else {
            if tok_is("byte") == 1 {
                et = ty_byte();
                next_token();
            } else {
                if gv(K_TKIND) == 1 {
                    let si: i64 = st_lookup(tokbuf());
                    if si >= 0 {
                        et = ty_struct(si);
                        next_token();
                    } else {
                        return err_at2("unknown type", gv(K_LINE), gv(K_COL));
                    }
                } else {
                    return err_at2("expected a type", gv(K_LINE), gv(K_COL));
                }
            }
        }
        expect("=");
        let v: i64 = gv(K_TIVAL);
        next_token();
        expect(";");
        let addr: i64 = 268435456 + gv(K_DLEN);
        let esz: i64 = ty_size(et);
        let i: i64 = 0;
        if ty_kind(et) == 5 {
            # byte 数组：一个元素一个字节。
            # 原来走的是 esz/8 = 0 的分支——一个字节都没分配，
            # 于是数组地址直接落在下一个全局变量上，写数组就是写别人。
            while i < n {
                dbyte(v & 255);
                i = i + 1;
            }
            # 补齐到 8 字节，让后面的全局变量仍对齐
            while (gv(K_DLEN) & 7) != 0 {
                dbyte(0);
            }
        } else {
            while i < n {
                if ty_kind(et) == 0 {
                    dquad(v);
                } else {
                    let j: i64 = 0;
                    while j < esz / 8 {
                        dquad(0);
                        j = j + 1;
                    }
                }
                i = i + 1;
            }
        }
        if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let id: i64 = sym_add(scratch2(), 2, addr, 0);
        store64(heap + O_STY + id * 8, ty_array(et, n));
        return 0;
    }
    let vt: i64 = ty_int();
    if accept("i64") == 1 {
        vt = ty_int();
    } else {
        if accept("byte") == 1 {
            vt = ty_byte();
        } else {
            return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
        }
    }
    expect("=");
    let v: i64 = gv(K_TIVAL);
    next_token();
    expect(";");
    let addr: i64 = 268435456 + gv(K_DLEN);
    dquad(v);
    if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let id: i64 = sym_add(scratch2(), 2, addr, 0);
    store64(heap + O_STY + id * 8, vt);
    return 0;
}

fn parse_func() -> i64 {
    next_token();
    memcpy(scratch2(), tokbuf());
    let fnln: i64 = gv(K_LINE);
    let fncol: i64 = gv(K_COL);
    let fnpos: i64 = gv(K_TOKPOS);
    next_token();
    expect("(");
    sv(K_DEPTH, 1);
    sv(K_CUROFF, -8);
    let nb: i64 = 0;
    let addr: i64 = 4194304 + 176 + gv(K_CLEN);
    let ex: i64 = sym_lookup_func(scratch2());
    let fsi: i64 = ex;
    if ex >= 0 {
        if sym_addr(ex) != 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        store64(heap + O_SA + ex * 8, addr);
    } else {
        fsi = sym_add(scratch2(), 0, addr, 0);
    }
    let ra: i64 = gv(K_NSYM);
    while tok_is(")") == 0 {
        memcpy(scratch1(), tokbuf());
        next_token();
        expect(":");
        let pt: i64 = ty_int();
        if accept("i64") == 1 {
            pt = ty_int();
        } else {
            if accept("byte") == 1 {
                pt = ty_byte();
            } else {
                if accept("ptr") == 1 {
                    pt = ty_ptr(ty_byte());
                } else {
                    return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
            }
        }
        let off: i64 = gv(K_CUROFF);
        sv(K_CUROFF, off - 8);
        if sym_dup(scratch1()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let pid: i64 = sym_add(scratch1(), 1, off, 0);
        store64(heap + O_STY + pid * 8, pt);
        nb = nb + 1;
        if accept(",") == 0 {
            if tok_is(")") == 0 { return syntax_error(); }
        }
    }
    expect(")");
    expect("->");
    expect("i64");
    store64(heap + O_SP + fsi * 8, nb);
    g_prologue();
    let i: i64 = 0;
    while i < nb {
        emit_store_arg(-8 * (i + 1), i, nb);
        i = i + 1;
    }
    sv(K_HASRET, 0);
    parse_block(2);
    if gv(K_HASRET) == 0 {
        return err_atp("missing return statement in a function returning i64", fnln, fncol, fnpos);
    }
    let frame: i64 = 0 - gv(K_CUROFF);
    frame = (frame + 15) & -16;
    let pp: i64 = gv(K_FPATCH);
    store8(heap + O_CODE + pp, frame & 255);
    store8(heap + O_CODE + pp + 1, (frame >> 8) & 255);
    store8(heap + O_CODE + pp + 2, (frame >> 16) & 255);
    store8(heap + O_CODE + pp + 3, (frame >> 24) & 255);
    g_epilogue();
    sv(K_NSYM, ra);
    sv(K_DEPTH, 0);
    return 0;
}

fn next_line(p: i64) -> i64 {
    let n: i64 = gv(K_SRCLEN);
    while p < n {
        if sbyte(p) == 10 { return p + 1; }
        p = p + 1;
    }
    return p;
}

# 预扫描：把顶层 fn 名登记为函数符号，使前向与互递归调用可用
fn predeclare() -> i64 {
    let p: i64 = 0;
    let n: i64 = gv(K_SRCLEN);
    while p < n {
        let c: i64 = sbyte(p);
        if c == 35 {
            p = skip_comment(p);
        } else {
            if c == 102 {
                if sbyte(p + 1) == 110 {
                    if sbyte(p + 2) == 32 {
                        let q: i64 = p + 3;
                        let i: i64 = 0;
                        let b: i64 = scratch1();
                        while is_alnum(sbyte(q + i)) == 1 {
                            store8(b + i, sbyte(q + i));
                            i = i + 1;
                        }
                        store8(b + i, 0);
                        if sbyte(q + i) == 40 {
                            # 数形参个数：扫到 ')' 或行尾，按逗号计
                            let np: i64 = 0;
                            let any: i64 = 0;
                            let j: i64 = q + i + 1;
                            while sbyte(j) != 41 {
                                if sbyte(j) == 10 { j = j - 1; }
                                else {
                                    if sbyte(j) == 44 { np = np + 1; }
                                    else { any = 1; }
                                }
                                j = j + 1;
                            }
                            if any == 1 { np = np + 1; }
                            let sid: i64 = sym_add(b, 0, 0, np);
                        }
                        p = next_line(p);
                    } else {
                        p = next_line(p);
                    }
                } else {
                    p = next_line(p);
                }
            } else {
                p = next_line(p);
            }
        }
    }
    return 0;
}

# 读取并编译 import 的另一个源文件（共享符号表与代码/数据缓冲）
# 已导入过该文件则返回 1（跳过），否则登记并返回 0
fn imp_seen(path: i64) -> i64 {
    let n: i64 = gv(K_NIMP);
    let i: i64 = 0;
    while i < n {
        if streq(heap + O_NAMES + load64(heap + O_IMP + i * 8), path) == 1 { return 1; }
        i = i + 1;
    }
    store64(heap + O_IMP + n * 8, intern(path));
    sv(K_NIMP, n + 1);
    return 0;
}

# 依次尝试若干路径，返回第一个能打开的 fd；全失败返回 -1
#   1) 原样
#   2) lib/<basename>
#   3) ../lib/<basename>
# 让 examples/ 下的程序写 import "io.mo" 就能用上标准库，不必手工拷贝。
var SP_BUF: i64 = 7416760;

# 依次尝试若干路径，返回第一个能打开的 fd；全失败返回 -1
#   1) 原样  2) lib/<basename>  3) ../lib/<basename>
# 让 examples/ 下的程序写 import "io.mo" 就能用上标准库，不必手工拷贝。
# 拼接缓冲直接取 O_SCAL 里的空闲区，不用全局变量（省得再占一个数据段槽）。
fn try_open(path: i64) -> i64 {
    let fd: i64 = syscall(2, path, 0, 0, 0, 0, 0);
    if fd >= 0 { return fd; }
    let b: i64 = path;
    let i: i64 = strlen(path);
    while i > 0 {
        if load8(path + i - 1) == 47 { b = path + i; i = 0; }
        else { i = i - 1; }
    }
    let p: i64 = heap + O_SCAL + 3000;
    let q: i64 = "lib/";
    let j: i64 = 0;
    while load8(q + j) != 0 {
        store8(p + j, load8(q + j));
        j = j + 1;
    }
    let k: i64 = 0;
    while load8(b + k) != 0 {
        store8(p + j + k, load8(b + k));
        k = k + 1;
    }
    store8(p + j + k, 0);
    fd = syscall(2, p, 0, 0, 0, 0, 0);
    if fd >= 0 { return fd; }
    let p2: i64 = p + 256;
    let q2: i64 = "../lib/";
    j = 0;
    while load8(q2 + j) != 0 {
        store8(p2 + j, load8(q2 + j));
        j = j + 1;
    }
    k = 0;
    while load8(b + k) != 0 {
        store8(p2 + j + k, load8(b + k));
        k = k + 1;
    }
    store8(p2 + j + k, 0);
    fd = syscall(2, p2, 0, 0, 0, 0, 0);
    if fd >= 0 { return fd; }
    # 启元系统标准库路径：/usr/lib/mo/<basename>
    # （墨语言作为启元官方开发语言，标准库随 mo 包装入系统）
    let p3: i64 = p + 512;
    let q3: i64 = "/usr/lib/mo/";
    j = 0;
    while load8(q3 + j) != 0 {
        store8(p3 + j, load8(q3 + j));
        j = j + 1;
    }
    k = 0;
    while load8(b + k) != 0 {
        store8(p3 + j + k, load8(b + k));
        k = k + 1;
    }
    store8(p3 + j + k, 0);
    return syscall(2, p3, 0, 0, 0, 0, 0);
}

fn compile_file(path: i64) -> i64 {
    if imp_seen(path) == 1 { return 0; }
    let s_srclen: i64 = gv(K_SRCLEN);
    let s_tok: i64 = gv(K_TOKPOS);
    let s_base: i64 = gv(K_SRCBASE);
    let s_in: i64 = INPATH;

    let k: i64 = gv(K_NFILE);
    if k >= 8 { return die("too many imported files\n"); }
    sv(K_NFILE, k + 1);
    let base: i64 = O_FILES + k * 1048576;

    let fd: i64 = try_open(path);
    if fd < 0 {
        syscall(1, 2, "cannot open import: ", 20, 0, 0, 0);
        syscall(1, 2, path, strlen(path), 0, 0, 0);
        syscall(1, 2, "\n", 1, 0, 0, 0);
        syscall(60, 1, 0, 0, 0, 0, 0);
    }
    let n: i64 = syscall(0, fd, heap + base, 1048575, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);

    sv(K_SRCBASE, base);
    sv(K_SRCLEN, n);
    sv(K_POS, 0);
    sv(K_CPOS, 0);
    sv(K_LINE, 1);
    sv(K_COL, 1);
    INPATH = path;

    parse_program();

    sv(K_SRCBASE, s_base);
    sv(K_SRCLEN, s_srclen);
    INPATH = s_in;
    set_pos(s_tok);
    return 0;
}

fn parse_import() -> i64 {
    next_token();
    if gv(K_TKIND) != 3 { return syntax_error(); }
    let p: i64 = strpool();
    next_token();
    expect(";");
    # import 进来的文件不记行号：它的行号属于另一个源文件，
    # 混进主文件的行号表会错乱。用局部变量保存开关原值，嵌套 import 也安全。
    let olddbg: i64 = gv(K_DBG);
    sv(K_DBG, 0);
    let r: i64 = compile_file(p);
    sv(K_DBG, olddbg);
    return r;
}

# struct Name { f: i64; g: Other; }
fn parse_struct() -> i64 {
    next_token();
    if gv(K_TKIND) != 1 { return syntax_error(); }
    memcpy(scratch2(), tokbuf());
    next_token();
    let si: i64 = st_add(scratch2());
    expect("{");
    while tok_is("}") == 0 {
        if gv(K_TKIND) != 1 { return syntax_error(); }
        memcpy(scratch1(), tokbuf());
        next_token();
        expect(":");
        let ft: i64 = ty_int();
        if tok_is("i64") == 1 {
            next_token();
        } else {
            if gv(K_TKIND) == 1 {
                let sub: i64 = st_lookup(tokbuf());
                if sub >= 0 {
                    ft = ty_struct(sub);
                    next_token();
                } else {
                    return err_at2("unknown type", gv(K_LINE), gv(K_COL));
                }
            } else {
                return err_at2("expected a type", gv(K_LINE), gv(K_COL));
            }
        }
        st_add_field(si, scratch1(), ft);
        expect(";");
    }
    next_token();
    return 0;
}

fn parse_program() -> i64 {
    predeclare();
    next_token();
    while gv(K_TKIND) != 0 {
        if tok_is("import") == 1 {
            parse_import();
        } else {
            if tok_is("struct") == 1 {
                parse_struct();
            } else {
                if tok_is("var") == 1 {
                    parse_global();
                } else {
                    if tok_is("fn") == 1 {
                        parse_func();
                    } else {
                        return syntax_error();
                    }
                }
            }
        }
    }
    return 0;
}

# ==========================================================================
#  回填
# ==========================================================================
fn resolve_all() -> i64 {
    let i: i64 = 0;
    while i < gv(K_NFNP) {
        let p: i64 = load64(heap + O_FP + i * 8);
        let a: i64 = sym_addr(load64(heap + O_FS + i * 8));
        let j: i64 = 0;
        while j < 8 {
            store8(heap + O_CODE + p + j, (a >> (j * 8)) & 255);
            j = j + 1;
        }
        i = i + 1;
    }
    i = 0;
    while i < gv(K_NJMP) {
        let p: i64 = load64(heap + O_JP + i * 8);
        let t: i64 = load64(heap + O_LB + load64(heap + O_JL + i * 8) * 8);
        let r: i64 = t - p - 4;
        store8(heap + O_CODE + p, r & 255);
        store8(heap + O_CODE + p + 1, (r >> 8) & 255);
        store8(heap + O_CODE + p + 2, (r >> 16) & 255);
        store8(heap + O_CODE + p + 3, (r >> 24) & 255);
        i = i + 1;
    }
    return 0;
}

# ==========================================================================
#  ELF64 输出
# ==========================================================================
var O_ELF:   i64 = 7471104;
var O_ZERO:  i64 = 7471280;
var MAINPAT: i64 = 0;

fn zero_elf() -> i64 {
    let i: i64 = 0;
    while i < 176 {
        store8(heap + O_ELF + i, 0);
        i = i + 1;
    }
    return 0;
}

# 启动：先把 argc / argv 存进数据段头 16 字节，再调 main
#   入口时 rsp -> argc, rsp+8 -> argv[0] 指针
#   数据段虚拟地址 0x10000000 起：+0 存 argc，+8 存 argv 指针
fn emit_startup() -> i64 {
    # mov rax, [rsp]              ; argc
    ops3(0x48, 0x8b, 0x04);
    emit1(0x24);
    # mov r11, 0x10000000
    ops2(0x49, 0xbb);
    emit8(268435456);
    # mov [r11], rax
    ops3(0x49, 0x89, 0x03);
    # lea rcx, [rsp+8]
    ops3(0x48, 0x8d, 0x4c);
    ops2(0x24, 0x08);
    # mov [r11+8], rcx
    ops3(0x49, 0x89, 0x4b);
    emit1(8);
    ops2(0x48, 0xb8);
    MAINPAT = gv(K_CLEN);
    emit8(0);
    # 调用前必须先落栈：被调函数里的 push 会 spill 调用者缓存在 rbx 里的值，
    # 把它压进被调函数的栈帧，调用者返回后取回的就是错的
    spill_cache();
    ops2(0xff, 0xd0);
    ops3(0x48, 0x89, 0xc7);
    ops3(0x48, 0xc7, 0xc0);
    emit4(60);
    ops2(0x0f, 0x05);
    return 0;
}

fn build_elf(entry: i64) -> i64 {
    zero_elf();
    let e: i64 = heap + O_ELF;
    store8(e, 0x7f);
    store8(e + 1, 0x45);
    store8(e + 2, 0x4c);
    store8(e + 3, 0x46);
    store8(e + 4, 2);
    store8(e + 5, 1);
    store8(e + 6, 1);
    store8(e + 16, 2);
    store8(e + 18, 0x3e);
    store8(e + 20, 1);
    store64(e + 24, entry);
    store64(e + 32, 64);
    store8(e + 52, 64);
    store8(e + 54, 56);
    store8(e + 56, 2);
    let sz: i64 = (gv(K_CLEN) + 176 + 4095) & -4096;
    let p1: i64 = e + 64;
    store8(p1, 1);
    store8(p1 + 4, 5);
    store64(p1 + 8, 0);
    store64(p1 + 16, 4194304);
    store64(p1 + 24, 4194304);
    store64(p1 + 32, sz);
    store64(p1 + 40, sz);
    store64(p1 + 48, 4096);
    let p2: i64 = e + 120;
    store8(p2, 1);
    store8(p2 + 4, 6);
    store64(p2 + 8, sz);
    store64(p2 + 16, 268435456);
    store64(p2 + 24, 268435456);
    store64(p2 + 32, gv(K_DLEN));
    store64(p2 + 40, gv(K_DLEN));
    store64(p2 + 48, 4096);
    return 0;
}

fn write_all(fd: i64, p: i64, n: i64) -> i64 {
    syscall(1, fd, p, n, 0, 0, 0);
    return 0;
}

# ==========================================================================
#  main
# ==========================================================================
var OUTPATH: i64 = 0;

# ============ DWARF 生成（-g）============
# 只生成最小可用集：.debug_info（一个 CU DIE）+ .debug_abbrev + .debug_line。
# 够 gdb 做到「按源码行下断点、看行号」，不含变量、类型、栈帧信息。

fn gen_info() -> i64 {
    sv(K_DBBASE, 0);
    sv(K_DBGLEN, 0);
    db_u32(0);                 # unit_length（稍后回填）
    db_u16(4);                 # version 4
    db_u32(0);                 # debug_abbrev_offset
    db_u8(8);                  # address_size
    db_uleb(1);                # abbrev code
    db_str(INPATH);            # DW_AT_name
    let cl0: i64 = gv(K_CLEN);
    db_u64(4194480);           # DW_AT_low_pc  = 代码段起始虚址
    db_u64(4194480 + cl0);     # DW_AT_high_pc
    db_u32(0);                 # DW_AT_stmt_list（.debug_line 内偏移 0）
    db_str("mo compiler");     # DW_AT_producer
    db_u16(12);                # DW_AT_language = DW_LANG_C89
    let il: i64 = gv(K_DBGLEN);
    db_poke32(0, il - 4);
    sv(K_INFOLEN, il);
    return 0;
}

fn gen_abbrev() -> i64 {
    sv(K_DBBASE, 262144);
    sv(K_DBGLEN, 0);
    db_uleb(1);                # abbrev code
    db_uleb(17);               # DW_TAG_compile_unit
    db_u8(0);                  # DW_CHILDREN_no
    db_uleb(3);  db_uleb(8);   # DW_AT_name     DW_FORM_string
    db_uleb(17); db_uleb(1);   # DW_AT_low_pc   DW_FORM_addr
    db_uleb(18); db_uleb(1);   # DW_AT_high_pc  DW_FORM_addr
    db_uleb(16); db_uleb(6);   # DW_AT_stmt_list DW_FORM_data4
    db_uleb(37); db_uleb(8);   # DW_AT_producer DW_FORM_string
    db_uleb(19); db_uleb(5);   # DW_AT_language DW_FORM_data2
    db_uleb(0);  db_uleb(0);   # 属性列表结束
    let al: i64 = gv(K_DBGLEN);
    sv(K_ABBRLEN, al);
    return 0;
}

fn gen_line() -> i64 {
    sv(K_DBBASE, 327680);
    sv(K_DBGLEN, 0);
    db_u32(0);                 # unit_length（回填）
    db_u16(4);                 # version 4
    let hpos: i64 = gv(K_DBGLEN);
    db_u32(0);                 # header_length（回填）
    let hstart: i64 = gv(K_DBGLEN);
    db_u8(1);                  # minimum_instruction_length
    db_u8(1);                  # maximum_operations_per_instruction
    db_u8(1);                  # default_is_stmt
    db_u8(251);                # line_base  = -5
    db_u8(14);                 # line_range = 14
    db_u8(13);                 # opcode_base
    # standard_opcode_lengths[12]
    db_u8(0); db_u8(1); db_u8(1); db_u8(1); db_u8(1); db_u8(0);
    db_u8(0); db_u8(0); db_u8(1); db_u8(0); db_u8(0); db_u8(1);
    # include_directories：空（只有一个结尾 NUL 表示表结束）
    db_u8(0);
    # file_names：只有主文件（dir=0, mtime=0, length=0）
    db_str(INPATH);
    db_u8(0); db_u8(0); db_u8(0);
    db_u8(0);                  # file table 结束
    let hl: i64 = gv(K_DBGLEN);
    db_poke32(hpos, hl - hstart);

    # ---- line number program ----
    # 只用最保守的三种操作：set_file / advance_line / advance_pc + copy。
    # 不用 special opcode，避免因 line_base/line_range 算错而整体错位。
    let cur: i64 = 0;
    let cline: i64 = 1;
    let i: i64 = 0;
    let n: i64 = gv(K_NLM);
    while i < n {
        let a: i64 = load64(DBG + O_LM + i * 16);
        let ln: i64 = load64(DBG + O_LM + i * 16 + 8);
        if ln != cline {
                db_u8(3);              # DW_LNS_advance_line
                db_sleb(ln - cline);
                cline = ln;
            }
            if a + 4194480 != cur {
                db_u8(2);              # DW_LNS_advance_pc
                db_uleb(a + 4194480 - cur);
                cur = a + 4194480;
            }
        db_u8(1);                      # DW_LNS_copy
        i = i + 1;
    }
    # end_sequence：把地址推到代码末尾再收尾
    let enda: i64 = 4194480 + gv(K_CLEN);
    if enda != cur {
        db_u8(2);
        db_uleb(enda - cur);
    }
    db_u8(0); db_u8(1); db_u8(1);      # DW_LNE_end_sequence
    let ll: i64 = gv(K_DBGLEN);
    db_poke32(0, ll - 4);
    sv(K_LINELEN, ll);
    return 0;
}

# section 名字符串表。名字固定，偏移写死（省去回传六个偏移量）：
#   .text(1) .data(7) .debug_info(13) .debug_abbrev(25) .debug_line(39) .shstrtab(51)
fn gen_shstr() -> i64 {
    sv(K_DBBASE, 917504);
    sv(K_DBGLEN, 0);
    db_u8(0);
    db_str(".text");
    db_str(".data");
    db_str(".debug_info");
    db_str(".debug_abbrev");
    db_str(".debug_line");
    db_str(".shstrtab");
    let sl: i64 = gv(K_DBGLEN);
    sv(K_SHSTRLEN, sl);
    return 0;
}

# 写一条 section header（每项 64 字节）。
# 刻意拆成两个不超过 5 个参数的函数：参数 7 个以上要走栈上传参，
# 那条路径刚修过但还没被真实程序验证过；寄存器传参（<=6）则是
# 编译器从一开始就走的路。这里不需要冒这个险。
fn sh_hdr(i: i64, name: i64, typ: i64, flags: i64, addr: i64) -> i64 {
    let p: i64 = DBG + O_SHDR + i * 64;
    store32(p, name);
    store32(p + 4, typ);
    store64(p + 8, flags);
    store64(p + 16, addr);
    return 0;
}

fn sh_rest(i: i64, off: i64, size: i64, align: i64) -> i64 {
    let p: i64 = DBG + O_SHDR + i * 64;
    store64(p + 24, off);
    store64(p + 32, size);
    store32(p + 40, 0);
    store32(p + 44, 0);
    store64(p + 48, align);
    store64(p + 56, 0);
    return 0;
}

fn gen_shdr(base: i64, sz: i64) -> i64 {
    let o: i64 = base;
    # 0: NULL
    sh_hdr(0, 0, 0, 0, 0);
    sh_rest(0, 0, 0, 0);
    # 1: .text —— vaddr 4194304 对应文件 offset 0，所以代码在 176 处
    # 实参里一律先取到局部变量，避免嵌套调用覆盖函数名缓冲
    let c1: i64 = gv(K_CLEN);
    let d1: i64 = gv(K_DLEN);
    let i1: i64 = gv(K_INFOLEN);
    let a1: i64 = gv(K_ABBRLEN);
    let l1: i64 = gv(K_LINELEN);
    let s1: i64 = gv(K_SHSTRLEN);
    sh_hdr(1, 1, 1, 6, 4194480);
    sh_rest(1, 176, c1, 16);
    sh_hdr(2, 7, 1, 3, 268435456);
    sh_rest(2, sz, d1, 8);
    sh_hdr(3, 13, 1, 0, 0);
    sh_rest(3, o, i1, 1);
    o = o + i1;
    sh_hdr(4, 25, 1, 0, 0);
    sh_rest(4, o, a1, 1);
    o = o + a1;
    sh_hdr(5, 39, 1, 0, 0);
    sh_rest(5, o, l1, 1);
    o = o + l1;
    sh_hdr(6, 51, 3, 0, 0);
    sh_rest(6, o, s1, 1);
    o = o + s1;
    # ELF header 里补上节头表位置
    let e: i64 = heap + O_ELF;
    store64(e + 40, o);
    store16(e + 58, 64);
    store16(e + 60, 7);
    store16(e + 62, 6);
    return 0;
}

fn main() -> i64 {
    # 申请堆：brk 到 16MB
    let brk: i64 = syscall(12, 0, 0, 0, 0, 0, 0);
    let need: i64 = brk + 100663296;
    syscall(12, need, 0, 0, 0, 0, 0);
    heap = brk + 4096;
    # 调试数据单独申请 4MB，放在主堆之后。
    # 主堆里的字符串池（O_STRS 起）会一直增长，早先调试区放在主堆内部，
    # 编译自身时被它覆盖，行号表读出来全是字符串内容。
    let need2: i64 = need + 4194304;
    syscall(12, need2, 0, 0, 0, 0, 0);
    DBG = need + 4096;

    # 命令行：argv[1] 为输入，argv[2] 为输出（缺省 test.mo / out.elf）
    let inpath: i64 = "test.mo";
    let outpath: i64 = "out.elf";
    let npath: i64 = 0;
    sv(K_DBG, 0);
    let ai: i64 = 1;
    while ai < argc() {
        let a: i64 = argv(ai);
        if streq(a, "-g") == 1 {
            sv(K_DBG, 1);
        } else {
            if npath == 0 {
                inpath = a;
                npath = 1;
            } else {
                outpath = a;
            }
        }
        ai = ai + 1;
    }
    INPATH = inpath;

    # 读源文件
    let fd: i64 = syscall(2, inpath, 0, 0, 0, 0, 0);
    if fd < 0 { return die("cannot open input\n"); }
    let n: i64 = syscall(0, fd, heap + O_SRC, 4194303, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    sv(K_SRCLEN, n);
    sv(K_POS, 0);
    sv(K_LINE, 1);
    sv(K_COL, 1);
    sv(K_CPOS, 0);
    sv(K_SRCBASE, O_SRC);
    sv(K_NFILE, 0);
    sv(K_NSTR, 0);
    sv(K_NSTRUCT, 0);
    sv(K_NIMP, 0);
    sv(K_PANIC, 0 - 1);
    sv(K_PJMP, 0);
    sv(K_NLM, 0);
    sv(K_CRBX, 0);
    ty_init();
    # 数据段头 16 字节留给 argc/argv，全局变量从 +16 开始
    dquad(0);
    dquad(0);

    emit_startup();
    parse_program();
    emit_panic();
    resolve_all();

    let m: i64 = sym_lookup_func("main");
    if m < 0 { return die("no main function\n"); }
    let ma: i64 = sym_addr(m);
    let j: i64 = 0;
    while j < 8 {
        store8(heap + O_CODE + MAINPAT + j, (ma >> (j * 8)) & 255);
        j = j + 1;
    }
    build_elf(4194304 + 176);

    # 调试信息：必须在写盘之前生成，因为它会改 ELF header（e_shoff 等）。
    # 不开启 -g 时这段不执行，输出字节与以前完全一致。
    if gv(K_DBG) == 1 {
        let sz: i64 = (gv(K_CLEN) + 176 + 4095) & -4096;
        gen_info();
        gen_abbrev();
        gen_line();
        gen_shstr();
        let dl: i64 = gv(K_DLEN);
        gen_shdr(sz + dl, sz);
    }

    let ofd: i64 = syscall(2, outpath, 577, 493, 0, 0, 0);
    if ofd < 0 { return die("cannot open output\n"); }
    write_all(ofd, heap + O_ELF, 176);
    write_all(ofd, heap + O_CODE, gv(K_CLEN));
    let pad: i64 = (4096 - ((gv(K_CLEN) + 176) & 4095)) & 4095;
    write_all(ofd, heap + O_ZERO, pad);
    write_all(ofd, heap + O_DATA, gv(K_DLEN));
    if gv(K_DBG) == 1 {
        write_all(ofd, DBG + O_DBG + 0, gv(K_INFOLEN));
        write_all(ofd, DBG + O_DBG + 262144, gv(K_ABBRLEN));
        write_all(ofd, DBG + O_DBG + 327680, gv(K_LINELEN));
        write_all(ofd, DBG + O_DBG + 917504, gv(K_SHSTRLEN));
        write_all(ofd, DBG + O_SHDR, 448);
    }
    syscall(3, ofd, 0, 0, 0, 0, 0);
    return 0;
}
