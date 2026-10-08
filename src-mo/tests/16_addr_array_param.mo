# expect: 15
# 取地址 & + 指针遍历：把数组传给函数
fn sum(p: i64, n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < n {
        s = s + load64(p + i * 8);
        i = i + 1;
    }
    return s;
}

fn main() -> i64 {
    let a: [5] i64;
    a[0] = 1;
    a[1] = 2;
    a[2] = 3;
    a[3] = 4;
    a[4] = 5;
    return sum(&a, 5);
}
