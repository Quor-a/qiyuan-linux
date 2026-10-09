# expect: 0
# f64 结构体字段：声明/读写/运算/局部 struct
import "io.mo";
struct P {
    x: f64;
    y: f64;
}
fn main() -> i64 {
    let v: P;
    v.x = 1.5;
    v.y = -2.25;
    print_f64(v.x); print(" "); print_f64(v.y); print("  期望 1.5 -2.25\n");
    v.x = v.x * 2.0;
    print_f64(v.x); print("  期望 3\n");
    let s: f64 = v.x + v.y;
    print_f64(s); print("  期望 0.75\n");
    return 0;
}
