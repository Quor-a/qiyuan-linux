# expect: 30
fn main() -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 10 {
        s = s + i;
        i = i + 1;
    }
    # 0+1+...+9 = 45
    return (s * 2 - 60) & 255;
}
