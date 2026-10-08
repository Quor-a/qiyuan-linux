# expect-error: cannot assign to an array
fn main() -> i64 {
    let a: [4] i64;
    a = 1;
    return 0;
}
