# expect-error: struct assignment requires the same type
struct A { x: i64; }
struct B { y: i64; }
fn main() -> i64 {
    let a: A;
    let b: B;
    a = b;
    return 0;
}
