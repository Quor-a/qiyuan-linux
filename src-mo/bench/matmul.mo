# 基准：128x128 整数矩阵乘法（约 200 万次乘加）
var A: [16384] i64 = 0;
var B: [16384] i64 = 0;
var C: [16384] i64 = 0;
fn main() -> i64 {
    let i: i64 = 0;
    let N: i64 = 128;
    while i < N {
        let j: i64 = 0;
        while j < N {
            A[i * N + j] = (i + j) & 7;
            B[i * N + j] = (i - j) & 7;
            j = j + 1;
        }
        i = i + 1;
    }
    i = 0;
    while i < N {
        let j: i64 = 0;
        while j < N {
            let s: i64 = 0;
            let k: i64 = 0;
            while k < N {
                s = s + A[i * N + k] * B[k * N + j];
                k = k + 1;
            }
            C[i * N + j] = s;
            j = j + 1;
        }
        i = i + 1;
    }
    return C[0] & 255;
}
