# expect: 1
# 用字符字面量判断字符类别（写 parser 时的典型用法）
fn is_upper(c: i64) -> i64 {
    if c >= 'A' {
        if c <= 'Z' {
            return 1;
        }
    }
    return 0;
}

fn main() -> i64 {
    let n: i64 = 0;
    if is_upper('M') == 1 { n = n + 1; }
    if is_upper('m') == 1 { n = n + 1; }
    if is_upper('0') == 1 { n = n + 1; }
    return n;
}
