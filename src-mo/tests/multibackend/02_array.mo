# expect: 140
# 0+1+4+9+16+25+36+49 = 140
fn main() -> i64 {
    let a: [8] i64;
    let i: i64 = 0;
    while i < 8 {
        a[i] = i * i;
        i = i + 1;
    }
    let t: i64 = 0;
    i = 0;
    while i < 8 {
        t = t + a[i];
        i += 1;
    }
    return t & 255;
}
