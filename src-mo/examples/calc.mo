# calc —— 表达式计算器（用墨语言自己写的）
#
#   ./calc "1+2*3"        -> 7
#   ./calc "(1+2)*3"      -> 9
#   ./calc "17/5"         -> 3   （整数除）
#   ./calc "17%5"         -> 2
#   ./calc "-2^2"         -> -4
#
# 实现：调度场算法（shunting-yard）转后缀，再求值。
# 两个栈：运算符栈 + 值栈。整个过程只处理整数。
import "io.mo";
import "str.mo";

var src: [256] byte = 0;
var sp: i64 = 0;

# 值栈（后缀表达式的中间结果）
var vst: [128] i64 = 0;
var vsp: i64 = 0;
# 运算符栈（存字符）
var ost: [128] byte = 0;
var osp: i64 = 0;

var ERRFLAG: i64 = 0;

fn die(msg: i64) -> i64 {
    print("error: ");
    print(msg);
    print_nl();
    ERRFLAG = 1;
    return 0;
}

fn prec(c: i64) -> i64 {
    if c == 43 { return 1; }     # +
    if c == 45 { return 1; }     # -
    if c == 42 { return 2; }     # *
    if c == 47 { return 2; }     # /
    if c == 37 { return 2; }     # %
    if c == 94 { return 3; }     # ^
    return 0;
}

fn is_right(c: i64) -> i64 {
    if c == 94 { return 1; }     # ^ 右结合
    return 0;
}

fn vpush(v: i64) -> i64 {
    if vsp >= 128 { return die("stack overflow"); }
    vst[vsp] = v;
    vsp = vsp + 1;
    return 0;
}

fn vpop() -> i64 {
    if vsp <= 0 { die("bad expression"); return 0; }
    vsp = vsp - 1;
    return vst[vsp];
}

fn opush(c: i64) -> i64 {
    ost[osp] = c;
    osp = osp + 1;
    return 0;
}

fn opop() -> i64 {
    osp = osp - 1;
    return ost[osp];
}

# 弹一个运算符并计算
fn apply(c: i64) -> i64 {
    let b: i64 = vpop();
    let a: i64 = vpop();
    if ERRFLAG == 1 { return 0; }
    let r: i64 = 0;
    if c == 43 { r = a + b; }
    else {
        if c == 45 { r = a - b; }
        else {
            if c == 42 { r = a * b; }
            else {
                if c == 47 {
                    if b == 0 { return die("division by zero"); }
                    r = a / b;
                } else {
                    if c == 37 {
                        if b == 0 { return die("division by zero"); }
                        r = a % b;
                    } else {
                        if c == 94 {
                            r = 1;
                            let i: i64 = 0;
                            while i < b { r = r * a; i = i + 1; }
                        } else { return die("unknown operator"); }
                    }
                }
            }
        }
    }
    return vpush(r);
}

# 一元负号：把接下来的数字取负。用 0 - x 实现
var NEG: i64 = 0;

fn run() -> i64 {
    let i: i64 = 0;
    let expect_operand: i64 = 1;
    while load8(&src + i) != 0 {
        let c: i64 = load8(&src + i);
        if c == 32 { i = i + 1; }
        else {
            if c >= 48 {
                if c <= 57 {
                    let v: i64 = 0;
                    while load8(&src + i) >= 48 {
                        if load8(&src + i) > 57 { break; }
                        v = v * 10 + load8(&src + i) - 48;
                        i = i + 1;
                    }
                    if NEG == 1 { v = 0 - v; NEG = 0; }
                    vpush(v);
                    expect_operand = 0;
                } else {
                    if prec(c) > 0 {
                        while osp > 0 {
                            let t: i64 = ost[osp - 1];
                            if t == 40 { break; }
                            if prec(t) < prec(c) { break; }
                            if prec(t) == prec(c) {
                                if is_right(c) == 1 { break; }
                            }
                            apply(opop());
                            if ERRFLAG == 1 { return 0; }
                        }
                        opush(c);
                        i = i + 1;
                        expect_operand = 1;
                    } else { return die("bad char"); }
                }
            } else {
                if c == 40 {
                    opush(c);
                    i = i + 1;
                    expect_operand = 1;
                } else {
                    if c == 41 {
                        while osp > 0 {
                            if ost[osp - 1] == 40 { break; }
                            apply(opop());
                            if ERRFLAG == 1 { return 0; }
                        }
                        if osp > 0 {
                            if ost[osp - 1] == 40 { osp = osp - 1; }
                        }
                        i = i + 1;
                        expect_operand = 0;
                    } else {
                        if c == 45 {
                            if expect_operand == 1 {
                                NEG = 1;
                                i = i + 1;
                            } else {
                                while osp > 0 {
                                    let t: i64 = ost[osp - 1];
                                    if t == 40 { break; }
                                    if prec(t) < prec(c) { break; }
                                    if prec(t) == prec(c) {
                                        if is_right(c) == 1 { break; }
                                    }
                                    apply(opop());
                                    if ERRFLAG == 1 { return 0; }
                                }
                                opush(c);
                                i = i + 1;
                                expect_operand = 1;
                            }
                        } else {
                            if prec(c) > 0 {
                                while osp > 0 {
                                    let t: i64 = ost[osp - 1];
                                    if t == 40 { break; }
                                    if prec(t) < prec(c) { break; }
                                    if prec(t) == prec(c) {
                                        if is_right(c) == 1 { break; }
                                    }
                                    apply(opop());
                                    if ERRFLAG == 1 { return 0; }
                                }
                                opush(c);
                                i = i + 1;
                                expect_operand = 1;
                            } else {
                                return die("bad char");
                            }
                        }
                    }
                }
            }
        }
    }
    while osp > 0 {
        let t: i64 = opop();
        if t == 40 { return die("mismatched paren"); }
        apply(t);
        if ERRFLAG == 1 { return 0; }
    }
    if vsp != 1 { return die("bad expression"); }
    return vpop();
}

fn main() -> i64 {
    if argc() < 2 {
        print("usage: calc \"<expr>\"\n");
        print("  支持 + - * / % ^ 和括号，整数运算\n");
        return 2;
    }
    strcpy(&src, argv(1));
    let r: i64 = run();
    if ERRFLAG == 1 { return 1; }
    print_i64(r);
    print_nl();
    return 0;
}
