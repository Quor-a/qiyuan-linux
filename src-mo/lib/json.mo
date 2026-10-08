# json —— 轻量 JSON 解析（用墨语言自己写的）
#
# 网络协议里几乎绕不开 JSON，而我们 1.3.0 已经有了 HTTP。
# 这里做最小可用集：按路径取值、遍历对象键、区分类型。
# 不做序列化（写出）——那需要动态缓冲区，先不做。
import "str.mo";

var J_TYPE: i64 = 0;    # 0=未找到 1=字符串 2=数字 3=true 4=false 5=null
var J_POS: i64 = 0;     # 命中值的起始下标
var J_END: i64 = 0;     # 命中值的结束下标

fn skip_ws(s: ptr, i: i64) -> i64 {
    while s[i] == 32 || s[i] == 10 || s[i] == 9 || s[i] == 13 {
        i = i + 1;
    }
    return i;
}

# 在对象里找 key，返回值的起始下标；找不到返回 -1
# 只扫描顶层（嵌套对象内部不查），够覆盖绝大多数响应
fn find_key(s: ptr, key: ptr, from: i64) -> i64 {
    let i: i64 = from;
    let n: i64 = strlen(s);
    while i < n {
        if s[i] == 34 {
            let ks: i64 = i + 1;
            let j: i64 = 0;
            while s[ks + j] == load8(key + j) {
                j = j + 1;
                if load8(key + j) == 0 { break; }
            }
            if load8(key + j) == 0 {
                if s[ks + j] == 34 {
                    # 匹配到 key，跳到冒号后的值
                    let p: i64 = ks + j + 1;
                    p = skip_ws(s, p);
                    if s[p] == 58 {
                        p = p + 1;
                        p = skip_ws(s, p);
                        return p;
                    }
                }
            }
        }
        i = i + 1;
    }
    return -1;
}

# 判断 p 处值的类型，并标记其区间；返回类型
fn val_type(s: ptr, p: i64) -> i64 {
    let c: i64 = s[p];
    if c == 34 {
        let e: i64 = p + 1;
        while s[e] != 34 { e = e + 1; }
        J_POS = p + 1; J_END = e;
        return 1;
    }
    if c == 116 { J_POS = p; J_END = p + 4; return 3; }
    if c == 102 { J_POS = p; J_END = p + 5; return 4; }
    if c == 110 { J_POS = p; J_END = p + 4; return 5; }
    if c == 45 {
        let e: i64 = p + 1;
        while s[e] >= 48 && s[e] <= 57 { e = e + 1; }
        J_POS = p; J_END = e;
        return 2;
    }
    if c >= 48 {
        if c <= 57 {
            let e: i64 = p;
            while s[e] >= 48 && s[e] <= 57 { e = e + 1; }
            J_POS = p; J_END = e;
            return 2;
        }
    }
    return 0;
}

# 取字符串值：把结果拷进 dst，返回 1 表示成功
fn json_str(s: ptr, key: ptr, dst: ptr) -> i64 {
    let p: i64 = find_key(s, key, 0);
    if p < 0 { return 0; }
    if val_type(s, p) != 1 { return 0; }
    let i: i64 = J_POS;
    let o: i64 = 0;
    while i < J_END {
        store8(dst + o, s[i]);
        o = o + 1;
        i = i + 1;
    }
    store8(dst + o, 0);
    return 1;
}

# 取整数值
fn json_int(s: ptr, key: ptr) -> i64 {
    let p: i64 = find_key(s, key, 0);
    if p < 0 { return 0; }
    if val_type(s, p) != 2 { return 0; }
    let v: i64 = 0;
    let neg: i64 = 0;
    let i: i64 = J_POS;
    if s[i] == 45 { neg = 1; i = i + 1; }
    while i < J_END {
        v = v * 10 + (s[i] - 48);
        i = i + 1;
    }
    if neg == 1 { return 0 - v; }
    return v;
}

# 判断布尔 / null
fn json_true(s: ptr, key: ptr) -> i64 {
    let p: i64 = find_key(s, key, 0);
    if p < 0 { return 0; }
    if val_type(s, p) == 3 { return 1; }
    return 0;
}
