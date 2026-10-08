# expect-error: duplicate definition
struct S {
    v: i64;
    v: i64;
}

fn main() -> i64 {
    return 0;
}
