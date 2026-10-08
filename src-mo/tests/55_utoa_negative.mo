# expect: 0
# utoa 必须能处理负数：原来 while v > 0 对负数直接空循环，输出空串
import "io.mo";
import "str.mo";

var b: [32] byte = 0;

fn main() -> i64 {
    utoa(0 - 42, &b, 10);
    if streq(&b, "-42") == 0 { return 1; }
    utoa(42, &b, 10);
    if streq(&b, "42") == 0 { return 2; }
    utoa(0, &b, 10);
    if streq(&b, "0") == 0 { return 3; }
    utoa(0 - 255, &b, 16);
    if streq(&b, "-ff") == 0 { return 4; }
    return 0;
}
