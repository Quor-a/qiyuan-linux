# expect: 7
# 字符串字面量求值即数据段地址，可作缓冲区使用
fn main() -> i64 {
    let p: i64 = "AAAAAAAA";
    store64(p, 7);
    return load64(p);
}
