# expect: 10
# 复合赋值：i += 1
fn main() -> i64 {
    let i: i64 = 0;
    while i < 10 {
        i += 1;
    }
    return i;
}
