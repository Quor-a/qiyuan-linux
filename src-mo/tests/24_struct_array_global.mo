# expect: 14
# 全局结构体数组
struct P {
    x: i64;
    y: i64;
}

var pts: [4] P = 0;

fn main() -> i64 {
    pts[0].x = 5;
    pts[1].y = 9;
    return pts[0].x + pts[1].y;
}
