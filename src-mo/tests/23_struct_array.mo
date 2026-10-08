# expect: 62
# 结构体数组：下标 + 字段读写 + 循环遍历
struct Box {
    v: i64;
    w: i64;
}

fn main() -> i64 {
    let a: [3] Box;
    let i: i64 = 0;
    while i < 3 {
        a[i].v = (i + 1) * 10;
        a[i].w = i;
        i = i + 1;
    }
    return a[0].v + a[1].v + a[2].v + a[2].w;
}
