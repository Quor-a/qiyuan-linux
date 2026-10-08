# expect: 44
# byte 变量：存储截断到低 8 位，读取零扩展（300 & 255 = 44）
fn main() -> i64 {
    let c: byte = 300;
    return c;
}
