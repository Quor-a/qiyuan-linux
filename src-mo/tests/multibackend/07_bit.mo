# expect: 163
fn main() -> i64 {
    let a: i64 = 60;      # 0b111100
    let b: i64 = 13;      # 0b001101
    let r: i64 = 0;
    r = r + (a & b);      # 12
    r = r + (a | b);      # 61
    r = r + (a ^ b);      # 49
    r = r + (b << 1);     # 26
    r = r + (a >> 2);     # 15
    return r & 255;       # 163 & 255
}
