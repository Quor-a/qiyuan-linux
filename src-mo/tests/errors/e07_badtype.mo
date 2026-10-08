# expect-error: unknown type
struct S {
    v: NoSuchType;
}
fn main() -> i64 {
    return 0;
}
