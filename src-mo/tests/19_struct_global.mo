# expect: 12
struct Pair {
    a: i64;
    b: i64;
}

var g: Pair;

fn main() -> i64 {
    g.a = 5;
    g.b = 7;
    return g.a + g.b;
}
