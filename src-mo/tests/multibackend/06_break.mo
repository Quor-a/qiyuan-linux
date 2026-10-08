# expect: 42
fn main() -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 100 {
        i = i + 1;
        if i == 5 { continue; }
        if i > 9 { break; }
        s = s + i;
    }
    # 1+2+3+4+6+7+8+9 = 40
    return s + 2;
}
