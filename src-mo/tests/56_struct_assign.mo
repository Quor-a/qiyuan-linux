# 结构体整体赋值：逐字段深拷贝
# expect: 123
struct P {
    a: i64;
    b: i64;
    c: i64;
}
fn main() -> i64 {
    let p: P;
    p.a = 1;
    p.b = 2;
    p.c = 3;
    let q: P;
    q = p;
    p.a = 100;          # 改 p 不应影响 q（说明是真拷贝，不是别名）
    return q.a * 100 + q.b * 10 + q.c;
}
