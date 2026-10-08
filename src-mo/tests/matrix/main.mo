# expect: 0
# 定点矩阵：乘单位阵、转置、行列式
import "io.mo";
import "matrix.mo";

var xs: [8] i64 = 0;

fn main() -> i64 {
    M_N = 2;

    # A = [[1.5, 2.0], [3.0, 4.0]]
    store64(&m_a + 0, 1500);  store64(&m_a + 8, 2000);
    store64(&m_a + 16, 3000); store64(&m_a + 24, 4000);

    # B = I
    store64(&m_b + 0, 1000); store64(&m_b + 8, 0);
    store64(&m_b + 16, 0);   store64(&m_b + 24, 1000);

    # A * I == A（对角元）
    mat_mul(&m_a, &m_b, &m_c);
    if load64(&m_c + 0) != 1500 { return 1; }
    if load64(&m_c + 24) != 4000 { return 2; }

    # 转置：A^T[0][1] 应为 3.0
    mat_T(&m_a, &m_c);
    if load64(&m_c + 8) != 3000 { return 3; }

    # det([[1.5,2],[3,4]]) = 1.5*4 - 2*3 = 6 - 6 = 0
    if mat_det(&m_a) != 0 { return 4; }

    # 换一个非奇异的：[[2,0],[0,3]] det = 6.0
    store64(&m_a + 0, 2000); store64(&m_a + 8, 0);
    store64(&m_a + 16, 0);   store64(&m_a + 24, 3000);
    let d: i64 = mat_det(&m_a);
    if d < 5900 { return 5; }
    if d > 6100 { return 5; }

    return 0;
}
