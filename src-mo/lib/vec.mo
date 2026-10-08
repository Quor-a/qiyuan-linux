# vec —— 动态数组（用墨语言自己写的）
#
# 元素宽度 8 字节，可存 i64 或指针。
# 句柄是一块固定大小的头部，内部保存 {数据指针, 长度, 容量}：
#
#     v + 0   数据区地址
#     v + 8   当前长度
#     v + 16  当前容量
#
# 扩容时只重新分配数据区、头部地址不变 —— 所以句柄可以到处传，
# 不需要像 realloc 那样"返回新指针"。
# 代价：扩容会丢弃旧数据区（bump 分配器不回收），空间上是浪费的。
import "mem.mo";
import "str.mo";

fn vec_new() -> i64 {
    let h: i64 = alloc(24);
    let d: i64 = alloc8(8);
    store64(h, d);
    store64(h + 8, 0);
    store64(h + 16, 8);
    return h;
}

fn vec_len(v: i64) -> i64 {
    return load64(v + 8);
}

fn vec_cap(v: i64) -> i64 {
    return load64(v + 16);
}

# 容量翻倍。初始容量不为 0 时不会死循环。
fn vec_grow(v: i64) -> i64 {
    let old: i64 = load64(v);
    let cap: i64 = load64(v + 16);
    let ncap: i64 = cap * 2;
    let nd: i64 = alloc8(ncap);
    memcpy(nd, old, cap * 8);
    store64(v, nd);
    store64(v + 16, ncap);
    return 0;
}

fn vec_push(v: i64, x: i64) -> i64 {
    let len: i64 = load64(v + 8);
    let cap: i64 = load64(v + 16);
    if len >= cap {
        vec_grow(v);
    }
    let d: i64 = load64(v);
    store64(d + len * 8, x);
    store64(v + 8, len + 1);
    return 0;
}

# 越界不再静默：置错误码并返回 0。
# 为什么不让库直接退出进程——调用方可能想自己决定怎么处理。
# 但"安静地返回 0"必须变成"能被检测到的失败"，这是两回事。
var VEC_ERR: i64 = 0;

# 0=无错 1=下标越界 2=弹空容器 3=容量上限
fn vec_err() -> i64 { return VEC_ERR; }
fn vec_clear_err() -> i64 { VEC_ERR = 0; return 0; }

fn vec_get(v: i64, i: i64) -> i64 {
    let len: i64 = load64(v + 8);
    if i < 0 { VEC_ERR = 1; return 0; }
    if i >= len { VEC_ERR = 1; return 0; }
    let d: i64 = load64(v);
    return load64(d + i * 8);
}

fn vec_set(v: i64, i: i64, x: i64) -> i64 {
    let len: i64 = load64(v + 8);
    if i < 0 { VEC_ERR = 1; return 0; }
    if i >= len { VEC_ERR = 1; return 0; }
    let d: i64 = load64(v);
    store64(d + i * 8, x);
    return 0;
}

# 带检查的读取：越界时直接报错退出，适合"越界就是 bug"的场景
fn vec_getc(v: i64, i: i64) -> i64 {
    let r: i64 = vec_get(v, i);
    if VEC_ERR == 1 {
        syscall(1, 2, "vec: index out of bounds\n", 26, 0, 0, 0);
        syscall(60, 1, 0, 0, 0, 0, 0);
    }
    return r;
}

fn vec_pop(v: i64) -> i64 {
    let len: i64 = load64(v + 8);
    if len <= 0 { VEC_ERR = 2; return 0; }
    let d: i64 = load64(v);
    let x: i64 = load64(d + (len - 1) * 8);
    store64(v + 8, len - 1);
    return x;
}

fn vec_clear(v: i64) -> i64 {
    store64(v + 8, 0);
    return 0;
}
