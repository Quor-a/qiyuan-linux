# 基准：2 亿次循环累加。考察循环体与局部变量访问
fn main() -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    while i < 200000000 {
        s = s + i;
        i = i + 1;
    }
    return s & 255;
}
