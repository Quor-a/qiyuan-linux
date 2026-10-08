# expect: 5
# byte 数组：下标步长为 1，可逐字节读写
fn main() -> i64 {
    let b: [8] byte = 0;
    let i: i64 = 0;
    while i < 5 {
        b[i] = 97 + i;
        i = i + 1;
    }
    return b[4] - 97 + 1;
}
