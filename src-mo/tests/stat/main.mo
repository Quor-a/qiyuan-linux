# expect: 0
# 统计：均值、方差、相关、回归、中位数（定点 SCALE=1000）
import "io.mo";
import "stat.mo";

var xs: [8] i64 = 0;
var ys: [8] i64 = 0;
var sl: i64 = 0;
var ic: i64 = 0;

fn main() -> i64 {
    # x = [1,2,3,4]  y = [2,3.9,6.1,8]  （近似 y=2x）
    store64(&xs + 0, 1000); store64(&xs + 8, 2000);
    store64(&xs + 16, 3000); store64(&xs + 24, 4000);
    store64(&ys + 0, 2000); store64(&ys + 8, 3900);
    store64(&ys + 16, 6100); store64(&ys + 24, 8000);

    # 均值 = 2.5
    if st_mean(&xs, 4) != 2500 { return 1; }

    # 方差 > 0
    if st_var(&xs, 4) <= 0 { return 2; }

    # 标准差 ~ 1.29
    let sd: i64 = st_sd(&xs, 4);
    if sd < 1200 { return 3; }
    if sd > 1400 { return 3; }

    # 相关系数接近 1（>0.99）
    if st_corr(&xs, &ys, 4) < 990 { return 4; }

    # 斜率约 2.0
    if st_linreg(&xs, &ys, 4, &sl, &ic) < 0 { return 5; }
    if sl < 1900 { return 6; }
    if sl > 2100 { return 6; }

    # 中位数 = 2.5
    if st_median(&xs, 4) != 2500 { return 7; }

    # 整数开方：sqrt(4.0) = 2.0
    if fsqrt(4000) < 1990 { return 8; }
    if fsqrt(4000) > 2010 { return 8; }

    return 0;
}
