# expect-error: duplicate definition
fn main() -> i64 {
    let a: i64 = 1;
    let a: i64 = 2;
    return a;
}
