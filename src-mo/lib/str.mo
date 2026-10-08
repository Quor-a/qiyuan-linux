# 字符串与字节缓冲区
#   用 ptr（指向字节的指针）与下标语法写成，不再手工 load8 / store8
#   ptr 没有长度信息，所以下标不做越界检查——这与 C 的字符指针一致

fn strlen(s: ptr) -> i64 {
    let i: i64 = 0;
    while s[i] != 0 {
        i = i + 1;
    }
    return i;
}

fn streq(a: ptr, b: ptr) -> i64 {
    let i: i64 = 0;
    while a[i] != 0 {
        if a[i] != b[i] {
            return 0;
        }
        i = i + 1;
    }
    if b[i] != 0 {
        return 0;
    }
    return 1;
}

fn strcmp(a: ptr, b: ptr) -> i64 {
    let i: i64 = 0;
    while 1 {
        if a[i] != b[i] {
            return a[i] - b[i];
        }
        if a[i] == 0 {
            return 0;
        }
        i = i + 1;
    }
    return 0;
}

fn strcpy(dst: ptr, src: ptr) -> i64 {
    let i: i64 = 0;
    while src[i] != 0 {
        dst[i] = src[i];
        i = i + 1;
    }
    dst[i] = 0;
    return dst;
}

fn strcat(dst: ptr, src: ptr) -> i64 {
    let i: i64 = strlen(dst);
    let j: i64 = 0;
    while src[j] != 0 {
        dst[i] = src[j];
        i = i + 1;
        j = j + 1;
    }
    dst[i] = 0;
    return dst;
}

# 在「到下一个 \n 为止」的范围内找子串；找到返回起始下标，找不到返回 -1
fn strchr(s: ptr, c: i64) -> i64 {
    let i: i64 = 0;
    while s[i] != 0 {
        if s[i] == c {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn is_digit(c: i64) -> i64 {
    if c >= 48 {
        if c <= 57 {
            return 1;
        }
    }
    return 0;
}

# 十进制字符串转整数。支持前导 '-'，遇非数字停止。
fn atoi(s: ptr) -> i64 {
    let i: i64 = 0;
    let neg: i64 = 0;
    if s[0] == 45 {
        neg = 1;
        i = 1;
    }
    let v: i64 = 0;
    while is_digit(s[i]) == 1 {
        v = v * 10 + (s[i] - 48);
        i = i + 1;
    }
    if neg == 1 {
        return 0 - v;
    }
    return v;
}

# 以下按字节操作内存，不解释为字符串
fn memset(p: i64, v: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        store8(p + i, v);
        i = i + 1;
    }
    return p;
}

fn memcpy(dst: i64, src: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        store8(dst + i, load8(src + i));
        i = i + 1;
    }
    return dst;
}

fn memcmp(a: i64, b: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        if load8(a + i) != load8(b + i) {
            return load8(a + i) - load8(b + i);
        }
        i = i + 1;
    }
    return 0;
}

# 找子串，返回起始下标，找不到返回 -1
fn strstr(hay: ptr, needle: ptr) -> i64 {
    let i: i64 = 0;
    let hn: i64 = strlen(hay);
    let nn: i64 = strlen(needle);
    if nn == 0 { return 0; }
    while i + nn <= hn {
        let j: i64 = 0;
        while hay[i + j] == needle[j] {
            j = j + 1;
            if j == nn { return i; }
        }
        i = i + 1;
    }
    return 0 - 1;
}
