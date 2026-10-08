# expect: 5
# 用 ptr 下标做缓冲区复制
fn copy(dst: ptr, src: ptr) -> i64 {
    let i: i64 = 0;
    while src[i] != 0 {
        dst[i] = src[i];
        i = i + 1;
    }
    dst[i] = 0;
    return i;
}

fn main() -> i64 {
    let b: [16] byte = 0;
    return copy(&b, "hello");
}
