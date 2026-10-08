# expect: 3
fn main() -> i64 {
    let r: i64 = 0;
    if 1 == 1 && 2 == 2 { r = r + 1; }
    if 1 == 2 || 3 == 3 { r = r + 1; }
    if !(1 == 2) { r = r + 1; }
    return r;
}
