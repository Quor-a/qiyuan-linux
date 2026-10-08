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
