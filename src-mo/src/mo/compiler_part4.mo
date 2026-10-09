
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
var O_SCR:  i64 = 10600448;

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
            let lt: i64 = R_ETY;
            g_push_rax();
            parse_rel();
            let rt: i64 = R_ETY;
            g_pop_rcx();
            if f_bin_promote(lt, rt) == 1 {
                g_fint2f(lt);
                g_fint2f_r(rt);
                g_fcmp_set(0x94);
            } else {
                g_cmp_set(0x94);
            }
        } else {
            if accept("!=") == 1 {
                let lt2: i64 = R_ETY;
                g_push_rax();
                parse_rel();
                let rt2: i64 = R_ETY;
                g_pop_rcx();
                if f_bin_promote(lt2, rt2) == 1 {
                    g_fint2f(lt2);
                    g_fint2f_r(rt2);
                    g_fcmp_set(0x95);
                } else {
                    g_cmp_set(0x95);
                }
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
            let l1: i64 = R_ETY;
            g_push_rax();
            parse_shift();
            let r1: i64 = R_ETY;
            g_pop_rcx();
            if f_bin_promote(l1, r1) == 1 { g_fint2f(l1); g_fint2f_r(r1); g_fcmp_set(0x92); }
            else { g_cmp_set(0x9c); }
        } else {
            if accept("<=") == 1 {
                let l2: i64 = R_ETY;
                g_push_rax();
                parse_shift();
                let r2: i64 = R_ETY;
                g_pop_rcx();
                if f_bin_promote(l2, r2) == 1 { g_fint2f(l2); g_fint2f_r(r2); g_fcmp_set(0x96); }
                else { g_cmp_set(0x9e); }
            } else {
                if accept(">") == 1 {
                    let l3: i64 = R_ETY;
                    g_push_rax();
                    parse_shift();
                    let r3: i64 = R_ETY;
                    g_pop_rcx();
                    if f_bin_promote(l3, r3) == 1 { g_fint2f(l3); g_fint2f_r(r3); g_fcmp_set(0x97); }
                    else { g_cmp_set(0x9f); }
                } else {
                    if accept(">=") == 1 {
                        let l4: i64 = R_ETY;
                        g_push_rax();
                        parse_shift();
                        let r4: i64 = R_ETY;
                        g_pop_rcx();
                        if f_bin_promote(l4, r4) == 1 { g_fint2f(l4); g_fint2f_r(r4); g_fcmp_set(0x93); }
                        else { g_cmp_set(0x9d); }
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
            let lt: i64 = R_ETY;
            g_push_rax();
            parse_mul();
            let rt: i64 = R_ETY;
            g_pop_rcx();
            if f_bin_promote(lt, rt) == 1 {
                g_fint2f(lt);
                g_fint2f_r(rt);
                g_fop(0);
                R_ETY = ty_f64();
            } else {
                g_add();
                R_ETY = ty_int();
            }
        } else {
            if accept("-") == 1 {
                let lt2: i64 = R_ETY;
                g_push_rax();
                parse_mul();
                let rt2: i64 = R_ETY;
                g_pop_rcx();
                if f_bin_promote(lt2, rt2) == 1 {
                    g_fint2f(lt2);
                    g_fint2f_r(rt2);
                    g_fop(1);
                    R_ETY = ty_f64();
                } else {
                    g_sub();
                }
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
            let lt: i64 = R_ETY;
            g_push_rax();
            parse_unary();
            let rt: i64 = R_ETY;
            g_pop_rcx();
            if f_bin_promote(lt, rt) == 1 {
                g_fint2f(lt);
                g_fint2f_r(rt);
                g_fop(2);
                R_ETY = ty_f64();
            } else {
                g_imul();
                R_ETY = ty_int();
            }
        } else {
            if accept("/") == 1 {
                let lt2: i64 = R_ETY;
                g_push_rax();
                parse_unary();
                let rt2: i64 = R_ETY;
                g_pop_rcx();
                if f_bin_promote(lt2, rt2) == 1 {
                    g_fint2f(lt2);
                    g_fint2f_r(rt2);
                    g_fop(3);
                    R_ETY = ty_f64();
                } else {
                    g_idiv(0);
                }
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
    # &函数名 → 函数代码地址（函数符号 kind==0 与全局变量同区，
    # sym_lookup 只查 kind!=0？不——sym_lookup 查 kind!=0 失败，故先查函数表）
    let fy: i64 = sym_lookup_func(scratch1());
    if fy >= 0 {
        # 函数地址在 resolve 阶段才回填？否——函数地址在 parse_func 时
        # sym_add(name,0,addr,0) 已是最终代码地址（code 基址相对）。
        g_movabs_rax(sym_addr(fy));
        R_ETY = ty_int();
        return 0;
    }
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
        if ty_kind(R_ETY) == 6 {
            # f64 位模式只翻符号位：rax ^= 1<<63（不要走整数 neg）
            g_xor_imm63();
            return 0;
        }
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
    # f64 字面量：位模式当 i64 装进 rax，类型 f64
    if k == 5 {
        g_movabs_rax(gv(K_TIVAL));
        next_token();
        R_ETY = ty_f64();
        return 0;
    }
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
            # 函数指针数组：ops[i](args) —— 元素值是代码地址，直接间接调用
            if tok_is("(") == 1 {
                next_token();
                let na2: i64 = 0;
                while tok_is(")") == 0 {
                    parse_expr();
                    g_push_rax();
                    na2 = na2 + 1;
                    if accept(",") == 0 {
                        if tok_is(")") == 0 { return syntax_error(); }
                    }
                }
                expect(")");
                # 被调地址已在 rax（栈上是参数），先存 rax 再弹参
                g_push_rax();          # 保住地址
                if na2 >= 6 { g_pop_r9(); }
                if na2 >= 5 { g_pop_r8(); }
                if na2 >= 4 { g_pop_rcx(); }
                if na2 >= 3 { g_pop_rdx(); }
                if na2 >= 2 { g_pop_rsi(); }
                if na2 >= 1 { g_pop_rdi(); }
                g_pop_rax();           # 恢复地址
                spill_cache();
                ops2(0xff, 0xd0);      # call rax
                R_ETY = ty_int();
            }
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
    if streq(cscratch(), "fabs") == 1 {
        g_pop_rax();
        ops4(0x66, 0x48, 0x0f, 0x6e); emit1(0xc0);   # movq xmm0, rax
        ops2(0x49, 0xbb); emit8(0x7fffffffffffffff); # movabs r11, mask
        ops4(0x66, 0x49, 0x0f, 0x6e); emit1(0xcb);   # movq xmm1, r11
        ops4(0x66, 0x0f, 0x54, 0xc1);                # andpd xmm0, xmm1
        ops4(0x66, 0x48, 0x0f, 0x7e); emit1(0xc0);   # movq rax, xmm0
        CALLD = CALLD - 1;
        R_ETY = ty_f64();
        return 0;
    }
    if streq(cscratch(), "fmin") == 1 {
        g_pop_rax();              # 右
        g_movq_rax_xmm1();
        g_pop_rcx();              # 左
        g_movq_rcx_xmm0();
        # minsd xmm0, xmm1: F2 0F 5D C1
        ops4(0xf2, 0x0f, 0x5d, 0xc1);
        g_movq_xmm0_rax();
        CALLD = CALLD - 1;
        R_ETY = ty_f64();
        return 0;
    }
    if streq(cscratch(), "fmax") == 1 {
        g_pop_rax();
        g_movq_rax_xmm1();
        g_pop_rcx();
        g_movq_rcx_xmm0();
        # maxsd xmm0, xmm1: F2 0F 5F C1
        ops4(0xf2, 0x0f, 0x5f, 0xc1);
        g_movq_xmm0_rax();
        CALLD = CALLD - 1;
        R_ETY = ty_f64();
        return 0;
    }
    # int -> f64 / f64 -> int（截断）显式转换
    if streq(cscratch(), "itof") == 1 {
        g_pop_rax();
        # cvtsi2sd xmm0, rax
        ops4(0xf2, 0x48, 0x0f, 0x2a); emit1(0xc0);
        g_movq_xmm0_rax();
        CALLD = CALLD - 1;
        R_ETY = ty_f64();
        return 0;
    }
    if streq(cscratch(), "ftoi") == 1 {
        g_pop_rax();
        ops3(0x48, 0x89, 0xc1);                      # mov rcx, rax
        g_movq_rcx_xmm0();
        g_cvtsd2si();
        CALLD = CALLD - 1;
        R_ETY = ty_int();
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
    if R_SYM < 0 {
        # 不是已知函数：若是保存了函数地址的变量，走间接调用 call rax
        let vy: i64 = sym_lookup(cscratch());
        if vy < 0 {
            let cn: i64 = cscratch();
            CALLD = CALLD - 1;
            return undef_err(cn);
        }
        load_sym(vy);
        spill_cache();
        ops2(0xff, 0xd0);          # call rax
        CALLD = CALLD - 1;
        R_ETY = ty_int();
        return 0;
    }
    emit_call_patch(R_SYM);
    CALLD = CALLD - 1;
    return 0;
}
