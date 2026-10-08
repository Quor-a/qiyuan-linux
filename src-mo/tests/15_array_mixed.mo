# expect: 2
# 数组元素参与复杂表达式、变量下标、嵌套下标
var g: [8] i64 = 1;

fn main() -> i64 {
    let a: [3] i64;
    a[0] = 1;
    a[1] = 2;
    let i: i64 = 1;
    a[i + 1] = a[i] + a[i - 1];
    g[0] = a[2] - g[1];
    return g[0];
}
