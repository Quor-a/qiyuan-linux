# expect: 0
# 密码学与归档：全部用公开测试向量校验，不是"能跑就行"
import "io.mo";
import "str.mo";
import "crypto.mo";
import "archive.mo";
import "fs.mo";

var d: [80] byte = 0;
var ks: [64] byte = 0;
var key: [32] byte = 0;
var non: [12] byte = 0;
var pt: [64] byte = 0;

fn main() -> i64 {
    # --- SHA-256：空串与 "abc" 的标准向量 ---
    sha256_hex("", 0, &d);
    if streq(&d, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == 0 {
        return 1;
    }
    sha256_hex("abc", 3, &d);
    if streq(&d, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0 {
        return 2;
    }
    # 长输入（跨块，验证填充与长度字段）
    let big: [200] byte = 0;
    let i: i64 = 0;
    while i < 199 { store8(&big + i, 97 + (i & 15)); i = i + 1; }
    store8(&big + 199, 0);
    # 只校验长度，说明它跨了两个 512 位块且没崩
    if sha256(&big, 199, &d) != 32 { return 3; }

    # --- CRC32("hello world") = 0x0D4A1185 ---
    # 0x0D4A1185 = 222957957
    if crc32("hello world", 11) != 222957957 { return 4; }

    # --- Base64 往返 ---
    let n: i64 = b64_enc("hello world", 11, &d);
    if streq(&d, "aGVsbG8gd29ybGQ=") == 0 { return 5; }
    let m: i64 = b64_dec(&d, n, &ks);
    store8(&ks + m, 0);
    if streq(&ks, "hello world") == 0 { return 6; }
    # 填充两种形态
    if b64_enc("a", 1, &d) != 4 { return 7; }
    if streq(&d, "YQ==") == 0 { return 8; }
    if b64_enc("ab", 2, &d) != 4 { return 9; }
    if streq(&d, "YWI=") == 0 { return 10; }

    # --- ChaCha20：全 0 key/nonce 的首块标准向量 ---
    chacha_block(&key, &non, 0, &ks);
    if ks[0] != 118 { return 11; }   # 0x76
    if ks[1] != 184 { return 12; }   # 0xb8
    if ks[2] != 224 { return 13; }   # 0xe0
    if ks[3] != 173 { return 14; }   # 0xad
    # 往返加密
    strcpy(&pt, "attack at dawn");
    chacha20_crypt(&key, &non, &pt, 14);
    if streq(&pt, "attack at dawn") == 1 { return 15; }   # 密文绝不能等于明文
    chacha20_crypt(&key, &non, &pt, 14);
    if streq(&pt, "attack at dawn") == 0 { return 16; }

    print("crypto ok\n");
    return 0;
}
