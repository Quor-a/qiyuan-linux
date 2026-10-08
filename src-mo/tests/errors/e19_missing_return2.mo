# expect-error: missing return statement
fn g(a: i64, b: i64) -> i64 {
    let s: i64 = a + b;
    if s > 10 {
        let t: i64 = s * 2;
    }
}

fn main() -> i64 {
    return g(1, 2);
}
