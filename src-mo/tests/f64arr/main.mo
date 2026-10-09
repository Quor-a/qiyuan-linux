# expect: 0
# f64 数组：局部/全局声明、下标读写、函数传参、循环累加、矩阵乘
import "io.mo";
var gm: [4] f64 = 0;

fn arrsum(p: i64, n: i64) -> f64 {
    let s: f64 = 0.0;
    let i: i64 = 0;
    while i < n { s = s + load64(p + i * 8); i = i + 1; }
    return s;
}

fn main() -> i64 {
    let a: [4] f64 = 0;
    a[0] = 1.5; a[1] = 2.25; a[2] = 3.75; a[3] = 0.5;
    # 1) 局部数组下标读写 + 循环累加
    let s: f64 = 0.0;
    let i: i64 = 0;
    while i < 4 { s = s + a[i]; i = i + 1; }
    print_f64(s); print(" 局部 sum 期望 8\n");
    # 2) 全局数组 + 指针传参求和
    gm[0] = 10.5; gm[1] = 20.25; gm[2] = 3.5; gm[3] = 0.25;
    print_f64(arrsum(&gm, 4)); print(" 全局 sum 期望 34.5\n");
    # 3) 2x2 矩阵乘：[1,2;3,4]x[5,6;7,8]=[19,22;43,50]
    let A: [4] f64 = 0;
    let B: [4] f64 = 0;
    A[0]=1.0; A[1]=2.0; A[2]=3.0; A[3]=4.0;
    B[0]=5.0; B[1]=6.0; B[2]=7.0; B[3]=8.0;
    print_f64(A[0]*B[0]+A[1]*B[2]); print(" ");
    print_f64(A[0]*B[1]+A[1]*B[3]); print(" ");
    print_f64(A[2]*B[0]+A[3]*B[2]); print(" ");
    print_f64(A[2]*B[1]+A[3]*B[3]); print(" 矩阵乘 期望 19 22 43 50\n");
    return 0;
}
