# expect: 0
fn main() -> i64 {
    syscall(1, 1, "hello, mo!\n", 11, 0, 0, 0);
    return 0;
}
