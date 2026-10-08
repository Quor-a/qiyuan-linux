# expect: 7
# 只要有 return 就算通过（不做全路径分析，见文档）
fn pick(c: i64) -> i64 {
    if c > 0 {
        return 7;
    }
    return 0;
}

fn main() -> i64 {
    return pick(1);
}
