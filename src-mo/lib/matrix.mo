# matrix —— 稠密矩阵运算（用墨语言自己写的）
#
# 用 f64？墨语言只有 i64 / byte。这里用**定点数**：
#   值以 SCALE=1000 的整数存储（1.5 存成 1500）。
# 这是没有浮点类型时的常规做法，乘法后要除以 SCALE 补回来。
import "io.mo";
import "str.mo";

var SCALE: i64 = 1000;

var m_a: [4096] i64 = 0;     # 最多 64x64
var m_b: [4096] i64 = 0;
var m_c: [4096] i64 = 0;
var M_N: i64 = 0;            # 方阵边长

fn mat_set(m: i64, i: i64, j: i64, v: i64) -> i64 {
    return store64(m + (i * M_N + j) * 8, v);
}

fn mat_get(m: i64, i: i64, j: i64) -> i64 {
    return load64(m + (i * M_N + j) * 8);
}

fn mat_zero(m: i64) -> i64 {
    let i: i64 = 0;
    while i < M_N * M_N {
        store64(m + i * 8, 0);
        i = i + 1;
    }
    return 0;
}

# C = A * B（定点，乘后除以 SCALE）
fn mat_mul(a: i64, b: i64, c: i64) -> i64 {
    let i: i64 = 0;
    while i < M_N {
        let j: i64 = 0;
        while j < M_N {
            let s: i64 = 0;
            let k: i64 = 0;
            while k < M_N {
                let va: i64 = load64(a + (i * M_N + k) * 8);
                let vb: i64 = load64(b + (k * M_N + j) * 8);
                s = s + va * vb / SCALE;
                k = k + 1;
            }
            store64(c + (i * M_N + j) * 8, s);
            j = j + 1;
        }
        i = i + 1;
    }
    return 0;
}

# 转置：B = A^T
fn mat_T(a: i64, b: i64) -> i64 {
    let i: i64 = 0;
    while i < M_N {
        let j: i64 = 0;
        while j < M_N {
            store64(b + (j * M_N + i) * 8, load64(a + (i * M_N + j) * 8));
            j = j + 1;
        }
        i = i + 1;
    }
    return 0;
}

# 行列式（高斯消元，定点除法）
fn mat_det(a: i64) -> i64 {
    let m: [4096] i64 = 0;
    let i: i64 = 0;
    while i < M_N * M_N {
        store64(&m + i * 8, load64(a + i * 8));
        i = i + 1;
    }
    let det: i64 = SCALE;      # 1.0
    let c: i64 = 0;
    while c < M_N {
        # 找主元
        let p: i64 = c;
        let r: i64 = c;
        while r < M_N {
            if load64(&m + (r * M_N + c) * 8) != 0 { p = r; }
            r = r + 1;
        }
        if load64(&m + (p * M_N + c) * 8) == 0 { return 0; }
        if p != c {
            let k: i64 = 0;
            while k < M_N {
                let t: i64 = load64(&m + (c * M_N + k) * 8);
                store64(&m + (c * M_N + k) * 8, load64(&m + (p * M_N + k) * 8));
                store64(&m + (p * M_N + k) * 8, t);
                k = k + 1;
            }
            det = 0 - det;
        }
        det = det * load64(&m + (c * M_N + c) * 8) / SCALE;
        let rr: i64 = c + 1;
        while rr < M_N {
            let f: i64 = load64(&m + (rr * M_N + c) * 8) * SCALE / load64(&m + (c * M_N + c) * 8);
            let cc: i64 = c;
            while cc < M_N {
                let nv: i64 = load64(&m + (rr * M_N + cc) * 8)
                            - f * load64(&m + (c * M_N + cc) * 8) / SCALE;
                store64(&m + (rr * M_N + cc) * 8, nv);
                cc = cc + 1;
            }
            rr = rr + 1;
        }
        c = c + 1;
    }
    return det;
}

# 打印（定点：整数部分.小数部分）
fn fp_print(v: i64) -> i64 {
    if v < 0 {
        print("-");
        v = 0 - v;
    }
    print_i64(v / SCALE);
    print(".");
    let f: i64 = v % SCALE;
    if f < 100 { print("0"); }
    if f < 10 { print("0"); }
    print_i64(f);
    return 0;
}

fn mat_print(m: i64) -> i64 {
    let i: i64 = 0;
    while i < M_N {
        let j: i64 = 0;
        while j < M_N {
            fp_print(load64(m + (i * M_N + j) * 8));
            print(" ");
            j = j + 1;
        }
        print_nl();
        i = i + 1;
    }
    return 0;
}
