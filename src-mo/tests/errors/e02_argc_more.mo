# expect-error: wrong number of arguments
fn f(a: i64) -> i64 {
    return a;
}
fn main() -> i64 {
    return f(1, 2, 3);
}
