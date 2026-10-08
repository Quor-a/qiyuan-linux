# expect: 1
# 负下标同样被拦住（无符号比较让负数变成超大值）
fn main() -> i64 {
    let a: [4] i64 = 0;
    let i: i64 = 0 - 1;
    return a[i];
}
