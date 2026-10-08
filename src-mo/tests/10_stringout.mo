# expect: 0
fn puts(s: i64) -> i64 {
    let n: i64 = 0;
    while load8(s + n) != 0 {
        n = n + 1;
    }
    syscall(1, 1, s, n, 0, 0, 0);
    return n;
}
fn main() -> i64 {
    puts("mo: 字符串输出正常\n");
    return 0;
}
