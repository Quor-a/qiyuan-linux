# stat —— 统计计算（用墨语言自己写的）
#
# 同样用定点（SCALE=1000）。提供：均值、方差、标准差、
# 协方差、皮尔逊相关、线性回归（最小二乘）、中位数、分位数。
import "matrix.mo";

var ST_SCALE: i64 = 1000;

fn st_mean(a: i64, n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < n {
        s = s + load64(a + i * 8);
        i = i + 1;
    }
    if n == 0 { return 0; }
    return s / n;
}

# 方差（定点：先算平方和再除）
fn st_var(a: i64, n: i64) -> i64 {
    if n < 2 { return 0; }
    let m: i64 = st_mean(a, n);
    let s: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let d: i64 = load64(a + i * 8) - m;
        s = s + d * d / ST_SCALE;
        i = i + 1;
    }
    return s / (n - 1);
}

# 标准差：牛顿迭代开方（整数平方根）
fn isqrt(v: i64) -> i64 {
    if v <= 0 { return 0; }
    let x: i64 = v;
    let i: i64 = 0;
    while i < 40 {
        let nx: i64 = (x + v / x) / 2;
        if nx == x { return x; }
        if nx > x {
            if nx - x == 1 { return x; }
        }
        x = nx;
        i = i + 1;
    }
    return x;
}

# sqrt(定点值) -> 定点
fn fsqrt(v: i64) -> i64 {
    if v <= 0 { return 0; }
    return isqrt(v * ST_SCALE);
}

fn st_sd(a: i64, n: i64) -> i64 {
    return fsqrt(st_var(a, n));
}

# 协方差
fn st_cov(x: i64, y: i64, n: i64) -> i64 {
    if n < 2 { return 0; }
    let mx: i64 = st_mean(x, n);
    let my: i64 = st_mean(y, n);
    let s: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let dx: i64 = load64(x + i * 8) - mx;
        let dy: i64 = load64(y + i * 8) - my;
        s = s + dx * dy / ST_SCALE;
        i = i + 1;
    }
    return s / (n - 1);
}

# 皮尔逊相关系数（返回定点，-1.0 ~ 1.0）
fn st_corr(x: i64, y: i64, n: i64) -> i64 {
    let c: i64 = st_cov(x, y, n);
    let vx: i64 = st_var(x, n);
    let vy: i64 = st_var(y, n);
    if vx == 0 { return 0; }
    if vy == 0 { return 0; }
    let d: i64 = fsqrt(vx * vy / ST_SCALE);
    if d == 0 { return 0; }
    return c * ST_SCALE / d;
}

# 线性回归 y = a + b*x，斜率写进 *slope，截距写进 *inter
fn st_linreg(x: i64, y: i64, n: i64, slope: i64, inter: i64) -> i64 {
    let vx: i64 = st_var(x, n);
    if vx == 0 { return -1; }
    let b: i64 = st_cov(x, y, n) * ST_SCALE / vx;
    let mx: i64 = st_mean(x, n);
    let my: i64 = st_mean(y, n);
    store64(slope, b);
    store64(inter, my - b * mx / ST_SCALE);
    return 0;
}

# 中位数（原地冒泡，n 小）
fn st_median(a: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n - 1 {
        let j: i64 = 0;
        while j < n - 1 - i {
            if load64(a + j * 8) > load64(a + (j + 1) * 8) {
                let t: i64 = load64(a + j * 8);
                store64(a + j * 8, load64(a + (j + 1) * 8));
                store64(a + (j + 1) * 8, t);
            }
            j = j + 1;
        }
        i = i + 1;
    }
    if (n % 2) == 1 { return load64(a + (n / 2) * 8); }
    return (load64(a + (n / 2 - 1) * 8) + load64(a + (n / 2) * 8)) / 2;
}
