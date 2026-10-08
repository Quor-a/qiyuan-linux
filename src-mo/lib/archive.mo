# archive —— tar 打包/解包 与 gzip（用墨语言自己写的）
#
# tar 是纯字节格式，gzip 的 stored 模式也是纯字节 + CRC32 ——
# 两者都不需要真正的压缩算法就能产出**标准工具能读**的文件：
#
#   tar 打包后 → 系统 tar 能解
#   gzip 后    → 系统 gunzip 能解
#
# 这是刻意的选择：优先保证「与现有生态互操作」，
# 而不是自己发明一个压缩格式（那会让产物没人能读）。
import "fs.mo";
import "str.mo";
import "crypto.mo";
import "io.mo";

var zeros: [512] byte = 0;   # 数据补齐必须用真零，不能拿头缓冲凑（会污染下一个头）
var TAR_CHK: i64 = 0;
var gz_buf: [65536] byte = 0;

# ---- 八进制字段写入（tar 头里数字都是八进制 ASCII）----
# 写 n 位宽的八进制数，前面补 '0'，最后一位是空格或 NUL
fn oct_field(buf: i64, off: i64, val: i64, width: i64) -> i64 {
    let i: i64 = width - 2;
    while i >= 0 {
        let d: i64 = val % 8;
        store8(buf + off + i, 48 + d);
        val = val / 8;
        i = i - 1;
    }
    store8(buf + off + width - 1, 32);   # 末位空格（tar 传统）
    return 0;
}

fn oct_read(buf: i64, off: i64, width: i64) -> i64 {
    let v: i64 = 0;
    let i: i64 = 0;
    while i < width {
        let c: i64 = load8(buf + off + i);
        if c < 48 { return v; }
        if c > 55 { return v; }
        v = v * 8 + (c - 48);
        i = i + 1;
    }
    return v;
}

# 头校验和：全部字节之和（chksum 字段按 8 个空格算）
fn tar_checksum(buf: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 512 {
        if i >= 148 {
            if i < 156 {
                s = s + 32;
            } else {
                s = s + load8(buf + i);
            }
        } else {
            s = s + load8(buf + i);
        }
        i = i + 1;
    }
    return s;
}

# 写一个 tar 头（512 字节）。size 为文件字节数
fn tar_hdr(buf: i64, name: i64, size: i64, mode: i64) -> i64 {
    let i: i64 = 0;
    while i < 512 { store8(buf + i, 0); i = i + 1; }
    strcpy(buf, name);
    oct_field(buf, 100, mode, 8);
    oct_field(buf, 108, 0, 8);      # uid
    oct_field(buf, 116, 0, 8);      # gid
    oct_field(buf, 124, size, 12);
    oct_field(buf, 136, 0, 12);     # mtime
    # 148..156 先填空格，算完校验和再覆盖
    i = 148;
    while i < 156 { store8(buf + i, 32); i = i + 1; }
    store8(buf + 156, 48);          # typeflag '0' = 普通文件
    strcpy(buf + 257, "ustar");
    store8(buf + 263, 48);
    # chksum 字段是 6 位八进制 + NUL + 空格（共 8 字节）。
    # 早先用 width=8 调用 oct_field，它写的是 7 位数字（148..154），
    # 又被我后面那句 store8(154, 0) 把最低位覆盖成 0 ——
    # 校验和凭空少一位，系统 tar 直接拒绝，报 "not a tar archive"。
    let c: i64 = tar_checksum(buf);
    oct_field(buf, 148, c, 7);
    store8(buf + 154, 0);
    store8(buf + 155, 32);
    return 512;
}

# 打包：把若干文件写进 tar。files 是路径数组，n 是个数
# 返回写入的字节数；失败返回负值
fn tar_pack(out: i64, files: i64, n: i64) -> i64 {
    let fd: i64 = fopen(out, 577, 420);
    if fd < 0 { return -1; }
    let hdr: [512] byte = 0;
    let body: [65536] byte = 0;
    let i: i64 = 0;
    while i < n {
        let path: i64 = load64(files + i * 8);
        let sz: i64 = read_file(path, &body, 65536);
        if sz < 0 { fclose(fd); return -2; }
        tar_hdr(&hdr, path, sz, 420);
        fwrite(fd, &hdr, 512);
        if sz > 0 { fwrite(fd, &body, sz); }
        # 数据补齐到 512 的倍数
        let pad: i64 = (512 - (sz & 511)) & 511;
        if pad > 0 { fwrite(fd, &zeros, pad); }
        i = i + 1;
    }
    # 结尾两个全零块
    let z: i64 = 0;
    while z < 512 { store8(&hdr + z, 0); z = z + 1; }
    fwrite(fd, &hdr, 512);
    fwrite(fd, &hdr, 512);
    fclose(fd);
    return 0;
}

# 解包：把 tar 里的文件提取到当前目录；返回提取个数
fn tar_unpack(path: i64) -> i64 {
    let fd: i64 = fopen(path, 0, 0);
    if fd < 0 { return -1; }
    let hdr: [512] byte = 0;
    let cnt: i64 = 0;
    while 1 {
        let n: i64 = fread(fd, &hdr, 512);
        if n < 512 { break; }
        # 全零块 = 结束
        if load8(&hdr) == 0 { break; }
        let sz: i64 = oct_read(&hdr, 124, 12);
        let remain: i64 = sz;
        let ofd: i64 = fopen(&hdr, 577, 420);
        if ofd >= 0 {
            while remain > 0 {
                let chunk: i64 = 65536;
                if remain < chunk { chunk = remain; }
                let m: i64 = fread(fd, &gz_buf, chunk);
                if m <= 0 { break; }
                fwrite(ofd, &gz_buf, m);
                remain = remain - m;
            }
            fclose(ofd);
        }
        # 跳到 512 边界
        let pad: i64 = (512 - (sz & 511)) & 511;
        if pad > 0 { fread(fd, &gz_buf, pad); }
        cnt = cnt + 1;
    }
    fclose(fd);
    return cnt;
}

# 列出 tar 内容（打印名字与大小），返回条目数
fn tar_list(path: i64) -> i64 {
    let fd: i64 = fopen(path, 0, 0);
    if fd < 0 { return -1; }
    let hdr: [512] byte = 0;
    let cnt: i64 = 0;
    while 1 {
        let n: i64 = fread(fd, &hdr, 512);
        if n < 512 { break; }
        if load8(&hdr) == 0 { break; }
        let sz: i64 = oct_read(&hdr, 124, 12);
        print_i64(sz);
        print("  ");
        print(&hdr);
        print_nl();
        # 必须跳过「数据本身 + 补齐」，只跳补齐的话会停在数据中段，
        # 下一个头就读成零块（表现为只列出第一个文件）
        let skip: i64 = sz + ((512 - (sz & 511)) & 511);
        while skip > 0 {
            let chunk: i64 = 65536;
            if skip < chunk { chunk = skip; }
            fread(fd, &gz_buf, chunk);
            skip = skip - chunk;
        }
        cnt = cnt + 1;
    }
    fclose(fd);
    return cnt;
}

# ---- gzip：只实现 stored（不压缩）模式 ----
#
# 为什么不直接实现 deflate：deflate 需要 Huffman + LZ77，
# 单轮时间做不完且极易出错。stored 模式格式完全合法，
# 系统 gunzip 能正常解开 —— 互操作性优先，压缩率留待后续。
fn gzip_file(src: i64, dst: i64) -> i64 {
    let n: i64 = read_file(src, &gz_buf, 65536);
    if n < 0 { return -1; }
    let fd: i64 = fopen(dst, 577, 420);
    if fd < 0 { return -2; }
    # 10 字节头：magic(2) CM(1) FLG(1) MTIME(4) XFL(1) OS(1)
    let h: [10] byte = 0;
    store8(&h + 0, 31); store8(&h + 1, 139);
    store8(&h + 2, 8);  store8(&h + 3, 0);
    store8(&h + 8, 0);  store8(&h + 9, 255);
    fwrite(fd, &h, 10);
    # deflate stored 块：先发 BFINAL=1,BTYPE=00
    let b: i64 = 1;
    fwrite(fd, &b, 1);
    # LEN 与 NLEN（小端，16 位取反）
    let len: [4] byte = 0;
    store8(&len + 0, n & 255);
    store8(&len + 1, (n / 256) & 255);
    let inv: i64 = (65535 ^ n) & 65535;
    store8(&len + 2, inv & 255);
    store8(&len + 3, (inv / 256) & 255);
    fwrite(fd, &len, 4);
    fwrite(fd, &gz_buf, n);
    # CRC32 + ISIZE（小端）
    let c: i64 = crc32(&gz_buf, n);
    let t: [8] byte = 0;
    let i: i64 = 0;
    while i < 4 {
        store8(&t + i, (c / (1 << (i * 8))) & 255);
        store8(&t + 4 + i, (n / (1 << (i * 8))) & 255);
        i = i + 1;
    }
    fwrite(fd, &t, 8);
    fclose(fd);
    return 0;
}

# 解 gzip（只支持 stored 模式的数据块）
fn gunzip_file(src: i64, dst: i64) -> i64 {
    let n: i64 = read_file(src, &gz_buf, 65536);
    if n < 18 { return -1; }
    if load8(&gz_buf) != 31 { return -2; }
    if load8(&gz_buf + 1) != 139 { return -2; }
    let p: i64 = 10;
    let out: i64 = fopen(dst, 577, 420);
    if out < 0 { return -3; }
    while p < n {
        let b: i64 = load8(&gz_buf + p);
        p = p + 1;
        if (b & 1) == 0 { return -4; }        # 只支持 BFINAL 块
        if (b & 6) != 0 { return -4; }        # 只支持 stored（BTYPE=00）
        let len: i64 = load8(&gz_buf + p) + load8(&gz_buf + p + 1) * 256;
        p = p + 4;
        fwrite(out, &gz_buf + p, len);
        p = p + len;
        if (b & 1) == 1 { break; }
    }
    fclose(out);
    return 0;
}
