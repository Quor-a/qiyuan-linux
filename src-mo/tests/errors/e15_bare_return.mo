# expect-error: return with no value
fn f() -> i64 {
    return;
}

fn main() -> i64 {
    return f();
}
