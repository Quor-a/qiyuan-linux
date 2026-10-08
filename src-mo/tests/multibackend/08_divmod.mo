# expect: 19
fn main() -> i64 {
    let a: i64 = 100;
    let r: i64 = 0;
    r = r + a / 7;        # 14
    r = r + a % 7;        # 2
    r = r + (a / 10);     # 10
    return r - 7;
}
