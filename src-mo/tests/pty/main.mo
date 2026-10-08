# expect: 0
# 伪终端：主端能开、从端能连、写入能从主端读回；HMAC 与日志
import "io.mo";
import "str.mo";
import "pty.mo";
import "hmac.mo";
import "log.mo";

var b: [256] byte = 0;
var out: [80] byte = 0;

fn main() -> i64 {
    # --- PTY ---
    if pty_master() != 0 { return 1; }
    let p: [64] byte = 0;
    pty_slave_path(&p);
    # 路径必须以 /dev/pts/ 开头
    if strstr(&p, "/dev/pts/") != 0 { return 2; }
    pty_winsize(24, 80);
    let s: i64 = pty_slave();
    if s < 0 { return 3; }
    syscall(1, s, "hi\n", 3, 0, 0, 0);
    let n: i64 = pty_read(&b, 255);
    if n <= 0 { return 4; }
    store8(&b + n, 0);
    if strstr(&b, "hi") < 0 { return 5; }   # 注意：strstr 返回 0 是「找到了」
    syscall(3, s, 0, 0, 0, 0, 0);
    pty_close();

    # --- HMAC-SHA256：RFC 4231 测试向量 ---
    let k: [20] byte = 0;
    let i: i64 = 0;
    while i < 20 { store8(&k + i, 11); i = i + 1; }
    hmac_hex(&k, 20, "Hi There", 8, &out);
    if streq(&out, "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7") == 0 {
        return 6;
    }
    if mac_verify(&k, 20, "Hi There", 8, &out) != 1 { return 7; }
    # 消息改一个字符就必须验不过
    if mac_verify(&k, 20, "Hi Therf", 8, &out) != 0 { return 8; }

    # --- 日志级别过滤 ---
    log_set_level(3);
    log_info("这条被过滤");
    log_error("这条要进缓冲");
    log_set_level(1);
    # 只看最近 1 条应是 ERROR 那条
    let c: i64 = log_tail(1);
    if c != 1 { return 9; }

    print("pty + hmac + log ok\n");
    return 0;
}
