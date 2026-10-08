# expect: 72
# byte 数组下标的复合赋值（按 1 字节读写）
fn main() -> i64 {
    let b: [4] byte = 0;
    b[0] = 65;
    b[0] += 7;
    return b[0];
}
