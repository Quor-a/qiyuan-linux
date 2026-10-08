# expect: 27
struct P { x: i64; y: i64; }
fn main() -> i64 {
    let p: P;
    p.x = 5;
    p.y = 7;
    let q: P;
    q.x = 15;
    return p.x + p.y + q.x;
}
