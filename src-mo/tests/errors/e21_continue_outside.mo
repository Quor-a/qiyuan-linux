# expect-error: continue outside
fn main() -> i64 {
    let i: i64 = 0;
    while i < 3 {
        i = i + 1;
    }
    continue;
    return 0;
}
