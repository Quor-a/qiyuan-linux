# expect: 5
# 减法不可交换，验证是 x - e 而不是 e - x
fn main() -> i64 {
    let x: i64 = 10;
    x -= 5;
    return x;
}
