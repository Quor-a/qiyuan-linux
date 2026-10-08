# expect-error: duplicate definition
fn f(a: i64, a: i64) -> i64 {
    return a;
}

fn main() -> i64 {
    return f(1, 2);
}
