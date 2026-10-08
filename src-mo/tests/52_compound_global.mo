# expect: 7
# 全局变量的复合赋值
var g: i64 = 3;

fn main() -> i64 {
    g += 4;
    return g;
}
