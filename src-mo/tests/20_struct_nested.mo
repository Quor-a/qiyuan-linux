# expect: 10
struct Inner {
    v: i64;
}

struct Outer {
    a: i64;
    in: Inner;
    b: i64;
}

fn main() -> i64 {
    let o: Outer;
    o.a = 1;
    o.b = 2;
    o.in.v = 7;
    return o.a + o.b + o.in.v;
}
