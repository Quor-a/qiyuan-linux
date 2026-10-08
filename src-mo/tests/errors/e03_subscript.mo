# expect-error: subscript on non-array type
fn main() -> i64 {
    let x: i64 = 5;
    return x[0];
}
