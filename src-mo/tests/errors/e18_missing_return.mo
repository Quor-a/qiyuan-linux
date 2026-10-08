# expect-error: missing return statement
fn f() -> i64 {
    let x: i64 = 1;
}

fn main() -> i64 {
    return f();
}
