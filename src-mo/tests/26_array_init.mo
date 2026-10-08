# expect: 20
# 局部数组常量初始化
fn main() -> i64 {
    let a: [4] i64 = 5;
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 4 {
        s = s + a[i];
        i = i + 1;
    }
    return s;
}
