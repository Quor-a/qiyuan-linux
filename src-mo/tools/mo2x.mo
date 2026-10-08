# mo2x —— 墨语言多后端翻译器（用墨语言自己写的）
#
#   ./mo2x prog.mo c   > prog.c      gcc -O2 prog.c -o prog
#   ./mo2x prog.mo js  > prog.js     node prog.js
#   ./mo2x prog.mo py  > prog.py     python3 prog.py
#
# 为什么是这个形态：
#   一个前端（分词 + 解析）产出同一套结构，交给不同的「发射器」。
#   三个后端共用解析器，所以它们的行为天然一致 ——
#   这正是「多后端对齐」的关键：差异只应该出现在发射层。
#
# 后端 1 = C      ：交给 gcc/clang，白嫖所有架构
# 后端 2 = JS     ：交给 node / 浏览器
# 后端 3 = Python ：交给 python3
#
# 已知差异（写清楚，不藏着）：
#   * C 后端数组不做越界检查
#   * JS 后端整数是浮点，超过 2^53 会失精（与普通 JS 一致）
#   * Python 后端整数任意精度，与 i64 的溢出行为不同

import "io.mo";
import "str.mo";
import "fs.mo";
import "dir.mo";

# ---------- 目标 ----------
var T_C: i64 = 1;
var T_JS: i64 = 2;
var T_PY: i64 = 3;
var T_FS: i64 = 4;          # freestanding C：无 libc，内联汇编 syscall
var FS_ARCH: i64 = 0;      # 1=x86_64  2=aarch64  3=riscv64
var TGT: i64 = 1;
var T_JAVA: i64 = 10;
var T_GO:   i64 = 11;
var T_RUST: i64 = 12;
var T_CS:   i64 = 13;
var T_SWIFT:i64 = 14;
var T_RUBY: i64 = 15;
var T_LUA:  i64 = 16;
var T_PHP:  i64 = 17;
var T_PERL: i64 = 18;

# profile —— 全部在 set_profile 里按目标填好
var G_FN: i64 = 0;          # 函数关键字（含尾空格）
var G_ENDFN: i64 = 0;       # 函数体结束符（"}" / "end"）
var G_VAR: i64 = 0;         # 变量前缀（"let " / "var " / "my $" / "local " / "$" / ""）
var G_TYI64: i64 = 0;       # i64 的类型名（动态语言为空串）
var G_TYPED: i64 = 0;       # 1 = 声明时写类型（java/go/rust/cs/swift）
var G_SEMI: i64 = 1;        # 语句结尾分号
var G_ARRPRE: i64 = 0;      # 数组初始化前缀（含数量占位用 # ）
var G_ARRPOST: i64 = 0;
var G_CLASS: i64 = 0;       # 结构体关键字（"class " / "type " / "struct "）
var G_NEW: i64 = 0;         # 结构体实例化（"new T()" / "T{}"）
var G_DIV: i64 = 0;         # 整数除写法：0=直接用 /  1=//  2=intdiv(a,b)  3=int(a/b)
var G_AND: i64 = 0;         # && 的写法
var G_OR: i64 = 0;
var G_NOT: i64 = 0;         # 一元 ! 的写法
var G_ELIF: i64 = 0;        # else-if 关键字
var G_CMT: i64 = 0;         # 注释前缀
var G_REF: i64 = 0;
var G_BOPEN: i64 = 0;
var G_FNBOPEN: i64 = 0;
var G_BREAK: i64 = 0;      # break 关键字（perl=last）
var G_CONT: i64 = 0;      # continue 关键字（perl/ruby=next）    # 函数体开始符（perl/lua/ruby 为空：函数头已自带）      # 块开始符（默认 "{"，lua 为空）         # 变量引用前缀（perl/php 用 $）
var G_ISMAIN: i64 = 0;      # 目标是否属于通用后端
var G_DIV_STR: i64 = 0;     # 整数除的写法
var TGNAME: i64 = 0;
var FSNAME: i64 = 0;        # 目标名（注释里用）
var G_ENDCLASS: i64 = 0;    # 结构体定义结束符



# ---------- 输出 ----------
var CHB: [2] byte = 0;
var IND: i64 = 0;          # 当前缩进层级（Python 用）
var LASTDIM: i64 = 0;      # 最近一次数组维度
var LASTTY: i64 = 0;       # 最近一次基类型名
var BOL: i64 = 1;          # 行首标记（全局变量必须先声明）

fn raw(s: i64) -> i64 {
    let n: i64 = strlen(s);
    if n > 0 { syscall(1, 1, s, n, 0, 0, 0); }
    return 0;
}
fn rawc(c: i64) -> i64 {
    store8(&CHB, c);
    syscall(1, 1, &CHB, 1, 0, 0, 0);
    return 0;
}
fn ind() -> i64 {
    if TGT == T_PY {
        let i: i64 = 0;
        while i < IND { raw("    "); i = i + 1; }
    }
    return 0;
}
fn outs(s: i64) -> i64 {
    if BOL == 1 { ind(); BOL = 0; }
    return raw(s);
}
fn nl() -> i64 {
    rawc(10);
    BOL = 1;
    return 0;
}
fn line(s: i64) -> i64 {
    outs(s);
    nl();
    return 0;
}

# ---------- 源码 / 分词 ----------

var SRC: [65536] byte = 0;
var SLEN: i64 = 0;

var POOL: [180000] byte = 0;
var PP: i64 = 0;

var TK: [6000] i64 = 0;
var TS: [6000] i64 = 0;
var NT: i64 = 0;
var TI: i64 = 0;
var LN: i64 = 1;

var OPS: [32] i64 = 0;
var NOPS: i64 = 0;

var LEXB: [4096] byte = 0;

fn pool_add(s: i64) -> i64 {
    let o: i64 = PP;
    let i: i64 = 0;
    while load8(s + i) != 0 {
        store8(&POOL + PP, load8(s + i));
        PP = PP + 1;
        i = i + 1;
    }
    store8(&POOL + PP, 0);
    PP = PP + 1;
    return o;
}

fn cur_k() -> i64 { return TK[TI]; }
fn cur_s() -> i64 { return &POOL + TS[TI]; }

fn is_op(s: i64) -> i64 {
    if cur_k() != 5 { return 0; }
    if streq(cur_s(), s) == 1 { return 1; }
    return 0;
}
fn accept_op(s: i64) -> i64 {
    if is_op(s) == 1 { TI = TI + 1; return 1; }
    return 0;
}
fn is_kw(s: i64) -> i64 {
    if cur_k() != 1 { return 0; }
    if streq(cur_s(), s) == 1 { return 1; }
    return 0;
}
fn accept_kw(s: i64) -> i64 {
    if is_kw(s) == 1 { TI = TI + 1; return 1; }
    return 0;
}
fn ident() -> i64 {
    if cur_k() != 1 { return err("expected identifier"); }
    let s: i64 = cur_s();
    TI = TI + 1;
    return s;
}

var FP: [24576] byte = 0;
var FPP: i64 = 0;
var FILES: [64] i64 = 0;
var NEED_SYS: i64 = 0;       # 用到 syscall / 裸内存 → 需要 <sys/syscall.h>
var NF: i64 = 0;
var CURF: i64 = 0;

fn err(msg: i64) -> i64 {
    syscall(1, 2, "mo2x: ", 6, 0, 0, 0);
    syscall(1, 2, &FP + FILES[CURF], strlen(&FP + FILES[CURF]), 0, 0, 0);
    syscall(1, 2, ":", 1, 0, 0, 0);
    let lb: [24] byte = 0;
    utoa(LN, &lb, 10);
    syscall(1, 2, &lb, strlen(&lb), 0, 0, 0);
    syscall(1, 2, ": ", 2, 0, 0, 0);
    syscall(1, 2, msg, strlen(msg), 0, 0, 0);
    syscall(1, 2, " at '", 5, 0, 0, 0);
    if TI >= NT { syscall(1, 2, "<eof>", 5, 0, 0, 0); }
    else {
        if cur_k() == 0 { syscall(1, 2, "<eof>", 5, 0, 0, 0); }
        else { syscall(1, 2, cur_s(), strlen(cur_s()), 0, 0, 0); }
    }
    syscall(1, 2, "'\n", 2, 0, 0, 0);
    syscall(1, 2, "\n", 1, 0, 0, 0);
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn expect_op(s: i64) -> i64 {
    if accept_op(s) == 0 { return err("expected operator"); }
    return 0;
}

fn is_alpha(c: i64) -> i64 {
    if c >= 97 { if c <= 122 { return 1; } }
    if c >= 65 { if c <= 90 { return 1; } }
    if c == 95 { return 1; }
    return 0;
}
fn is_digit_ch(c: i64) -> i64 {
    if c >= 48 { if c <= 57 { return 1; } }
    return 0;
}
fn is_ws(c: i64) -> i64 {
    if c == 32 { return 1; }
    if c == 9 { return 1; }
    if c == 10 { return 1; }
    if c == 13 { return 1; }
    return 0;
}

fn ops_init() -> i64 {
    if NOPS > 0 { return 0; }
    # 长的必须在前，否则 "==" 会被拆成两个 "="
    OPS[0] = "=="; OPS[1] = "!="; OPS[2] = "<="; OPS[3] = ">=";
    OPS[4] = "&&"; OPS[5] = "||"; OPS[6] = "<<"; OPS[7] = ">>";
    OPS[8] = "+="; OPS[9] = "-="; OPS[10] = "*="; OPS[11] = "/=";
    OPS[12] = "%="; OPS[13] = "&="; OPS[14] = "|="; OPS[15] = "^=";
    OPS[16] = "+"; OPS[17] = "-"; OPS[18] = "*"; OPS[19] = "/";
    OPS[20] = "%"; OPS[21] = "&"; OPS[22] = "|"; OPS[23] = "^";
    OPS[24] = "="; OPS[25] = "<"; OPS[26] = ">"; OPS[27] = "!";
    NOPS = 28;
    return 0;
}

fn lex_str(dst: i64) -> i64 {
    let n: i64 = 0;
    while load8(&SRC + SLEN) != 34 {
        let c: i64 = load8(&SRC + SLEN);
        if c == 0 { return n; }
        if c == 92 {
            SLEN = SLEN + 1;
            let e: i64 = load8(&SRC + SLEN);
            if e == 110 { store8(dst + n, 10); }
            else {
                if e == 116 { store8(dst + n, 9); }
                else {
                    if e == 114 { store8(dst + n, 13); }
                    else {
                        if e == 48 { store8(dst + n, 0); }
                        else {
                            if e == 92 { store8(dst + n, 92); }
                            else {
                                if e == 34 { store8(dst + n, 34); }
                                else {
                                    if e == 39 { store8(dst + n, 39); }
                                    else { store8(dst + n, e); }
                                }
                            }
                        }
                    }
                }
            }
            SLEN = SLEN + 1;
            n = n + 1;
        } else {
            store8(dst + n, c);
            SLEN = SLEN + 1;
            n = n + 1;
        }
    }
    SLEN = SLEN + 1;
    store8(dst + n, 0);
    return n;
}

fn add_tok(k: i64, s: i64) -> i64 {
    if NT >= 6000 { return 0; }
    TK[NT] = k;
    TS[NT] = pool_add(s);
    NT = NT + 1;
    return 0;
}

fn tokenize() -> i64 {
    NT = 0;
    TI = 0;
    SLEN = 0;
    LN = 1;
    ops_init();
    while 1 {
        while 1 {
            let c: i64 = load8(&SRC + SLEN);
            if c == 0 { return 0; }
            if is_ws(c) == 1 {
                if c == 10 { LN = LN + 1; }
                SLEN = SLEN + 1;
            } else {
                if c == 35 {
                    while load8(&SRC + SLEN) != 10 {
                        if load8(&SRC + SLEN) == 0 { return 0; }
                        SLEN = SLEN + 1;
                    }
                } else {
                    break;
                }
            }
        }
        let c: i64 = load8(&SRC + SLEN);
        if is_alpha(c) == 1 {
            let n: i64 = 0;
            while is_alpha(load8(&SRC + SLEN)) == 1 || is_digit_ch(load8(&SRC + SLEN)) == 1 {
                store8(&LEXB + n, load8(&SRC + SLEN));
                SLEN = SLEN + 1;
                n = n + 1;
            }
            store8(&LEXB + n, 0);
            add_tok(1, &LEXB);
        } else {
            if is_digit_ch(c) == 1 {
                let n: i64 = 0;
                while is_digit_ch(load8(&SRC + SLEN)) == 1 {
                    store8(&LEXB + n, load8(&SRC + SLEN));
                    SLEN = SLEN + 1;
                    n = n + 1;
                }
                store8(&LEXB + n, 0);
                add_tok(2, &LEXB);
            } else {
                if c == 34 {
                    SLEN = SLEN + 1;
                    lex_str(&LEXB);
                    add_tok(3, &LEXB);
                } else {
                    if c == 39 {
                        SLEN = SLEN + 1;
                        let v: i64 = 0;
                        if load8(&SRC + SLEN) == 92 {
                            SLEN = SLEN + 1;
                            let e: i64 = load8(&SRC + SLEN);
                            if e == 110 { v = 10; }
                            else {
                                if e == 116 { v = 9; }
                                else {
                                    if e == 48 { v = 0; }
                                    else { v = e; }
                                }
                            }
                            SLEN = SLEN + 1;
                        } else {
                            v = load8(&SRC + SLEN);
                            SLEN = SLEN + 1;
                        }
                        if load8(&SRC + SLEN) == 39 { SLEN = SLEN + 1; }
                        store8(&LEXB, v);
                        store8(&LEXB + 1, 0);
                        add_tok(4, &LEXB);
                    } else {
                        # 单字符分隔符。注意：不能包含 < > = ! ，
                        # 否则 "==" / "!=" / "<=" / ">=" 会被拆开
                        if c == 40 || c == 41 || c == 123 || c == 125 || c == 91 || c == 93
                           || c == 59 || c == 44 || c == 58 || c == 46 {
                            store8(&LEXB, c);
                            store8(&LEXB + 1, 0);
                            SLEN = SLEN + 1;
                            add_tok(5, &LEXB);
                        } else {
                            let k: i64 = 0;
                            let found: i64 = -1;
                            while k < NOPS {
                                let op: i64 = OPS[k];
                                let j: i64 = 0;
                                let ok: i64 = 1;
                                while load8(op + j) != 0 {
                                    if load8(&SRC + SLEN + j) != load8(op + j) { ok = 0; }
                                    j = j + 1;
                                }
                                if ok == 1 { found = k; break; }
                                k = k + 1;
                            }
                            if found < 0 {
                                SLEN = SLEN + 1;
                            } else {
                                let op: i64 = OPS[found];
                                SLEN = SLEN + strlen(op);
                                add_tok(5, op);
                            }
                        }
                    }
                }
            }
        }
    }
    return 0;
}

# ---------- 表达式 ----------
#
# 用「优先级递归」而不是手写 8 个层级函数：
#   emit_prec(minp)：先输出一元项，再看当前运算符优先级是否 >= minp，
#   是就输出运算符并递归 emit_prec(p+1)。
# 这样既保证结合性，又不产生多余括号 —— 手写层级时括号数对不上，
# 会生成错的表达式，而这类错误极难发现。

fn binprec() -> i64 {
    if cur_k() != 5 { return 0; }
    let s: i64 = cur_s();
    if streq(s, "||") == 1 { return 1; }
    if streq(s, "&&") == 1 { return 2; }
    if streq(s, "|") == 1 { return 3; }
    if streq(s, "^") == 1 { return 4; }
    if streq(s, "&") == 1 { return 5; }
    if streq(s, "==") == 1 { return 6; }
    if streq(s, "!=") == 1 { return 6; }
    if streq(s, "<") == 1 { return 7; }
    if streq(s, ">") == 1 { return 7; }
    if streq(s, "<=") == 1 { return 7; }
    if streq(s, ">=") == 1 { return 7; }
    if streq(s, "<<") == 1 { return 8; }
    if streq(s, ">>") == 1 { return 8; }
    if streq(s, "+") == 1 { return 9; }
    if streq(s, "-") == 1 { return 9; }
    if streq(s, "*") == 1 { return 10; }
    if streq(s, "/") == 1 { return 10; }
    if streq(s, "%") == 1 { return 10; }
    return 0;
}

fn emit_binop(s: i64) -> i64 {
    if TGT == T_PY {
        if streq(s, "&&") == 1 { outs(" and "); return 0; }
        if streq(s, "||") == 1 { outs(" or "); return 0; }
        # 墨语言 / 是整数除，Python 的 / 会得到浮点
        if streq(s, "/") == 1 { outs(" // "); return 0; }
    }
    if TGT == T_JS {
        if streq(s, "/") == 1 {
            return err("JS 后端不支持整数除法 / （JS 的 / 是浮点除）。请改写或改用 c / py");
        }
    }
    if is_gen() == 1 {
        if streq(s, "&&") == 1 { outs(G_AND); return 0; }
        if streq(s, "||") == 1 { outs(G_OR); return 0; }
        if streq(s, "/") == 1 {
            # Lua 用 //，PHP 用 intdiv，Perl 要 int(a/b)
            outs(G_DIV_STR);
            return 0;
        }
    }
    outs(" ");
    outs(s);
    outs(" ");
    return 0;
}

fn emit_expr() -> i64 { return emit_prec(1); }

fn emit_primary() -> i64 {
    if cur_k() == 2 {
        outs(cur_s());
        TI = TI + 1;
        return 0;
    }
    if cur_k() == 3 {
        if is_c_like() == 1 { outs("(unsigned char*)"); }
        out_cstr(cur_s());
        TI = TI + 1;
        return 0;
    }
    if cur_k() == 4 {
        let v: i64 = load8(cur_s());
        let b: [24] byte = 0;
        utoa(v, &b, 10);
        outs(&b);
        TI = TI + 1;
        return 0;
    }
    if accept_op("(") == 1 {
        outs("(");
        emit_expr();
        expect_op(")");
        outs(")");
        return 0;
    }
    if cur_k() == 1 {
        let nm: i64 = cur_s();
        TI = TI + 1;
        if is_op("(") == 1 {
            if streq(nm, "load8") == 1 { return err("load8 仅在 C 后端支持"); }
            if streq(nm, "load64") == 1 { return err("load64 仅在 C 后端支持"); }
            if streq(nm, "store8") == 1 { return err("store8 仅在 C 后端支持"); }
            if streq(nm, "store64") == 1 { return err("store64 仅在 C 后端支持"); }
            if streq(nm, "syscall") == 1 {
                if is_c_like() == 0 { return err("syscall 仅在 C / freestanding 后端支持"); }
                TI = TI + 1;                 # 吃掉 '('，否则实参解析会把它当分组
                outs("mo_syscall");          # header 里定义的就是这个名字
                outs("(");
                if is_op(")") == 0 {
                    # 实参显式转 long：指针传给 long 形参在 clang/zig 下是硬错误，
                    # 而 syscall 的语义本来就是把地址当整数传
                    outs("(long)");
                    emit_expr();
                    while accept_op(",") == 1 {
                        outs(",");
                        outs("(long)");
                        emit_expr();
                    }
                }
                expect_op(")");
                outs(")");
                return 0;
            }
            if streq(nm, "argc") == 1 { return err("argc 仅在 C 后端支持"); }
            if streq(nm, "argv") == 1 { return err("argv 仅在 C 后端支持"); }
            TI = TI + 1;          # 吃掉 '(' —— 必须先消耗再输出
            outs(nm);
            outs("(");
            if is_op(")") == 0 {
                emit_expr();
                while accept_op(",") == 1 {
                    outs(",");
                    emit_expr();
                }
            }
            expect_op(")");
            outs(")");
            return 0;
        }
        if is_gen() == 1 { outs(G_REF); }
        outs(nm);
        return 0;
    }
    return err("bad primary");
}

fn emit_postfix() -> i64 {
    emit_primary();
    while 1 {
        if accept_op("[") == 1 {
            outs("[");
            emit_expr();
            expect_op("]");
            outs("]");
        } else {
            if accept_op(".") == 1 {
                outs(".");
                outs(ident());
            } else {
                return 0;
            }
        }
    }
    return 0;
}

fn emit_unary() -> i64 {
    if accept_op("-") == 1 {
        outs("-");
        return emit_unary();
    }
    if accept_op("!") == 1 {
        if TGT == T_PY { outs("not "); }
        else {
            if is_gen() == 1 { outs(G_NOT); } else { outs("!"); }
        }
        return emit_unary();
    }
    if accept_op("&") == 1 {
        return err("取地址 & 仅在 C 后端支持");
    }
    if accept_op("*") == 1 {
        return err("解引用 * 仅在 C 后端支持");
    }
    return emit_postfix();
}

fn emit_prec(minp: i64) -> i64 {
    emit_unary();
    while 1 {
        let p: i64 = binprec();
        if p == 0 { return 0; }
        if p < minp { return 0; }
        let op: i64 = cur_s();
        TI = TI + 1;
        emit_binop(op);
        emit_prec(p + 1);
    }
    return 0;
}

fn out_cstr(s: i64) -> i64 {
    outs("\"");
    let i: i64 = 0;
    while load8(s + i) != 0 {
        let c: i64 = load8(s + i);
        if c == 34 { outs("\\\""); }
        else {
            if c == 92 { outs("\\\\"); }
            else {
                if c == 10 { outs("\\n"); }
                else {
                    if c == 9 { outs("\\t"); }
                    else {
                        if c == 13 { outs("\\r"); }
                        else {
                            if c < 32 { outs(" "); }
                            else { rawc(c); }
                        }
                    }
                }
            }
        }
        i = i + 1;
    }
    outs("\"");
    return 0;
}

# ---------- 类型名映射 ----------

fn emit_scalar(t: i64) -> i64 {
    if streq(t, "i64") == 1 {
        if is_c_like() == 1 { outs("long long"); } else { outs("0"); }
        return 0;
    }
    if streq(t, "byte") == 1 {
        if is_c_like() == 1 { outs("unsigned char"); } else { outs("0"); }
        return 0;
    }
    if streq(t, "ptr") == 1 {
        if is_c_like() == 1 { outs("unsigned char*"); return 0; }
        return err("ptr 只在 C / freestanding 后端支持（JS/Python 等无指针语义）");
    }
    if is_c_like() == 1 { outs("struct "); outs(t); outs("_t"); } else { outs(t); }
    return 0;
}

# C 用：输出完整声明（含数组维度与变量名）
fn emit_scalar_or_arr(nm: i64, isarr: i64) -> i64 {
    if isarr == 1 {
        if is_op("[") == 1 {
            TI = TI + 1;
            let n: i64 = cur_s();
            TI = TI + 1;
            expect_op("]");
            emit_scalar_or_arr(nm, 1);
            outs("[");
            outs(n);
            outs("]");
            return 0;
        }
    }
    let t: i64 = ident();
    emit_scalar(t);
    outs(" ");
    outs(nm);
    return 0;
}

# 消耗一个类型，返回数组维度（0 表示标量）。
# JS / Python 不需要类型名，但**必须把它消耗掉** ——
# 早先只在数组分支消耗，标量时类型名残留在流里，
# 后面的 '=' 就匹配不上（现象：只生成 "let s;" 就崩了）。
fn consume_type() -> i64 {
    if is_op("[") == 1 {
        TI = TI + 1;
        let d: i64 = atoi(cur_s());
        TI = TI + 1;
        expect_op("]");
        let inner: i64 = consume_type();
        return d;
    }
    if cur_k() == 1 { LASTTY = cur_s(); TI = TI + 1; }
    return 0;
}

# 是否结构体类型（JS 要 new，Python 要实例化）
fn is_struct_ty(t: i64) -> i64 {
    if streq(t, "i64") == 1 { return 0; }
    if streq(t, "byte") == 1 { return 0; }
    if streq(t, "ptr") == 1 { return 0; }
    return 1;
}

fn outi(v: i64) -> i64 {
    let b: [24] byte = 0;
    utoa(v, &b, 10);
    return outs(&b);
}

# ---------- 块与语句 ----------

fn blk_open() -> i64 {
    if TGT == T_PY {
        outs(":");
        nl();
        IND = IND + 1;
        return 0;
    }
    outs(" {");
    nl();
    return 0;
}

fn blk_close() -> i64 {
    if TGT == T_PY {
        IND = IND - 1;
        return 0;
    }
    outs("}");
    nl();
    return 0;
}

# 关闭一个块并紧接着开另一个（else / else if）
fn blk_join(kw: i64) -> i64 {
    if TGT == T_PY {
        IND = IND - 1;
        outs(kw);
        outs(":");
        nl();
        IND = IND + 1;
        return 0;
    }
    outs("} ");
    outs(kw);
    outs(" {");
    nl();
    return 0;
}

fn semi() -> i64 {
    if TGT == T_PY { nl(); return 0; }
    outs(";");
    nl();
    return 0;
}

# 判断当前语句是不是赋值（只扫 token，不产生输出）
fn is_assign_start() -> i64 {
    let save: i64 = TI;
    let r: i64 = 0;
    if cur_k() == 1 {
        TI = TI + 1;
        let ok: i64 = 1;
        while ok == 1 {
            if is_op("[") == 1 {
                let d: i64 = 0;
                let done: i64 = 0;
                while TI < NT {
                    if is_op("[") == 1 { d = d + 1; }
                    else {
                        if is_op("]") == 1 {
                            d = d - 1;
                            if d == 0 { TI = TI + 1; done = 1; break; }
                        }
                    }
                    TI = TI + 1;
                }
                if done == 0 { ok = 0; }
            } else {
                if is_op(".") == 1 {
                    TI = TI + 1;
                    if cur_k() == 1 { TI = TI + 1; } else { ok = 0; }
                } else {
                    break;
                }
            }
        }
        if ok == 1 {
            if is_op("=") == 1 { r = 1; }
            else { if is_op("+=") == 1 { r = 1; }
            else { if is_op("-=") == 1 { r = 1; }
            else { if is_op("*=") == 1 { r = 1; }
            else { if is_op("/=") == 1 { r = 1; }
            else { if is_op("%=") == 1 { r = 1; }
            else { if is_op("&=") == 1 { r = 1; }
            else { if is_op("|=") == 1 { r = 1; }
            else { if is_op("^=") == 1 { r = 1; } } } } } } } } }
        }
    }
    TI = save;
    return r;
}

fn emit_lvalue() -> i64 {
    if is_gen() == 1 { outs(G_REF); }
    outs(ident());
    while 1 {
        if accept_op("[") == 1 {
            outs("[");
            emit_expr();
            expect_op("]");
            outs("]");
        } else {
            if accept_op(".") == 1 {
                outs(".");
                outs(ident());
            } else {
                return 0;
            }
        }
    }
    return 0;
}

fn emit_stmt() -> i64 {
    if is_assign_start() == 1 {
        emit_lvalue();
        let t: i64 = cur_s();
        TI = TI + 1;
        if TGT == T_PY {
            if streq(t, "/=") == 1 { outs(" //= "); } else { outs(" "); outs(t); outs(" "); }
        } else {
            outs(" ");
            outs(t);
            outs(" ");
        }
        emit_expr();
        expect_op(";");
        semi();
        return 0;
    }
    if accept_kw("return") == 1 {
        if is_op(";") == 1 {
            TI = TI + 1;
            outs("return");
            semi();
            return 0;
        }
        outs("return ");
        if is_c_like() == 1 { outs("("); }
        emit_expr();
        if is_c_like() == 1 { outs(")"); }
        expect_op(";");
        semi();
        return 0;
    }
    if accept_kw("break") == 1 {
        expect_op(";");
        if TGT == T_PY { line("break"); } else { line("break;"); }
        return 0;
    }
    if accept_kw("continue") == 1 {
        expect_op(";");
        if TGT == T_PY { line("continue"); } else { line("continue;"); }
        return 0;
    }
    if accept_kw("while") == 1 {
        if TGT == T_PY { outs("while "); } else { outs("while ("); }
        emit_expr();
        if TGT != T_PY { outs(")"); }
        expect_op("{");
        blk_open();
        emit_stmts();
        blk_close();
        return 0;
    }
    if accept_kw("if") == 1 {
        if TGT == T_PY { outs("if "); } else { outs("if ("); }
        emit_expr();
        if TGT != T_PY { outs(")"); }
        expect_op("{");
        blk_open();
        emit_stmts();
        while is_kw("else") == 1 {
            TI = TI + 1;
            if is_kw("if") == 1 {
                TI = TI + 1;
                if TGT == T_PY {
                    IND = IND - 1;
                    outs("elif ");
                    emit_expr();
                    outs(":");
                    nl();
                    IND = IND + 1;
                } else {
                    outs("} else if (");
                    emit_expr();
                    outs(") {");
                    nl();
                }
                expect_op("{");
                emit_stmts();
            } else {
                blk_join("else");
                expect_op("{");
                emit_stmts();
            }
        }
        blk_close();
        return 0;
    }
    if accept_kw("let") == 1 {
        emit_local();
        return 0;
    }
    if accept_op("{") == 1 {
        blk_open();
        emit_stmts();
        blk_close();
        return 0;
    }
    emit_expr();
    expect_op(";");
    semi();
    return 0;
}

fn emit_stmts() -> i64 {
    while is_op("}") == 0 {
        if cur_k() == 0 { return err("unexpected eof in block"); }
        emit_stmt();
    }
    TI = TI + 1;
    return 0;
}

fn emit_block_body() -> i64 {
    expect_op("{");
    if TGT == T_PY {
        IND = 0;
        outs(":");
        nl();
        IND = 1;
    } else {
        outs(" {");
        nl();
    }
    emit_stmts();
    if TGT == T_PY { IND = 0; } else { line("}"); }
    return 0;
}

# ---------- 声明 ----------

# 局部：let name: T [= expr];
fn emit_local() -> i64 {
    let nm: i64 = ident();
    expect_op(":");
    if is_c_like() == 1 {
        let isarr: i64 = 0;
        if is_op("[") == 1 { isarr = 1; }
        emit_scalar_or_arr(nm, isarr);
        if accept_op("=") == 1 {
            if isarr == 1 { outs(" = {"); emit_expr(); outs("}"); }
            else { outs(" = ("); emit_expr(); outs(")"); }
        }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    let dim: i64 = consume_type();
    if TGT == T_JS {
        outs("let ");
        outs(nm);
        if dim > 0 { outs(" = new Array("); outi(dim); outs(").fill(0)"); }
        else { if is_struct_ty(LASTTY) == 1 { outs(" = new "); outs(LASTTY); outs("()"); } }
        if accept_op("=") == 1 {
            if dim > 0 { emit_expr(); } else { outs(" = "); emit_expr(); }
        }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    outs(nm);
    if dim > 0 {
        outs(" = [0] * ");
        outi(dim);
        if accept_op("=") == 1 { emit_expr(); }
    } else {
        if is_struct_ty(LASTTY) == 1 { outs(" = "); outs(LASTTY); outs("()"); } else { if accept_op("=") == 1 { outs(" = "); emit_expr(); } else { outs(" = 0"); } }
    }
    nl();
    expect_op(";");
    return 0;
}

# 全局：var name: T = expr;
fn emit_global() -> i64 {
    let nm: i64 = ident();
    expect_op(":");
    if is_c_like() == 1 {
        let isarr: i64 = 0;
        if is_op("[") == 1 { isarr = 1; }
        emit_scalar_or_arr(nm, isarr);
        if accept_op("=") == 1 {
            if isarr == 1 { outs(" = {"); emit_expr(); outs("}"); }
            else { outs(" = ("); emit_expr(); outs(")"); }
        }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    let dim: i64 = consume_type();
    if TGT == T_JS {
        outs("let ");
        outs(nm);
        if dim > 0 { outs(" = new Array("); outi(dim); outs(").fill(0)"); }
        else { if is_struct_ty(LASTTY) == 1 { outs(" = new "); outs(LASTTY); outs("()"); } }
        if accept_op("=") == 1 {
            if dim > 0 { emit_expr(); } else { outs(" = "); emit_expr(); }
        }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    outs(nm);
    if dim > 0 {
        outs(" = [0] * ");
        outi(dim);
        if accept_op("=") == 1 { emit_expr(); }
    } else {
        if is_struct_ty(LASTTY) == 1 { outs(" = "); outs(LASTTY); outs("()"); } else { if accept_op("=") == 1 { outs(" = "); emit_expr(); } else { outs(" = 0"); } }
    }
    nl();
    expect_op(";");
    return 0;
}

# 结构体
fn emit_struct() -> i64 {
    let nm: i64 = ident();
    if is_c_like() == 1 {
        outs("typedef struct ");
        outs(nm);
        outs("_t {\n");
        expect_op("{");
        while is_op("}") == 0 {
            if cur_k() == 0 { return err("unexpected eof in struct"); }
            let fn2: i64 = ident();
            expect_op(":");
            emit_scalar_or_arr(fn2, 0);
            outs(";");
            nl();
            expect_op(";");
        }
        TI = TI + 1;
        outs("} ");
        outs(nm);
        outs("_t;\n");
        return 0;
    }
    if TGT == T_JS {
        outs("function ");
        outs(nm);
        outs("() {\n");
        expect_op("{");
        while is_op("}") == 0 {
            if cur_k() == 0 { return err("unexpected eof in struct"); }
            let fn2: i64 = ident();
            expect_op(":");
            let dim: i64 = consume_type();
            outs("  this.");
            outs(fn2);
            if dim > 0 { outs(" = new Array("); outi(dim); outs(").fill(0)"); } else { outs(" = 0"); }
            outs(";");
            nl();
            expect_op(";");
        }
        TI = TI + 1;
        outs("}\n");
        return 0;
    }
    outs("class ");
    outs(nm);
    outs(":\n");
    outs("    def __init__(self):\n");
    expect_op("{");
    while is_op("}") == 0 {
        if cur_k() == 0 { return err("unexpected eof in struct"); }
        let fn2: i64 = ident();
        expect_op(":");
        let dim: i64 = consume_type();
        outs("        self.");
        outs(fn2);
        if dim > 0 { outs(" = [0] * "); outi(dim); } else { outs(" = 0"); }
        nl();
        expect_op(";");
    }
    TI = TI + 1;
    return 0;
}

# 函数签名
fn emit_sig() -> i64 {
    let nm: i64 = ident();
    expect_op("(");
    let first: i64 = 1;
    let ps: [512] byte = 0;
    while is_op(")") == 0 {
        if first == 0 { strcat(&ps, ", "); }
        first = 0;
        let pn: i64 = ident();
        expect_op(":");
        let isarr: i64 = 0;
        if is_op("[") == 1 { isarr = 1; }
        if is_c_like() == 1 {
            if isarr == 1 { skip_brackets(); }
            let t: i64 = ident();
            if streq(t, "i64") == 1 { strcat(&ps, "long long"); }
            else {
                if streq(t, "byte") == 1 { strcat(&ps, "unsigned char"); }
                else {
                    if streq(t, "ptr") == 1 { strcat(&ps, "unsigned char*"); }
                    else { strcat(&ps, "struct "); strcat(&ps, t); strcat(&ps, "_t"); }
                }
            }
            strcat(&ps, " ");
            strcat(&ps, pn);
        } else {
            strcat(&ps, pn);
            let d: i64 = consume_type();
        }
        if is_op(",") == 1 { TI = TI + 1; } else { break; }
    }
    expect_op(")");
    accept_op("-");
    accept_op(">");
    let rt: i64 = 0;
    if cur_k() == 1 { rt = cur_s(); TI = TI + 1; }
    let ismain: i64 = 0;
    if streq(nm, "main") == 1 { ismain = 1; }

    if is_c_like() == 1 {
        if rt != 0 {
            if streq(rt, "i64") == 1 { outs("long long "); }
            else {
                if streq(rt, "byte") == 1 { outs("unsigned char "); }
                else { outs("struct "); outs(rt); outs("_t "); }
            }
        } else { outs("long long "); }
        if ismain == 1 { outs("mo_main"); } else { outs(nm); }
        outs("(");
        outs(&ps);
        outs(")");
        return 0;
    }
    if TGT == T_JS {
        outs("function ");
        outs(nm);
        outs("(");
        outs(&ps);
        outs(")");
        return 0;
    }
    outs("def ");
    outs(nm);
    outs("(");
    outs(&ps);
    outs(")");
    return 0;
}

fn skip_brackets() -> i64 {
    while is_op("[") == 1 {
        TI = TI + 1;
        TI = TI + 1;
        expect_op("]");
    }
    return 0;
}

# ---------- 跳过 ----------

fn skip_balanced() -> i64 {
    while is_op("{") == 0 {
        if cur_k() == 0 { return 0; }
        TI = TI + 1;
    }
    let d: i64 = 0;
    while 1 {
        if cur_k() == 0 { return 0; }
        if is_op("{") == 1 { d = d + 1; }
        else {
            if is_op("}") == 1 {
                d = d - 1;
                TI = TI + 1;
                if d == 0 { return 0; }
                continue;
            }
        }
        TI = TI + 1;
    }
    return 0;
}

fn skip_to_semi() -> i64 {
    while is_op(";") == 0 {
        if cur_k() == 0 { return 0; }
        TI = TI + 1;
    }
    TI = TI + 1;
    return 0;
}

# ---------- 文件表 ----------

var PBUF: [4096] byte = 0;

fn add_file(path: i64) -> i64 {
    let i: i64 = 0;
    while i < NF {
        if streq(&FP + FILES[i], path) == 1 { return 0; }
        i = i + 1;
    }
    if NF >= 64 { return -1; }
    let o: i64 = FPP;
    let k: i64 = 0;
    while load8(path + k) != 0 {
        store8(&FP + FPP, load8(path + k));
        FPP = FPP + 1;
        k = k + 1;
    }
    store8(&FP + FPP, 0);
    FPP = FPP + 1;
    FILES[NF] = o;
    NF = NF + 1;
    return 0;
}

fn resolve(path: i64, dst: i64) -> i64 {
    if exists(path) == 1 {
        strcpy(dst, path);
        return 0;
    }
    let bi: i64 = 0;
    let i: i64 = 0;
    while load8(path + i) != 0 {
        if load8(path + i) == 47 { bi = i + 1; }
        i = i + 1;
    }
    strcpy(dst, "lib/");
    strcat(dst, path + bi);
    if exists(dst) == 1 { return 0; }
    strcpy(dst, "../lib/");
    strcat(dst, path + bi);
    if exists(dst) == 1 { return 0; }
    return -1;
}

# 扫描 token，记录是否需要 Linux 特定能力。
# C 后端原先无条件输出 <sys/syscall.h>，于是 Windows / macOS 直接编译失败
# （那两个平台根本没有这个头）。应该按需输出。
fn scan_needs() -> i64 {
    let k: i64 = 0;
    while k < NT {
        if TK[k] == 1 {
            let nm: i64 = &POOL + TS[k];
            if streq(nm, "syscall") == 1 { NEED_SYS = 1; }
            if streq(nm, "load8") == 1 { NEED_SYS = 1; }
            if streq(nm, "load64") == 1 { NEED_SYS = 1; }
            if streq(nm, "store8") == 1 { NEED_SYS = 1; }
            if streq(nm, "store64") == 1 { NEED_SYS = 1; }
            if streq(nm, "argc") == 1 { NEED_SYS = 1; }
            if streq(nm, "argv") == 1 { NEED_SYS = 1; }
        }
        k = k + 1;
    }
    return 0;
}

fn load_file(i: i64) -> i64 {
    let n: i64 = read_file(&FP + FILES[i], &SRC, 131071);
    if n < 0 {
        syscall(1, 2, "mo2x: cannot open ", 19, 0, 0, 0);
        syscall(1, 2, &FP + FILES[i], strlen(&FP + FILES[i]), 0, 0, 0);
        syscall(1, 2, "\n", 1, 0, 0, 0);
        syscall(60, 1, 0, 0, 0, 0, 0);
    }
    store8(&SRC + n, 0);
    PP = 0;
    tokenize();
    scan_needs();
    return 0;
}

# kind: 0=收集 import + struct  1=var  2=函数签名  3=函数体
fn pass_file(i: i64, kind: i64) -> i64 {
    CURF = i;
    load_file(i);
    if kind == 3 {
        nl();
        if is_gen() == 1 { raw(G_CMT); raw(" ---- "); raw(&FP + FILES[i]); raw(" ----\n"); }
        else {
            if TGT == T_PY { raw("# ---- "); raw(&FP + FILES[i]); raw(" ----\n"); }
            else { raw("/* ---- "); raw(&FP + FILES[i]); raw(" ---- */\n"); }
        }
    }
    while cur_k() != 0 {
        if accept_kw("import") == 1 {
            if cur_k() == 3 {
                let p: i64 = cur_s();
                TI = TI + 1;
                if kind == 0 {
                    if resolve(p, &PBUF) == 0 { add_file(&PBUF); }
                }
            }
            accept_op(";");
        } else {
            if accept_kw("struct") == 1 {
                if kind == 0 {
                    if is_gen() == 1 { g_struct(); } else { emit_struct(); }
                } else { skip_balanced(); }
            } else {
                if accept_kw("var") == 1 {
                    if kind == 1 {
                        if is_gen() == 1 { g_global(); } else { emit_global(); }
                    } else { skip_to_semi(); }
                } else {
                    if accept_kw("fn") == 1 {
                        if kind == 2 {
                            if is_gen() == 1 { skip_balanced(); } else { if is_c_like() == 1 {
                                emit_sig();
                                outs(";");
                                nl();
                            } }
                            if is_gen() == 0 { skip_balanced(); }
                        } else {
                            if kind == 3 {
                                if is_gen() == 1 { g_sig(); g_block(); } else { emit_sig(); emit_block_body(); }
                            } else {
                                skip_balanced();
                            }
                        }
                    } else {
                        TI = TI + 1;
                    }
                }
            }
        }
    }
    return 0;
}

# ---------- 前后缀 ----------

fn fs_header() -> i64 {
    line("/* generated by mo2x -- 墨语言 freestanding 后端 */");
    line("/* 完全不依赖 libc：系统调用用内联汇编直接陷入内核 */");
    raw("/* 目标架构: ");
    raw(FSNAME);
    raw(" */\n");
    line("static long strlen_(unsigned char* s){ long n=0; while(s[n]) n++; return n; }");
    line("#define strlen strlen_");
    if FS_ARCH == 1 {
        line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
        line("  register long r0 asm(\"rax\") = n;");
        line("  register long r1 asm(\"rdi\") = a; register long r2 asm(\"rsi\") = b;");
        line("  register long r3 asm(\"rdx\") = c; register long r4 asm(\"r10\") = d;");
        line("  register long r5 asm(\"r8\")  = e; register long r6 asm(\"r9\")  = f;");
        line("  asm volatile(\"syscall\" : \"+r\"(r0)");
        line("    : \"r\"(r1),\"r\"(r2),\"r\"(r3),\"r\"(r4),\"r\"(r5),\"r\"(r6)");
        line("    : \"rcx\",\"r11\",\"memory\");");
        line("  return r0;");
        line("}");
        line("#define MO_WRITE 1");
        line("#define MO_EXIT  60");
        return 0;
    }
    if FS_ARCH == 2 {
        line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
        line("  register long r8 asm(\"x8\") = n; register long r0 asm(\"x0\") = a;");
        line("  register long r1 asm(\"x1\") = b; register long r2 asm(\"x2\") = c;");
        line("  register long r3 asm(\"x3\") = d; register long r4 asm(\"x4\") = e;");
        line("  register long r5 asm(\"x5\") = f;");
        line("  asm volatile(\"svc #0\" : \"+r\"(r0)");
        line("    : \"r\"(r8),\"r\"(r1),\"r\"(r2),\"r\"(r3),\"r\"(r4),\"r\"(r5)");
        line("    : \"memory\");");
        line("  return r0;");
        line("}");
        line("#define MO_WRITE 64");
        line("#define MO_EXIT  93");
        return 0;
    }
    line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
    line("  register long r7 asm(\"a7\") = n; register long r0 asm(\"a0\") = a;");
    line("  register long r1 asm(\"a1\") = b; register long r2 asm(\"a2\") = c;");
    line("  register long r3 asm(\"a3\") = d; register long r4 asm(\"a4\") = e;");
    line("  register long r5 asm(\"a5\") = f;");
    line("  asm volatile(\"ecall\" : \"+r\"(r0)");
    line("    : \"r\"(r7),\"r\"(r1),\"r\"(r2),\"r\"(r3),\"r\"(r4),\"r\"(r5)");
    line("    : \"memory\");");
    line("  return r0;");
    line("}");
    line("#define MO_WRITE 64");
    line("#define MO_EXIT  93");
    return 0;
}

fn is_c_like() -> i64 {
    if TGT == T_C { return 1; }
    if TGT == T_FS { return 1; }
    return 0;
}

fn emit_header() -> i64 {
    if TGT == T_FS { return fs_header(); }
    if is_c_like() == 1 {
        line("/* generated by mo2x -- 墨语言 C 后端 */");
        line("#include <unistd.h>");
        if NEED_SYS == 1 {
            line("#include <sys/syscall.h>");
            line("static long mo_syscall(long n,long a,long b,long c,long d,long e,long f){");
            line("  return syscall(n,a,b,c,d,e,f);");
            line("}");
        }
        line("static long strlen_(unsigned char* s){ long n=0; while(s[n]) n++; return n; }");
        line("#define strlen strlen_");
        return 0;
    }
    if TGT == T_JS {
        line("// generated by mo2x -- 墨语言 JS 后端");
        line("function strlen(s){ return s.length; }");
        return 0;
    }
    line("# generated by mo2x -- 墨语言 Python 后端");
    line("import sys");
    line("sys.setrecursionlimit(100000)");
    line("def strlen(s): return len(s)");
    return 0;
}

fn tg_name() -> i64 {
    if TGT == T_JAVA { return "Java"; }
    if TGT == T_GO { return "Go"; }
    if TGT == T_RUST { return "Rust"; }
    if TGT == T_CS { return "C#"; }
    if TGT == T_SWIFT { return "Swift"; }
    if TGT == T_RUBY { return "Ruby"; }
    if TGT == T_LUA { return "Lua"; }
    if TGT == T_PHP { return "PHP"; }
    return "Perl";
}

fn g_header() -> i64 {
    outs(G_CMT);
    outs(" generated by mo2x -- 墨语言 ");
    outs(tg_name());
    outs(" 后端\n");
    if TGT == T_GO { line("package main"); line("import \"os\""); return 0; }
    if TGT == T_PERL { line("use strict;"); line("use warnings;"); return 0; }
    if TGT == T_PHP { line("<?php"); return 0; }
    if TGT == T_RUST { return 0; }
    if TGT == T_JAVA { return 0; }
    if TGT == T_CS { return 0; }
    if TGT == T_SWIFT { line("import Foundation"); return 0; }
    if TGT == T_RUBY { return 0; }
    if TGT == T_LUA { return 0; }
    return 0;
}

fn g_footer() -> i64 {
    if TGT == T_GO { line("func main() { os.Exit(int(mo_main_entry())) }"); return 0; }
    if TGT == T_RUST { line("fn main() { std::process::exit(mo_main_entry() as i32) }"); return 0; }
    if TGT == T_JAVA { return 0; }
    if TGT == T_CS { return 0; }
    if TGT == T_SWIFT { line("exit(Int32(mo_main_entry()))"); return 0; }
    if TGT == T_RUBY { line("exit(main())"); return 0; }
    if TGT == T_LUA { line("os.exit(main())"); return 0; }
    if TGT == T_PHP { line("exit(main());"); return 0; }
    line("exit main();");
    return 0;
}

fn emit_footer() -> i64 {
    if TGT == T_FS {
        nl();
        line("long long mo_main(void);");
        line("void _start(void){");
        line("  long r = mo_main();");
        line("  mo_syscall(MO_EXIT, r, 0, 0, 0, 0, 0);");
        line("  while(1){}");
        line("}");
        return 0;
    }
    if is_c_like() == 1 {
        line("int main(int argc, char** argv){");
        line("  return (int)mo_main();");
        line("}");
        return 0;
    }
    if TGT == T_JS {
        line("process.exit(main());");
        return 0;
    }
    line("sys.exit(main())");
    return 0;
}

# ==========================================================================
#  通用多语言后端：一套 profile 驱动，覆盖 java / go / rust / cs / swift /
#  ruby / lua / php / perl
#
#  做法：把每门语言的「关键字与模板」抽成一组变量（profile），
#  发射器只写一份。新增一门语言 = 填一张表，而不是复制一套发射器。
# ==========================================================================

fn set_profile(t: i64) -> i64 {
    TGT = t;
    G_ISMAIN = 1;
    G_SEMI = 1;
    G_ENDFN = "}";
    G_ENDCLASS = "}";
    G_DIV = 0;
    G_AND = " && ";
    G_OR = " || ";
    G_NOT = "!";
    G_DIV_STR = " / ";
    G_ELIF = "else if";
    G_VAR = "";
    G_TYPED = 0;
    G_TYI64 = "";
    G_ARRPRE = "";
    G_ARRPOST = "";
    G_NEW = "";
    G_CMT = "//";
    G_REF = "";
    G_BOPEN = "{";
    G_FNBOPEN = "{";
    G_BREAK = "break";
    G_CONT = "continue";

    if t == T_JAVA {
        G_FN = "static long "; G_VAR = ""; G_TYPED = 1; G_TYI64 = "long";
        G_ARRPRE = "new long["; G_ARRPOST = "]"; G_CLASS = "class ";
        G_NEW = "new "; G_CMT = "//"; return 0;
    }
    if t == T_GO {
        G_FN = "func "; G_VAR = "var "; G_TYPED = 1; G_TYI64 = "int64";
        G_ARRPRE = "make([]int64, "; G_ARRPOST = ")"; G_CLASS = "type ";
        G_NEW = ""; G_CMT = "//"; return 0;
    }
    if t == T_RUST {
        G_FN = "fn "; G_VAR = "let mut "; G_TYPED = 1; G_TYI64 = "i64";
        G_ARRPRE = "vec![0i64; "; G_ARRPOST = "]"; G_CLASS = "struct ";
        G_NEW = ""; G_CMT = "//"; return 0;
    }
    if t == T_CS {
        G_FN = "static long "; G_VAR = ""; G_TYPED = 1; G_TYI64 = "long";
        G_ARRPRE = "new long["; G_ARRPOST = "]"; G_CLASS = "class ";
        G_NEW = "new "; G_CMT = "//"; return 0;
    }
    if t == T_SWIFT {
        G_FN = "func "; G_VAR = "var "; G_TYPED = 1; G_TYI64 = "Int64";
        G_ARRPRE = "[Int64](repeating: 0, count: "; G_ARRPOST = ")";
        G_CLASS = "class "; G_NEW = ""; G_CMT = "//"; return 0;
    }
    if t == T_RUBY {
        G_FN = "def "; G_ENDFN = "end"; G_ENDCLASS = "end"; G_SEMI = 0;
        G_ARRPRE = "Array.new("; G_ARRPOST = ", 0)"; G_CLASS = "class ";
        G_NEW = ".new"; G_AND = " and "; G_OR = " or "; G_ELIF = "elsif";
        G_CMT = "#"; return 0;
    }
    if t == T_LUA {
        G_FN = "function "; G_ENDFN = "end"; G_ENDCLASS = "end"; G_SEMI = 0;
        G_VAR = "local "; G_ARRPRE = "{}"; G_CLASS = "";
        G_AND = " and "; G_OR = " or "; G_NOT = "not "; G_ELIF = "elseif"; G_CONT = "goto __cont";
        G_DIV = 1; G_CMT = "--"; G_DIV_STR = " // "; G_REF = ""; G_BOPEN = ""; G_FNBOPEN = ""; return 0;
    }
    if t == T_PHP {
        G_FN = "function "; G_VAR = "$"; G_ARRPRE = "array_fill(0, "; G_ARRPOST = ", 0)";
        G_CLASS = "class "; G_NEW = "new "; G_ELIF = "elseif"; G_DIV = 2;
        G_CMT = "//"; return 0;
    }
    if t == T_PERL {
        G_FN = "sub "; G_ENDFN = "}"; G_ENDCLASS = "}"; G_VAR = "my $";
        G_ARRPRE = "(0) x "; G_ELIF = "elsif"; G_DIV = 3; G_DIV_STR = " / "; G_REF = "$"; G_BREAK = "last"; G_CONT = "next";
        G_AND = " and "; G_OR = " or "; G_CMT = "#"; G_DIV_STR = " / "; G_FNBOPEN = ""; return 0;
    }
    return 0;
}


fn is_gen() -> i64 {
    if TGT >= 10 { return 1; }
    return 0;
}

# ---------- 通用后端的类型与声明 ----------

fn g_decl(nm: i64, dim: i64) -> i64 {
    if dim > 0 {
        if TGT == T_RUST { outs("let mut "); outs(nm); outs(" = "); outs(G_ARRPRE); outi(dim); outs(G_ARRPOST); return 0; }
        if TGT == T_GO { outs("var "); outs(nm); outs(" []int64 = "); outs(G_ARRPRE); outi(dim); outs(G_ARRPOST); return 0; }
        if TGT == T_SWIFT { outs("var "); outs(nm); outs(" = "); outs(G_ARRPRE); outi(dim); outs(G_ARRPOST); return 0; }
        if TGT == T_JAVA { outs("long[] "); outs(nm); outs(" = new long["); outi(dim); outs("]"); return 0; }
        if TGT == T_CS { outs("long[] "); outs(nm); outs(" = new long["); outi(dim); outs("]"); return 0; }
        if TGT == T_LUA { outs("local "); outs(nm); outs(" = {}"); return 0; }
        if TGT == T_PHP { outs(G_REF); outs(nm); outs(" = array_fill(0, "); outi(dim); outs(", 0)"); return 0; }
        if TGT == T_PERL { outs("my @"); outs(nm); outs(" = (0) x "); outi(dim); return 0; }
        outs(nm); outs(" = "); outs(G_ARRPRE); outi(dim); outs(G_ARRPOST);
        return 0;
    }
    if G_TYPED == 1 {
        if TGT == T_GO { outs("var "); outs(nm); outs(" "); outs(G_TYI64); return 0; }
        if TGT == T_RUST { outs("let mut "); outs(nm); outs(": "); outs(G_TYI64); return 0; }
        if TGT == T_SWIFT { outs("var "); outs(nm); outs(": "); outs(G_TYI64); return 0; }
        outs(G_TYI64); outs(" "); outs(nm);
        return 0;
    }
    outs(G_VAR);
    outs(nm);
    return 0;
}

# ---------- 通用后端的语句 ----------

fn g_stmt() -> i64 {
    if is_assign_start() == 1 {
        ind();
        emit_lvalue();
        let t: i64 = cur_s();
        TI = TI + 1;
        outs(" ");
        outs(t);
        outs(" ");
        emit_expr();
        expect_op(";");
        if G_SEMI == 1 { outs(";"); }
        nl();
        return 0;
    }
    if accept_kw("return") == 1 {
        ind();
        outs("return ");
        emit_expr();
        expect_op(";");
        if G_SEMI == 1 { outs(";"); }
        nl();
        return 0;
    }
    if accept_kw("break") == 1 {
        expect_op(";");
        line(G_BREAK);
        return 0;
    }
    if accept_kw("continue") == 1 {
        expect_op(";");
        line(G_CONT);
        return 0;
    }
    if accept_kw("while") == 1 {
        ind();
        if TGT == T_GO { outs("for "); } else { outs("while "); }
        if TGT == T_RUBY { emit_expr(); }
        else {
            if TGT == T_LUA { emit_expr(); outs(" do"); }
            else { outs(" ("); emit_expr(); outs(")"); }
        }
        if TGT == T_GO { nl(); }
        else {
            if TGT == T_RUST { nl(); }
            else { outs(" "); }
        }
        expect_op("{");
        outs(G_BOPEN);
        nl();
        g_stmts();
        ind();
        outs(G_ENDFN);
        nl();
        return 0;
    }
    if accept_kw("if") == 1 {
        ind();
        outs("if ");
        if TGT == T_RUBY { emit_expr(); }
        else {
            if TGT == T_LUA { emit_expr(); outs(" then"); }
            else { outs(" ("); emit_expr(); outs(")"); }
        }
        outs(" ");
        expect_op("{");
        outs(G_BOPEN);
        nl();
        g_stmts();
        while is_kw("else") == 1 {
            TI = TI + 1;
            if is_kw("if") == 1 {
                TI = TI + 1;
                ind();
                outs("} ");
                outs(G_ELIF);
                outs(" ");
                if TGT == T_RUBY { emit_expr(); } else { outs(" ("); emit_expr(); outs(")"); }
                outs(" {");
                nl();
                expect_op("{");
                g_stmts();
            } else {
                ind();
                outs("} else {");
                nl();
                expect_op("{");
                g_stmts();
            }
        }
        ind();
        outs("}");
        nl();
        return 0;
    }
    if accept_kw("let") == 1 {
        let nm: i64 = ident();
        expect_op(":");
        let dim: i64 = consume_type();
        ind();
        if dim > 0 {
            g_decl(nm, dim);
            if accept_op("=") == 1 { emit_expr(); }
        } else {
            if is_struct_ty(LASTTY) == 1 {
                # 结构体实例
                if TGT == T_JAVA { outs(""); outs(LASTTY); outs(" "); outs(nm); outs(" = new "); outs(LASTTY); outs("()"); }
                else {
                    if TGT == T_CS { outs(LASTTY); outs(" "); outs(nm); outs(" = new "); outs(LASTTY); outs("()"); }
                    else {
                        if TGT == T_GO { outs("var "); outs(nm); outs(" "); outs(LASTTY); }
                        else {
                            if TGT == T_RUST { outs("let mut "); outs(nm); outs(" = "); outs(LASTTY); outs(" {}"); }
                            else {
                                if TGT == T_SWIFT { outs("var "); outs(nm); outs(" = "); outs(LASTTY); outs("()"); }
                                else { outs(nm); outs(" = "); outs(LASTTY); outs(".new"); }
                            }
                        }
                    }
                }
                if accept_op("=") == 1 { emit_expr(); }
            } else {
                g_decl(nm, 0);
                if accept_op("=") == 1 { outs(" = "); emit_expr(); }
                else {
                    if TGT == T_RUST { outs(" = 0"); }
                    else {
                        if TGT == T_GO { outs(" = 0"); }
                        else {
                            if TGT == T_JAVA { outs(" = 0"); }
                            else {
                                if TGT == T_CS { outs(" = 0"); }
                                else {
                                    if TGT == T_SWIFT { outs(" = 0"); }
                                    else { outs(" = 0"); }
                                }
                            }
                        }
                    }
                }
            }
        }
        if G_SEMI == 1 { outs(";"); }
        nl();
        expect_op(";");
        return 0;
    }
    ind();
    emit_expr();
    expect_op(";");
    if G_SEMI == 1 { outs(";"); }
    nl();
    return 0;
}

fn g_stmts() -> i64 {
    while is_op("}") == 0 {
        if cur_k() == 0 { return err("unexpected eof in block"); }
        g_stmt();
    }
    TI = TI + 1;
    return 0;
}

# ---------- 通用后端的签名与结构体 ----------

fn g_sig() -> i64 {
    let nm: i64 = ident();
    expect_op("(");
    let ps: [512] byte = 0;
    let first: i64 = 1;
    while is_op(")") == 0 {
        if first == 0 { strcat(&ps, ", "); }
        first = 0;
        let pn: i64 = ident();
        expect_op(":");
        let d: i64 = consume_type();
        if G_TYPED == 1 {
            if TGT == T_GO { strcat(&ps, pn); strcat(&ps, " "); strcat(&ps, G_TYI64); }
            else {
                if TGT == T_RUST { strcat(&ps, pn); strcat(&ps, ": "); strcat(&ps, G_TYI64); }
                else {
                    if TGT == T_SWIFT { strcat(&ps, pn); strcat(&ps, ": "); strcat(&ps, G_TYI64); }
                    else { strcat(&ps, G_TYI64); strcat(&ps, " "); strcat(&ps, pn); }
                }
            }
        } else {
            strcat(&ps, G_REF);
            strcat(&ps, pn);
        }
        if is_op(",") == 1 { TI = TI + 1; } else { break; }
    }
    expect_op(")");
    accept_op("-");
    accept_op(">");
    if cur_k() == 1 { TI = TI + 1; }

    if TGT == T_GO { outs("func "); outs(nm); outs("("); outs(&ps); outs(") int64 "); return 0; }
    if TGT == T_RUST { outs("fn "); outs(nm); outs("("); outs(&ps); outs(") -> i64 "); return 0; }
    if TGT == T_SWIFT { outs("func "); outs(nm); outs("("); outs(&ps); outs(") -> Int64 "); return 0; }
    if TGT == T_JAVA { outs("static long "); outs(nm); outs("("); outs(&ps); outs(") "); return 0; }
    if TGT == T_CS { outs("static long "); outs(nm); outs("("); outs(&ps); outs(") "); return 0; }
    if TGT == T_RUBY { outs("def "); outs(nm); outs("("); outs(&ps); outs(")"); return 0; }
    if TGT == T_PHP { outs("function "); outs(nm); outs("("); outs(&ps); outs(") "); return 0; }
    if TGT == T_LUA { outs("function "); outs(nm); outs("("); outs(&ps); outs(")"); return 0; }
    outs("sub ");
    outs(nm);
    outs(" { my (");
    outs(&ps);
    outs(") = @_;");
    return 0;
}

fn g_struct() -> i64 {
    let nm: i64 = ident();
    if TGT == T_PERL { return err("Perl 后端不支持 struct（用 hash 需另设语义）"); }
    if TGT == T_LUA { return err("Lua 后端不支持 struct（用 table 需另设语义）"); }
    if TGT == T_GO {
        outs("type ");
        outs(nm);
        outs(" struct {\n");
        expect_op("{");
        while is_op("}") == 0 {
            if cur_k() == 0 { return err("unexpected eof in struct"); }
            let f: i64 = ident();
            expect_op(":");
            let d: i64 = consume_type();
            outs("    ");
            outs(f);
            outs(" int64\n");
            expect_op(";");
        }
        TI = TI + 1;
        outs("}\n");
        return 0;
    }
    if TGT == T_RUST {
        outs("struct ");
        outs(nm);
        outs(" { ");
        expect_op("{");
        let first: i64 = 1;
        while is_op("}") == 0 {
            if cur_k() == 0 { return err("unexpected eof in struct"); }
            let f: i64 = ident();
            expect_op(":");
            let d: i64 = consume_type();
            if first == 0 { outs(", "); }
            first = 0;
            outs(f);
            outs(": i64");
            expect_op(";");
        }
        TI = TI + 1;
        outs(" }\n");
        return 0;
    }
    # java / cs / swift / ruby / php：class
    outs(G_CLASS);
    outs(nm);
    outs(" {\n");
    expect_op("{");
    while is_op("}") == 0 {
        if cur_k() == 0 { return err("unexpected eof in struct"); }
        let f: i64 = ident();
        expect_op(":");
        let d: i64 = consume_type();
        if TGT == T_RUBY { outs("  attr_accessor :"); outs(f); nl(); }
        else {
            if TGT == T_PHP { outs("  public $"); outs(f); outs(" = 0;"); nl(); }
            else {
                if TGT == T_JAVA { outs("  public long "); outs(f); outs(" = 0;"); nl(); }
                else {
                    if TGT == T_CS { outs("  public long "); outs(f); outs(" = 0;"); nl(); }
                    else { outs("  var "); outs(f); outs(": Int64 = 0"); nl(); }
                }
            }
        }
        expect_op(";");
    }
    TI = TI + 1;
    outs(G_ENDCLASS);
    nl();
    return 0;
}

fn g_block() -> i64 {
    expect_op("{");
    outs(" ");
    outs(G_FNBOPEN);
    nl();
    g_stmts();
    ind();
    outs(G_ENDFN);
    nl();
    return 0;
}

# 目标识别：用 if-return 平铺，避免深层 else 链
# （墨语言的 else 必须紧跟 }，深层嵌套极易写错）
fn target_id(t: i64) -> i64 {
    if streq(t, "c") == 1 { TGT = T_C; return 1; }
    if streq(t, "js") == 1 { TGT = T_JS; return 1; }
    if streq(t, "py") == 1 { TGT = T_PY; return 1; }
    if streq(t, "perl") == 1 { set_profile(T_PERL); return 1; }
    if streq(t, "java") == 1 { set_profile(T_JAVA); return 1; }
    if streq(t, "go") == 1 { set_profile(T_GO); return 1; }
    if streq(t, "rust") == 1 { set_profile(T_RUST); return 1; }
    if streq(t, "cs") == 1 { set_profile(T_CS); return 1; }
    if streq(t, "swift") == 1 { set_profile(T_SWIFT); return 1; }
    if streq(t, "ruby") == 1 { set_profile(T_RUBY); return 1; }
    if streq(t, "lua") == 1 { set_profile(T_LUA); return 1; }
    if streq(t, "php") == 1 { set_profile(T_PHP); return 1; }
    if streq(t, "cfs") == 1 { TGT = T_FS; FS_ARCH = 1; FSNAME = "x86_64"; return 1; }
    if streq(t, "cfs-x86_64") == 1 { TGT = T_FS; FS_ARCH = 1; FSNAME = "x86_64"; return 1; }
    if streq(t, "cfs-aarch64") == 1 { TGT = T_FS; FS_ARCH = 2; FSNAME = "aarch64"; return 1; }
    if streq(t, "cfs-arm64") == 1 { TGT = T_FS; FS_ARCH = 2; FSNAME = "aarch64"; return 1; }
    if streq(t, "cfs-riscv64") == 1 { TGT = T_FS; FS_ARCH = 3; FSNAME = "riscv64"; return 1; }
    return 0;
}


fn main() -> i64 {
    if argc() < 3 {
        print("usage: mo2x <file.mo> <target>\n");
        print("target: c | cfs | cfs-aarch64 | cfs-riscv64 | js | py | perl\n");
        print("        java | go | rust | cs | swift | ruby | lua | php\n");
        return 2;
    }
    if target_id(argv(2)) == 0 {
        print("unknown target: ");
        print(argv(2));
        print("\n");
        return 2;
    }
    add_file(argv(1));
    if is_gen() == 1 { g_header(); } else { emit_header(); }
    let i: i64 = 0;
    while i < NF { pass_file(i, 0); i = i + 1; }
    let j: i64 = 0;
    while j < NF { pass_file(j, 1); j = j + 1; }
    let k: i64 = 0;
    while k < NF { pass_file(k, 2); k = k + 1; }
    let m: i64 = 0;
    while m < NF { pass_file(m, 3); m = m + 1; }
    if is_gen() == 1 { g_footer(); } else { emit_footer(); }
    return 0;
}

# 通用后端的全局变量声明
fn g_global() -> i64 {
    let nm: i64 = ident();
    expect_op(":");
    let dim: i64 = consume_type();
    if TGT == T_PERL {
        if dim > 0 { outs("my @"); outs(nm); outs(" = (0) x "); outi(dim); }
        else { outs("my $"); outs(nm); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_RUBY {
        outs(nm);
        if dim > 0 { outs(" = Array.new("); outi(dim); outs(", 0)"); } else { outs(" = 0"); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_GO {
        outs("var ");
        outs(nm);
        if dim > 0 { outs(" = make([]int64, "); outi(dim); outs(")"); } else { outs(" int64"); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_RUST {
        outs("static mut ");
        outs(nm);
        if dim > 0 { outs(": Vec<i64> = Vec::new()"); } else { outs(": i64"); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_JAVA {
        if dim > 0 { outs("static long[] "); outs(nm); outs(" = new long["); outi(dim); outs("]"); }
        else { outs("static long "); outs(nm); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_CS {
        if dim > 0 { outs("static long[] "); outs(nm); outs(" = new long["); outi(dim); outs("]"); }
        else { outs("static long "); outs(nm); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_SWIFT {
        outs("var ");
        outs(nm);
        if dim > 0 { outs(" = [Int64](repeating: 0, count: "); outi(dim); outs(")"); }
        else { outs(": Int64"); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        nl();
        expect_op(";");
        return 0;
    }
    if TGT == T_PHP {
        outs(G_REF);
        outs(nm);
        if dim > 0 { outs(" = array_fill(0, "); outi(dim); outs(", 0)"); } else { outs(" = 0"); }
        if accept_op("=") == 1 { outs(" = "); emit_expr(); }
        outs(";");
        nl();
        expect_op(";");
        return 0;
    }
    outs("local ");
    outs(nm);
    if dim > 0 { outs(" = {}"); } else { outs(" = 0"); }
    if accept_op("=") == 1 { outs(" = "); emit_expr(); }
    nl();
    expect_op(";");
    return 0;
}
