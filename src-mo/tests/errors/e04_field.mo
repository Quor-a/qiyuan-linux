# expect-error: field access on non-struct type
fn main() -> i64 {
    let x: i64 = 5;
    return x.f;
}
