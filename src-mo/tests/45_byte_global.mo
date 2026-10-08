# expect: 44
# 全局 byte 与 byte 形参
var g: byte = 0;

fn setv(v: byte) -> i64 {
    g = v;
    return 0;
}

fn main() -> i64 {
    setv(300);
    return g;
}
