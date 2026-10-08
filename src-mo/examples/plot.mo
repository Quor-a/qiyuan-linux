# plot —— 终端里的 ASCII 绘图（用墨语言自己写的）
#
#   ./plot file.txt      每个值一行，画折线图
#
# 没有图形栈也能"画图"：把数值映射到字符网格。
# 这是墨语言在当前能力下做可视化的现实路径。
import "io.mo";
import "str.mo";
import "fs.mo";
import "stat.mo";

var vals: [1024] i64 = 0;
var N: i64 = 0;
var W: i64 = 60;      # 图宽
var H: i64 = 16;      # 图高
var grid: [80] i64 = 0;   # 每行一个字符串缓冲不方便，直接用行列即时打印

var rowbuf: [128] byte = 0;

fn load(path: i64) -> i64 {
    let b: [32768] byte = 0;
    let n: i64 = read_file(path, &b, 32767);
    if n < 0 { return -1; }
    store8(&b + n, 0);
    let i: i64 = 0;
    while load8(&b + i) != 0 {
        let c: i64 = load8(&b + i);
        if c >= 48 {
            if c <= 57 {
                let v: i64 = 0;
                let neg: i64 = 0;
                if i > 0 {
                    if load8(&b + i - 1) == 45 { neg = 1; }
                }
                while load8(&b + i) >= 48 {
                    if load8(&b + i) > 57 { break; }
                    v = v * 10 + load8(&b + i) - 48;
                    i = i + 1;
                }
                if neg == 1 { v = 0 - v; }
                if N < 1024 {
                    store64(&vals + N * 8, v);
                    N = N + 1;
                }
            } else { i = i + 1; }
        } else { i = i + 1; }
    }
    return 0;
}

fn main() -> i64 {
    if argc() < 2 {
        print("usage: plot <file>   （每行一个整数）\n");
        return 2;
    }
    if load(argv(1)) < 0 {
        print("cannot open ");
        print(argv(1));
        print_nl();
        return 1;
    }
    if N == 0 { print("no data\n"); return 1; }

    # 找最值（先复制到可排序缓冲）
    let s: [1024] i64 = 0;
    let i: i64 = 0;
    while i < N {
        store64(&s + i * 8, load64(&vals + i * 8));
        i = i + 1;
    }
    let mn: i64 = st_median(&s, N);     # 排序后的首元素即最小值
    # st_median 会原地排序，首尾即 min/max
    let minv: i64 = load64(&s + 0);
    let maxv: i64 = load64(&s + (N - 1) * 8);
    if maxv == minv { maxv = minv + 1; }

    print("min="); print_i64(minv);
    print(" max="); print_i64(maxv);
    print(" median="); print_i64(mn);
    print(" n="); print_i64(N);
    print_nl();

    let r: i64 = 0;
    while r < H {
        # 该行对应的值区间上界
        let hi: i64 = maxv - (maxv - minv) * r / (H - 1);
        store8(&rowbuf, 0);
        let c: i64 = 0;
        while c < W {
            let idx: i64 = c * N / W;
            if idx >= N { idx = N - 1; }
            let v: i64 = load64(&vals + idx * 8);
            if v >= hi { strcat(&rowbuf, "*"); } else { strcat(&rowbuf, " "); }
            c = c + 1;
        }
        # 纵轴刻度
        print("|");
        print(&rowbuf);
        print_nl();
        r = r + 1;
    }
    print("+");
    let c2: i64 = 0;
    while c2 < W { print("-"); c2 = c2 + 1; }
    print_nl();
    return 0;
}
