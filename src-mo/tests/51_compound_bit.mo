# expect: 12
# 位运算复合赋值：12 &= 10 -> 8; 8 |= 4 -> 12
fn main() -> i64 {
    let x: i64 = 12;
    x &= 10;
    x |= 4;
    return x;
}
