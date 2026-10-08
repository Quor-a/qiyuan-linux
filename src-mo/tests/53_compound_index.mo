# expect: 15
# 数组下标的复合赋值：a[2] += 5
fn main() -> i64 {
    let a: [4] i64 = 0;
    a[2] = 10;
    a[2] += 5;
    return a[2];
}
