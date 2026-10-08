# expect: 7
# 全局结构体在非 main 函数中访问（回归：曾错误地按局部变量寻址）
struct S {
    a: i64;
    b: i64;
}

var st: S;

fn work() -> i64 {
    st.a = 3;
    st.b = st.b + 4;
    return st.a + st.b;
}

fn main() -> i64 {
    return work();
}
