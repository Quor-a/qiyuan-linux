# hmac —— HMAC-SHA256 消息认证码（用墨语言自己写的）
#
# 「签名」需求：真正的数字签名（RSA/ECDSA）需要大数运算，
# 单轮做不完且极易出错。这里提供**对称**的消息认证码 HMAC-SHA256，
# 它能解决「消息是否被篡改 / 是否来自持有密钥的一方」。
#
# 非对称签名（验签可公开）需要 RSA 或 Ed25519，属于后续工作。
import "str.mo";
import "crypto.mo";

var ipad: [64] byte = 0;
var opad: [64] byte = 0;
var ibuf: [4096] byte = 0;
var hmac_d: [32] byte = 0;
var hmac_h: [72] byte = 0;

# hmac_sha256(key, klen, msg, mlen, out32)：写 32 字节原始 MAC
# 密钥长于 64 字节时先 hash 一次
fn hmac_sha256(key: i64, klen: i64, msg: i64, mlen: i64, out: i64) -> i64 {
    let k: i64 = key;
    let kl: i64 = klen;
    if klen > 64 {
        sha256(key, klen, &hmac_d);
        k = &hmac_d;
        kl = 32;
    }
    let i: i64 = 0;
    while i < 64 {
        let b: i64 = 0;
        if i < kl { b = load8(k + i); }
        store8(&ipad + i, b ^ 54);      # 0x36
        store8(&opad + i, b ^ 92);      # 0x5c
        i = i + 1;
    }
    # inner = H(ipad || msg)
    memcpy(&ibuf, &ipad, 64);
    if mlen > 0 { memcpy(&ibuf + 64, msg, mlen); }
    sha256(&ibuf, 64 + mlen, &hmac_d);
    # outer = H(opad || inner)
    memcpy(&ibuf, &opad, 64);
    memcpy(&ibuf + 64, &hmac_d, 32);
    sha256(&ibuf, 96, out);
    return 32;
}

# 一步得到十六进制串（dst 至少 65 字节）
fn hmac_hex(key: i64, klen: i64, msg: i64, mlen: i64, dst: i64) -> i64 {
    let d: [32] byte = 0;
    hmac_sha256(key, klen, msg, mlen, &d);
    return hex_of(&d, 32, dst);
}

# 常量时间比较：长度不同直接失败，逐字节累积差异。
# 不能用 strcmp 提前退出 —— 那样会泄漏「前几位是对的」信息。
fn mac_eq(a: i64, b: i64, n: i64) -> i64 {
    let d: i64 = 0;
    let i: i64 = 0;
    while i < n {
        d = d | (load8(a + i) ^ load8(b + i));
        i = i + 1;
    }
    if d == 0 { return 1; }
    return 0;
}

# 验签：mac 是十六进制串形式
fn mac_verify(key: i64, klen: i64, msg: i64, mlen: i64, mac: i64) -> i64 {
    hmac_hex(key, klen, msg, mlen, &hmac_h);
    return mac_eq(&hmac_h, mac, 64);
}
