# expect: 10
# 数组基本读写：局部数组与全局数组
var g: [4] i64 = 0;

fn main() -> i64 {
    let a: [4] i64;
    a[0] = 1;
    a[1] = 2;
    a[3] = 4;
    g[2] = 3;
    return a[0] + a[1] + g[2] + a[3];
}
