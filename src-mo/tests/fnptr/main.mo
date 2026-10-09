# expect: 0
# 函数指针：&fn 取址 / p(x) 间接调用 / 函数指针当参数（回调）/ 函数指针数组
import "io.mo";
fn sq(x: i64) -> i64 { return x * x; }
fn cube(x: i64) -> i64 { return x * x * x; }
fn dbl(x: i64) -> i64 { return x * 2; }
fn apply(f: i64, v: i64) -> i64 { return f(v); }
fn f0() -> i64 { return 100; }
fn f1() -> i64 { return 200; }
fn f2() -> i64 { return 300; }
var ops: [3] i64 = 0;
fn fact(n: i64) -> i64 {
    if n <= 1 { return 1; }
    let f: i64 = &fact;
    return n * f(n - 1);
}
fn main() -> i64 {
    let p: i64 = &sq;
    print_i64(p(9)); print(" expect 81\n");
    p = &cube;
    print_i64(p(3)); print(" expect 27\n");
    print_i64(apply(&dbl, 10)); print(" expect 20\n");
    ops[0] = &f0; ops[1] = &f1; ops[2] = &f2;
    print_i64(ops[0]()); print(" ");
    print_i64(ops[1]()); print(" ");
    print_i64(ops[2]()); print(" expect 100 200 300\n");
    print_i64(fact(5)); print(" expect 120\n");
    return 0;
}
