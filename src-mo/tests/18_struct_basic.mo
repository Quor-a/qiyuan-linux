# expect: 7
struct Point {
    x: i64;
    y: i64;
}

fn main() -> i64 {
    let p: Point;
    p.x = 3;
    p.y = 4;
    return p.x + p.y;
}
