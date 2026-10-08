# manifest —— 读取项目声明文件 mo.mod（用墨语言自己写的）
#
# 对应「声明 / 元数据 / 目录」需求：
# 一个项目用一个纯文本清单描述自己，构建工具据此工作。
import "fs.mo";
import "str.mo";

var m_buf: [8192] byte = 0;
var m_len: i64 = 0;

fn manifest_load(path: i64) -> i64 {
    m_len = read_file(path, &m_buf, 8191);
    if m_len < 0 { return -1; }
    store8(&m_buf + m_len, 0);
    return 0;
}

fn skip_sp(i: i64) -> i64 {
    while m_buf[i] == 32 || m_buf[i] == 9 { i = i + 1; }
    return i;
}

# 取某个 key 的值，写进 dst；找不到返回 0
fn manifest_get(key: i64, dst: i64) -> i64 {
    let i: i64 = 0;
    while i < m_len {
        if m_buf[i] == 35 {
            # 注释：跳到行尾
            while i < m_len {
                if m_buf[i] == 10 { break; }
                i = i + 1;
            }
        } else {
            let j: i64 = 0;
            while load8(key + j) != 0 {
                if m_buf[i + j] != load8(key + j) { break; }
                j = j + 1;
            }
            if load8(key + j) == 0 {
                let p: i64 = skip_sp(i + j);
                if m_buf[p] == 61 {
                    p = skip_sp(p + 1);
                    let s: i64 = p;
                    while m_buf[p] != 10 {
                        if m_buf[p] == 0 { break; }
                        if m_buf[p] == 13 { break; }
                        p = p + 1;
                    }
                    let n: i64 = p - s;
                    memcpy(dst, &m_buf + s, n);
                    store8(dst + n, 0);
                    # 去掉行尾空白
                    while n > 0 {
                        if load8(dst + n - 1) == 32 { store8(dst + n - 1, 0); n = n - 1; }
                        else { break; }
                    }
                    return 1;
                }
            }
            # 跳到下一行
            while i < m_len {
                if m_buf[i] == 10 { i = i + 1; break; }
                i = i + 1;
            }
        }
    }
    return 0;
}
