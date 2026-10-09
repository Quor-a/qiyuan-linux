
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
    if accept("switch") == 1 { return parse_switch(); }
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
                if tok_is("f64") == 1 {
                    et = ty_f64();
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
            # byte 数组的字符串字面量初始化：let t: [32] byte = "abc"
            # 把字面量（已落在输出数据段，NUL 结尾）逐字节拷进局部数组。
            if ty_kind(et) == 5 && gv(K_TKIND) == 3 {
                # 字面量在编译器进程里读不到（该地址映射 moc 自身数据段，
                # 读到垃圾——见 skill 教训），必须从编译器字符串池 O_STRS 拷。
                let sa: i64 = strpool();   # 编译器侧可读地址（heap + O_STRS + STROFF）
                next_token();
                expect(";");
                if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                let id: i64 = sym_add(scratch2(), 1, off, 0);
                store64(heap + O_STY + id * 8, ty_array(et, n));
                let k2: i64 = 0;
                while k2 < n {
                    let c: i64 = load8(sa + k2);
                    g_movabs_rax(c);
                    g_store_local_b(off + k2);
                    if c == 0 { break; }
                    k2 = k2 + 1;
                }
                # 剩余槽清零
                k2 = k2 + 1;
                while k2 < n {
                    g_movabs_rax(0);
                    g_store_local_b(off + k2);
                    k2 = k2 + 1;
                }
                return 0;
            }
            if ty_kind(et) != 0 { if ty_kind(et) != 5 { if ty_kind(et) != 6 { return err_at2("cannot init a struct array this way", gv(K_LINE), gv(K_COL)); } } }
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
            if accept("f64") == 1 {
                vt = ty_f64();
            } else {
                if accept("ptr") == 1 {
                    vt = ty_ptr(ty_byte());
                } else {
                    return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
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

# switch <expr> { <val> { ... } <val> { ... } else { ... } }
# 生成顺序：对每个 case 先 cmp+jcc 跳到分支体，末尾统一 end。
# case 值必须是整型常量（字面量或 -字面量）；else 分支可选。
# break 落到 loop 栈（把 end 当 break 标签压入），复用 loop_brk。
fn parse_switch() -> i64 {
    # 开关值算进 rax；每个 case 用 cmp rax,imm / je L 直接比较——
    # 不用 g_push_rax/g_pop_rcx（常量折叠窥孔会改坏值，实战踩坑）。
    # else 为最后一段：先 jmp 到 els 让前面的 case 跳过它，再顺序放 else 体。
    parse_expr();
    let d: i64 = gv(K_DEPTH) + 1;
    let end: i64 = new_label();
    loop_push(-1, end, -1);          # break → switch 出口
    let els: i64 = -1;
    let has_els: i64 = 0;
    expect("{");
    while tok_is("}") == 0 {
        if accept("else") == 1 {
            has_els = 1;
            els = new_label();
            emit_jmp(els);           # 前面 case 命中后 jmp end，不会落到这里
            place_label(els);
            parse_block(d);          # 消费 else 的 { }
            emit_jmp(end);
            break;
        }
        let l: i64 = new_label();
        let v: i64 = 0;
        if gv(K_TKIND) == 2 {
            v = gv(K_TIVAL);
            next_token();
        } else {
            if accept("-") == 1 {
                if gv(K_TKIND) == 2 { v = -(gv(K_TIVAL)); next_token(); }
                else { return syntax_error(); }
            } else {
                return err_atp("switch case value must be an integer constant", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
        }
        # cmp rax, v ; je l
        if v >= -128 && v <= 127 {
            ops3(0x48, 0x83, 0xf8);
            emit1(v & 255);
        } else {
            ops2(0x48, 0x3d);
            emit4(v);
        }
        emit_jcc(0x85, l);        # jne skip：不命中则跳过本 case 体
        parse_block(d);
        emit_jmp(end);
        place_label(l);
    }
    expect("}");                     # switch 的收尾 }
    place_label(end);
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
                if tok_is("f64") == 1 {
                    et = ty_f64();
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
        }
        expect("=");
        # 全局 byte 数组的字符串字面量初始化：var g: [16] byte = "global"
        if ty_kind(et) == 5 && gv(K_TKIND) == 3 {
            let sa2: i64 = strpool();
            next_token();
            expect(";");
            let addr2: i64 = 268435456 + gv(K_DLEN);
            let i2: i64 = 0;
            while i2 < n {
                let c2: i64 = load8(sa2 + i2);
                dbyte(c2 & 255);
                if c2 == 0 { i2 = i2 + 1; break; }
                i2 = i2 + 1;
            }
            while i2 < n { dbyte(0); i2 = i2 + 1; }
            while (gv(K_DLEN) & 7) != 0 { dbyte(0); }
            if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            let id2: i64 = sym_add(scratch2(), 2, addr2, 0);
            store64(heap + O_STY + id2 * 8, ty_array(et, n));
            return 0;
        }
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
            if accept("f64") == 1 {
                vt = ty_f64();
                expect("=");
                # 浮点字面量 K_TKIND=5，位模式在 K_TIVAL/K_TFVAL（lex_number 写入）
                let fneg: i64 = 0;
                if accept("-") == 1 { fneg = 1; }
                if gv(K_TKIND) != 5 { return err_at2("expected a float literal", gv(K_LINE), gv(K_COL)); }
                let fv: i64 = gv(K_TIVAL) ^ (fneg * -9223372036854775808);
                next_token();
                expect(";");
                let faddr: i64 = 268435456 + gv(K_DLEN);
                dquad(fv);
                if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                let fid: i64 = sym_add(scratch2(), 2, faddr, 0);
                store64(heap + O_STY + fid * 8, vt);
                return 0;
            } else {
                return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
        }
    }
    expect("=");
    # 全局标量初始化支持带符号十进制（var x: i64 = -1 之前只认裸字面量）
    let v: i64 = 0;
    if gv(K_TKIND) == 3 {
        v = gv(K_TIVAL);
        next_token();
    } else {
        if accept("-") == 1 {
            if gv(K_TKIND) != 2 { return err_at2("expected a number after -", gv(K_LINE), gv(K_COL)); }
            v = -gv(K_TIVAL);
            next_token();
        } else {
            v = gv(K_TIVAL);
            next_token();
        }
    }
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
                if accept("f64") == 1 {
                    pt = ty_f64();
                } else {
                    if accept("ptr") == 1 {
                        pt = ty_ptr(ty_byte());
                    } else {
                        return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                    }
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
    if accept("f64") == 1 {
        # 返回 f64：位模式经 rax 返回，语义同 i64
    } else {
        expect("i64");
    }
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
    if k >= 16 { return die("too many imported files\n"); }
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
            if tok_is("f64") == 1 {
                ft = ty_f64();
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
                    if tok_is("const") == 1 {
                        # const 复用全局声明路径（编译期常量约定；当前实现为
                        # 只读语义的全局存储——写它编译不报错但约定不改写）
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
