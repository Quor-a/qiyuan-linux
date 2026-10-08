# 冒泡排序 + 结构体统计：验证阶段一语法表达力
struct Stat {
    swaps: i64;
    passes: i64;
}

var data: [8] i64 = 0;
var st: Stat;

fn init() -> i64 {
    let seed: i64 = 7;
    let i: i64 = 0;
    while i < 8 {
        seed = (seed * 37 + 11) % 100;
        data[i] = seed;
        i = i + 1;
    }
    return 0;
}

fn sort(n: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let t: i64 = 0;
    while i < n {
        j = 0;
        while j < n - 1 - i {
            if data[j] > data[j + 1] {
                t = data[j];
                data[j] = data[j + 1];
                data[j + 1] = t;
                st.swaps = st.swaps + 1;
            }
            j = j + 1;
        }
        st.passes = st.passes + 1;
        i = i + 1;
    }
    return 0;
}

fn put2(v: i64) -> i64 {
    let buf: [2] i64 = 0;
    store8(&buf, 48 + v / 10);
    store8(&buf + 1, 48 + v % 10);
    syscall(1, 1, &buf, 2, 0, 0, 0);
    syscall(1, 1, " ", 1, 0, 0, 0);
    return 0;
}

fn main() -> i64 {
    init();
    sort(8);
    syscall(1, 1, "sorted: ", 8, 0, 0, 0);
    let i: i64 = 0;
    while i < 8 {
        put2(data[i]);
        i = i + 1;
    }
    syscall(1, 1, "\n", 1, 0, 0, 0);
    return st.passes;
}
