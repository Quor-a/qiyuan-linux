# 基准：字符串扫描。考察 byte/ptr 下标与比较
import "str.mo";
var buf: [4096] byte = 0;
fn main() -> i64 {
    let i: i64 = 0;
    while i < 4095 {
        buf[i] = 97 + (i & 15);
        i = i + 1;
    }
    buf[4095] = 0;
    let n: i64 = 0;
    let r: i64 = 0;
    while n < 3000 {
        let j: i64 = 0;
        while buf[j] != 0 {
            if buf[j] == 100 { r = r + 1; }
            j = j + 1;
        }
        n = n + 1;
    }
    return r & 255;
}
