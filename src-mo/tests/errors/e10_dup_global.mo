# expect-error: duplicate definition
var g: i64 = 1;
var g: i64 = 2;

fn main() -> i64 {
    return g;
}
