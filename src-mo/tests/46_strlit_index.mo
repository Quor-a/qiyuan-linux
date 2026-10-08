# expect: 1
# 字符串字面量可以直接下标，不必先赋给 ptr 变量
fn main() -> i64 {
    return "hello"[1] - 100;
}
