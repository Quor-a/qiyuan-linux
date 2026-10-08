# expect: 0
# 字符字面量：值就是字符的 ASCII 码
fn main() -> i64 {
    let a: i64 = 'a';
    let nl: i64 = '\n';
    let d: i64 = '7' - '0';
    let tab: i64 = '\t';
    let esc: i64 = '\\';
    # 97 + 10 + 7 + 9 + 92 = 215
    return a + nl + d + tab + esc - 215;
}
