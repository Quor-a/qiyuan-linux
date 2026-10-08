# map —— 字符串键到 i64 的映射（用墨语言自己写的）
#
# 开链法：桶数组 + 每个桶一条链表。负载因子超过 1 时把桶数翻倍。
#
#     m + 0    桶数组地址（每桶是一个链表头指针，0 表示空）
#     m + 8    桶数量
#     m + 16   元素个数
#
# 链表节点：{ next, hash, key指针, value }
#
# 键在插入时被拷进堆里，因此调用方之后修改或复用自己的缓冲区都安全。
# 这一点很重要：早期版本的容器几乎都栽在"存了别人的指针"上。
import "mem.mo";
import "str.mo";

var NBUCKETS: i64 = 16;

# FNV-1a：够快，分布也够用
fn hash(s: ptr) -> i64 {
    let h: i64 = 1469598103934665603;
    let i: i64 = 0;
    while s[i] != 0 {
        h = h ^ s[i];
        h = h * 1099511628211;
        i = i + 1;
    }
    # 结果可能为负，取绝对值避免下标为负
    if h < 0 { h = 0 - h; }
    return h;
}

fn map_new() -> i64 {
    let m: i64 = alloc(24);
    let b: i64 = alloc8(NBUCKETS);
    memset(b, 0, NBUCKETS * 8);
    store64(m, b);
    store64(m + 8, NBUCKETS);
    store64(m + 16, 0);
    return m;
}

fn map_len(m: i64) -> i64 {
    return load64(m + 16);
}

# 找 key 所在的节点，找不到返回 0
fn node_of(m: i64, key: ptr) -> i64 {
    let nb: i64 = load64(m + 8);
    let h: i64 = hash(key);
    let n: i64 = load64(load64(m) + (h % nb) * 8);
    while n != 0 {
        if load64(n + 8) == h {
            if streq(load64(n + 16), key) == 1 {
                return n;
            }
        }
        n = load64(n + 0);
    }
    return 0;
}

fn mk_node(key: ptr, h: i64, val: i64) -> i64 {
    let n: i64 = alloc8(4);
    let k: i64 = alloc(strlen(key) + 1);
    strcpy(k, key);
    store64(n + 0, 0);
    store64(n + 8, h);
    store64(n + 16, k);
    store64(n + 24, val);
    return n;
}

# 桶数翻倍并重挂所有节点
fn rehash(m: i64) -> i64 {
    let oldnb: i64 = load64(m + 8);
    let oldb: i64 = load64(m);
    let nnb: i64 = oldnb * 2;
    let nb: i64 = alloc8(nnb);
    memset(nb, 0, nnb * 8);
    let i: i64 = 0;
    while i < oldnb {
        let n: i64 = load64(oldb + i * 8);
        while n != 0 {
            let nx: i64 = load64(n + 0);
            let h: i64 = load64(n + 8);
            let slot: i64 = h % nnb;
            store64(n + 0, load64(nb + slot * 8));
            store64(nb + slot * 8, n);
            n = nx;
        }
        i = i + 1;
    }
    store64(m, nb);
    store64(m + 8, nnb);
    return 0;
}

# 插入或更新。返回 1 表示新建，0 表示更新
fn map_put(m: i64, key: ptr, val: i64) -> i64 {
    let n: i64 = node_of(m, key);
    if n != 0 {
        store64(n + 24, val);
        return 0;
    }
    let cnt: i64 = load64(m + 16);
    let nb: i64 = load64(m + 8);
    # 负载因子 > 1 就扩容，保证链长期望很短
    if cnt + 1 > nb {
        rehash(m);
        nb = load64(m + 8);
    }
    let h: i64 = hash(key);
    let nd: i64 = mk_node(key, h, val);
    let slot: i64 = h % nb;
    let b: i64 = load64(m);
    store64(nd + 0, load64(b + slot * 8));
    store64(b + slot * 8, nd);
    store64(m + 16, cnt + 1);
    return 1;
}

# 取值。键不存在返回 0
fn map_get(m: i64, key: ptr) -> i64 {
    let n: i64 = node_of(m, key);
    if n == 0 { return 0; }
    return load64(n + 24);
}

# 键是否存在
fn map_has(m: i64, key: ptr) -> i64 {
    if node_of(m, key) == 0 { return 0; }
    return 1;
}

# 计数用途：不存在则从 0 开始 +1
fn map_inc(m: i64, key: ptr) -> i64 {
    let n: i64 = node_of(m, key);
    if n != 0 {
        let v: i64 = load64(n + 24) + 1;
        store64(n + 24, v);
        return v;
    }
    map_put(m, key, 1);
    return 1;
}
