# expect: 15
fn main() -> i64 {
    return (0xff & 0x0f) | (6 ^ 3) | ((1 << 3) & 8) | (0 == 0);
}
