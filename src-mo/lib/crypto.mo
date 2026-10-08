# crypto —— 纯计算的哈希与对称加密（用墨语言自己写的）
#
# 墨语言不依赖任何 libc，但这些算法全是纯位运算与查表，
# 不需要任何系统调用 —— 所以能完全用墨语言自己实现。
# 这是「无 libc」带来的另一个好处：密码学库没有外部依赖。

var M32: i64 = 4294967295;      # 0xFFFFFFFF

# ---- 32 位辅助：墨语言只有 i64，所有 32 位运算都要手动截断 ----

# 逻辑右移：算术右移对负数会补符号位，故先截成 32 位正数再移
fn shr32(x: i64, n: i64) -> i64 {
    return (x & M32) / (1 << n);
}

# 循环右移（32 位）
fn rotr32(x: i64, n: i64) -> i64 {
    let v: i64 = x & M32;
    return (shr32(v, n) | ((v << (32 - n)) & M32)) & M32;
}

# 循环左移（32 位），ChaCha20 用
fn rotl32(x: i64, n: i64) -> i64 {
    let v: i64 = x & M32;
    return ((v << n) & M32) | shr32(v, 32 - n);
}

# ---- CRC32（IEEE，用于 gzip 与通用校验）----

var crc_tab: [256] i64 = 0;
var crc_ready: i64 = 0;

fn crc_init() -> i64 {
    if crc_ready == 1 { return 0; }
    let i: i64 = 0;
    while i < 256 {
        let c: i64 = i;
        let k: i64 = 0;
        while k < 8 {
            if (c & 1) == 1 {
                c = 3988292384 ^ shr32(c, 1);
            } else {
                c = shr32(c, 1);
            }
            k = k + 1;
        }
        crc_tab[i] = c;
        i = i + 1;
    }
    crc_ready = 1;
    return 0;
}

# 计算 buf[0..n) 的 CRC32
fn crc32(buf: i64, n: i64) -> i64 {
    crc_init();
    let c: i64 = 4294967295;
    let i: i64 = 0;
    while i < n {
        let b: i64 = load8(buf + i);
        c = crc_tab[(c ^ b) & 255] ^ shr32(c, 8);
        i = i + 1;
    }
    return (c ^ 4294967295) & M32;
}

# ---- SHA-256 ----

var K256: [64] i64 = 0;
var k256_ready: i64 = 0;

fn k256_init() -> i64 {
    if k256_ready == 1 { return 0; }
    # 前 16 个是分数部分常量，后 48 个是立方根小数部分，
    # 全部写死在表里（从标准取，避免运行时算浮点）
    K256[0] = 1116352408; K256[1] = 1899447441; K256[2] = 3049323471;
    K256[3] = 3921009573; K256[4] = 961987163; K256[5] = 1508970993;
    K256[6] = 2453635748; K256[7] = 2870763221; K256[8] = 3624381080;
    K256[9] = 310598401; K256[10] = 607225278; K256[11] = 1426881987;
    K256[12] = 1925078388; K256[13] = 2162078206; K256[14] = 2614888103;
    K256[15] = 3248222580; K256[16] = 3835390401; K256[17] = 4022224774;
    K256[18] = 264347078; K256[19] = 604807628; K256[20] = 770255983;
    K256[21] = 1249150122; K256[22] = 1555081692; K256[23] = 1996064986;
    K256[24] = 2554220882; K256[25] = 2821834349; K256[26] = 2952996808;
    K256[27] = 3210313671; K256[28] = 3336571891; K256[29] = 3584528711;
    K256[30] = 113926993; K256[31] = 338241895; K256[32] = 666307205;
    K256[33] = 773529912; K256[34] = 1294757372; K256[35] = 1396182291;
    K256[36] = 1695183700; K256[37] = 1986661051; K256[38] = 2177026350;
    K256[39] = 2456956037; K256[40] = 2730485921; K256[41] = 2820302411;
    K256[42] = 3259730800; K256[43] = 3345764771; K256[44] = 3516065817;
    K256[45] = 3600352804; K256[46] = 4094571909; K256[47] = 275423344;
    K256[48] = 430227734; K256[49] = 506948616; K256[50] = 659060556;
    K256[51] = 883997877; K256[52] = 958139571; K256[53] = 1322822218;
    K256[54] = 1537002063; K256[55] = 1747873779; K256[56] = 1955562222;
    K256[57] = 2024104815; K256[58] = 2227730452; K256[59] = 2361852424;
    K256[60] = 2428436474; K256[61] = 2756734187; K256[62] = 3204031479;
    K256[63] = 3329325298;
    k256_ready = 1;
    return 0;
}

var W: [64] i64 = 0;

# sha256(msg, n, out)：out 至少 32 字节，写的是原始字节（不是十六进制串）
fn sha256(msg: i64, n: i64, out: i64) -> i64 {
    k256_init();
    let h0: i64 = 1779033703; let h1: i64 = 3144134277;
    let h2: i64 = 1013904242; let h3: i64 = 2773480762;
    let h4: i64 = 1359893119; let h5: i64 = 2600822924;
    let h6: i64 = 528734635;  let h7: i64 = 1541459225;

    # 先算总长度（位），用于填充
    let bitlen: i64 = n * 8;
    # 填充后总字节：n + 1 + pad + 8 使其为 64 的倍数
    let total: i64 = n + 1 + 8;
    while (total & 63) != 0 { total = total + 1; }

    let blk: [64] byte = 0;
    let off: i64 = 0;
    while off < total {
        let i: i64 = 0;
        while i < 64 {
            if off + i < n {
                blk[i] = load8(msg + off + i);
            } else {
                if off + i == n {
                    blk[i] = 128;          # 0x80 起始的填充
                } else {
                    if off + i >= total - 8 {
                        # 末尾 8 字节放长度（大端）
                        let sh: i64 = 56 - (8 * (off + i - (total - 8)));
                        blk[i] = (bitlen / (1 << sh)) & 255;
                    } else {
                        blk[i] = 0;
                    }
                }
            }
            i = i + 1;
        }

        # 消息扩展
        let t: i64 = 0;
        while t < 16 {
            W[t] = (blk[t * 4] * 16777216) + (blk[t * 4 + 1] * 65536)
                 + (blk[t * 4 + 2] * 256) + blk[t * 4 + 3];
            t = t + 1;
        }
        while t < 64 {
            let s0: i64 = rotr32(W[t - 15], 7) ^ rotr32(W[t - 15], 18) ^ shr32(W[t - 15], 3);
            let s1: i64 = rotr32(W[t - 2], 17) ^ rotr32(W[t - 2], 19) ^ shr32(W[t - 2], 10);
            W[t] = (W[t - 16] + s0 + W[t - 7] + s1) & M32;
            t = t + 1;
        }

        let a: i64 = h0; let b: i64 = h1; let c: i64 = h2; let d: i64 = h3;
        let e: i64 = h4; let f: i64 = h5; let g: i64 = h6; let h: i64 = h7;
        t = 0;
        while t < 64 {
            let S1: i64 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
            let ch: i64 = (e & f) ^ ((M32 ^ e) & g);
            let t1: i64 = (h + S1 + ch + K256[t] + W[t]) & M32;
            let S0: i64 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
            let mj: i64 = (a & b) ^ (a & c) ^ (b & c);
            let t2: i64 = (S0 + mj) & M32;
            h = g; g = f; f = e; e = (d + t1) & M32;
            d = c; c = b; b = a; a = (t1 + t2) & M32;
            t = t + 1;
        }
        h0 = (h0 + a) & M32; h1 = (h1 + b) & M32; h2 = (h2 + c) & M32;
        h3 = (h3 + d) & M32; h4 = (h4 + e) & M32; h5 = (h5 + f) & M32;
        h6 = (h6 + g) & M32; h7 = (h7 + h) & M32;
        off = off + 64;
    }

    let hs: [8] i64 = 0;
    hs[0] = h0; hs[1] = h1; hs[2] = h2; hs[3] = h3;
    hs[4] = h4; hs[5] = h5; hs[6] = h6; hs[7] = h7;
    let i: i64 = 0;
    while i < 8 {
        let v: i64 = hs[i];
        store8(out + i * 4 + 0, shr32(v, 24) & 255);
        store8(out + i * 4 + 1, shr32(v, 16) & 255);
        store8(out + i * 4 + 2, shr32(v, 8) & 255);
        store8(out + i * 4 + 3, v & 255);
        i = i + 1;
    }
    return 32;
}

# 把 32 字节摘要写成 64 字符的十六进制串（dst 至少 65 字节）
fn hex_of(src: i64, n: i64, dst: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        let v: i64 = load8(src + i);
        let hi: i64 = shr32(v, 4) & 15;
        let lo: i64 = v & 15;
        if hi < 10 { store8(dst + i * 2, 48 + hi); } else { store8(dst + i * 2, 87 + hi); }
        if lo < 10 { store8(dst + i * 2 + 1, 48 + lo); } else { store8(dst + i * 2 + 1, 87 + lo); }
        i = i + 1;
    }
    store8(dst + n * 2, 0);
    return n * 2;
}

# sha256_hex(msg, n, dst)：一步得到十六进制串
fn sha256_hex(msg: i64, n: i64, dst: i64) -> i64 {
    let d: [32] byte = 0;
    sha256(msg, n, &d);
    return hex_of(&d, 32, dst);
}

# ---- Base64（网络与配置里几乎必用到）----

var B64: [64] byte = 0;
var b64_ready: i64 = 0;

fn b64_init() -> i64 {
    if b64_ready == 1 { return 0; }
    let t: i64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let i: i64 = 0;
    while i < 64 {
        B64[i] = load8(t + i);
        i = i + 1;
    }
    b64_ready = 1;
    return 0;
}

fn b64_val(c: i64) -> i64 {
    if c >= 65 { if c <= 90 { return c - 65; } }
    if c >= 97 { if c <= 122 { return c - 71; } }
    if c >= 48 { if c <= 57 { return c + 4; } }
    if c == 43 { return 62; }
    if c == 47 { return 63; }
    return -1;
}

# 编码：返回写入 dst 的字符数（不含结尾 0）
fn b64_enc(src: i64, n: i64, dst: i64) -> i64 {
    b64_init();
    let o: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let rem: i64 = n - i;
        let b0: i64 = load8(src + i);
        let b1: i64 = 0; let b2: i64 = 0;
        if rem > 1 { b1 = load8(src + i + 1); }
        if rem > 2 { b2 = load8(src + i + 2); }
        let v: i64 = (b0 * 65536) + (b1 * 256) + b2;
        store8(dst + o + 0, B64[shr32(v, 18) & 63]);
        store8(dst + o + 1, B64[shr32(v, 12) & 63]);
        if rem > 1 { store8(dst + o + 2, B64[shr32(v, 6) & 63]); } else { store8(dst + o + 2, 61); }
        if rem > 2 { store8(dst + o + 3, B64[v & 63]); } else { store8(dst + o + 3, 61); }
        o = o + 4;
        i = i + 3;
    }
    store8(dst + o, 0);
    return o;
}

# 解码：返回写出的字节数；非法字符返回 -1
fn b64_dec(src: i64, n: i64, dst: i64) -> i64 {
    let o: i64 = 0;
    let i: i64 = 0;
    let acc: i64 = 0;
    let nb: i64 = 0;
    while i < n {
        let c: i64 = load8(src + i);
        if c == 61 { break; }
        let v: i64 = b64_val(c);
        if v < 0 { return -1; }
        acc = acc * 64 + v;
        nb = nb + 1;
        if nb == 4 {
            store8(dst + o + 0, shr32(acc, 16) & 255);
            store8(dst + o + 1, shr32(acc, 8) & 255);
            store8(dst + o + 2, acc & 255);
            o = o + 3;
            acc = 0;
            nb = 0;
        }
        i = i + 1;
    }
    if nb == 2 {
        store8(dst + o, shr32(acc, 4) & 255);
        o = o + 1;
    } else {
        if nb == 3 {
            store8(dst + o + 0, shr32(acc, 10) & 255);
            store8(dst + o + 1, shr32(acc, 2) & 255);
            o = o + 2;
        }
    }
    return o;
}

# ---- ChaCha20 流加密 ----
# 对称、无分支、纯整数运算，非常适合在没有乘除加速的环境实现。
# 注意：这只是算法本身，不含认证（生产环境请用带 MAC 的构造）。

fn chacha_qr(st: i64, ia: i64, ib: i64, ic: i64, id: i64) -> i64 {
    let a: i64 = load64(st + ia * 8);
    let b: i64 = load64(st + ib * 8);
    let c: i64 = load64(st + ic * 8);
    let d: i64 = load64(st + id * 8);
    a = (a + b) & M32; d = rotl32(d ^ a, 16);
    c = (c + d) & M32; b = rotl32(b ^ c, 12);
    a = (a + b) & M32; d = rotl32(d ^ a, 8);
    c = (c + d) & M32; b = rotl32(b ^ c, 7);
    store64(st + ia * 8, a); store64(st + ib * 8, b);
    store64(st + ic * 8, c); store64(st + id * 8, d);
    return 0;
}

# 生成一个 64 字节密钥流块（key 32 字节，nonce 12 字节，counter 为块号）
fn chacha_block(key: i64, nonce: i64, counter: i64, out: i64) -> i64 {
    let st: [16] i64 = 0;
    st[0] = 1634760805; st[1] = 857760878; st[2] = 2036477234; st[3] = 1797285236;
    let i: i64 = 0;
    while i < 8 {
        let v: i64 = 0;
        v = load8(key + i * 4) * 16777216;
        v = v + load8(key + i * 4 + 1) * 65536;
        v = v + load8(key + i * 4 + 2) * 256;
        v = v + load8(key + i * 4 + 3);
        st[4 + i] = v & M32;
        i = i + 1;
    }
    st[12] = counter & M32;
    i = 0;
    while i < 3 {
        let v: i64 = 0;
        v = load8(nonce + i * 4) * 16777216;
        v = v + load8(nonce + i * 4 + 1) * 65536;
        v = v + load8(nonce + i * 4 + 2) * 256;
        v = v + load8(nonce + i * 4 + 3);
        st[13 + i] = v & M32;
        i = i + 1;
    }

    let x: [16] i64 = 0;
    i = 0;
    while i < 16 { x[i] = st[i]; i = i + 1; }

    let r: i64 = 0;
    while r < 10 {
        chacha_qr(&x, 0, 4, 8, 12);
        chacha_qr(&x, 1, 5, 9, 13);
        chacha_qr(&x, 2, 6, 10, 14);
        chacha_qr(&x, 3, 7, 11, 15);
        chacha_qr(&x, 0, 5, 10, 15);
        chacha_qr(&x, 1, 6, 11, 12);
        chacha_qr(&x, 2, 7, 8, 13);
        chacha_qr(&x, 3, 4, 9, 14);
        r = r + 1;
    }

    i = 0;
    while i < 16 {
        let v: i64 = (x[i] + st[i]) & M32;
        store8(out + i * 4 + 0, v & 255);
        store8(out + i * 4 + 1, shr32(v, 8) & 255);
        store8(out + i * 4 + 2, shr32(v, 16) & 255);
        store8(out + i * 4 + 3, shr32(v, 24) & 255);
        i = i + 1;
    }
    return 0;
}

# 流式加解密（同一函数，异或密钥流）
fn chacha20_crypt(key: i64, nonce: i64, buf: i64, n: i64) -> i64 {
    let ks: [64] byte = 0;
    let blk: i64 = 0;
    let off: i64 = 0;
    while off < n {
        chacha_block(key, nonce, blk, &ks);
        let i: i64 = 0;
        while i < 64 {
            if off + i >= n { return 0; }
            let v: i64 = load8(buf + off + i) ^ ks[i];
            store8(buf + off + i, v);
            i = i + 1;
        }
        off = off + 64;
        blk = blk + 1;
    }
    return 0;
}
