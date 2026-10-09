# qyhash —— 文件校验和工具（墨语言实战工具 #6）
#
# 用法:
#   qyhash <文件>              输出 SHA-256 与 CRC32
#   qyhash -c <清单文件>       校验模式：清单每行 "<hex>  <路径>"，全部一致 exit=0
#   qyhash -g <目录>           生成模式：目录下每个文件一行写 stdout（可重定向做清单）
#
# 实战压测点：大文件分块读取、sha256/crc32 标准库调用、
# 清单文本解析（hex 比较的逐字节实现）、多模式参数分发。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";
import "crypto.mo";

var fbuf: [65536] byte = 0;
var digest: [32] byte = 0;
var hex: [65] byte = 0;
var linebuf: [1024] byte = 0;
var mbuf: [65536] byte = 0;   # 清单专用缓冲（hash_file 会覆盖 fbuf）
var hex_in: [65] byte = 0;
var filepath: [512] byte = 0;
var dir_names: [64000] byte = 0;
var dir_types: [250] byte = 0;
var subpath: [1024] byte = 0;
var crc_hex: [12] byte = 0;

var err_count: i64 = 0;
var ok_count: i64 = 0;

fn fputs_err(s: i64) -> i64 {
    return syscall(1, 2, s, strlen(s), 0, 0, 0);
}

# CRC32 十六进制（8 位）
fn crc_hex_of(buf: i64, n: i64) -> i64 {
    let c: i64 = crc32(buf, n);
    store8(&crc_hex + 0, 48); store8(&crc_hex + 1, 120);   # "0x"
    let i: i64 = 0;
    while i < 8 {
        let nib: i64 = (c >> ((7 - i) * 4)) & 15;
        if nib < 10 { store8(&crc_hex + 2 + i, 48 + nib); }
        else { store8(&crc_hex + 2 + i, 87 + nib); }
        i = i + 1;
    }
    store8(&crc_hex + 10, 0);   # "0x"+8hex=10 字符，需要 11 字节缓冲
    return 0;
}

# 对单个文件：流式分块摘要（任意大小），输出 hex 与 crc
fn hash_file(path: i64) -> i64 {
    let sz: i64 = stat_size(path);
    if sz < 0 {
        fputs_err("qyhash: 打不开: ");
        fputs_err(path);
        fputs_err("\n");
        return 0 - 1;
    }
    let fd: i64 = fopen(path, 0, 0);
    if fd < 0 { return 0 - 1; }
    sha256_file(fd, &hex);
    fclose(fd);
    return sz;
}

fn print_hash_line(path: i64) -> i64 {
    let n: i64 = hash_file(path);
    if n < 0 { return 0 - 1; }
    print(&hex);
    print("  ");
    print(path);
    print("\n");
    return n;
}

# 十六进制串相等比较（长度同 64）
fn hex_equal(a: i64, b: i64) -> i64 {
    let i: i64 = 0;
    while i < 64 {
        let x: i64 = load8(a + i);
        let y: i64 = load8(b + i);
        # 统一转小写
        if x >= 65 && x <= 90 { x = x + 32; }
        if y >= 65 && y <= 90 { y = y + 32; }
        if x != y { return 0; }
        i = i + 1;
    }
    return 1;
}

# 生成模式：目录下普通文件逐行输出
fn gen_dir(path: i64, depth: i64) -> i64 {
    if depth > 6 { return 0; }
    let n: i64 = dir_list(path, &dir_names, &dir_types, 256, 249);
    if n < 0 { return 0; }
    let i: i64 = 0;
    while i < n {
        let nm: i64 = &dir_names + i * 256;
        if streq(nm, ".") != 1 && streq(nm, "..") != 1 {
            strcpy(&subpath, path);
            strcat(&subpath, "/");
            strcat(&subpath, nm);
            if load8(&dir_types + i) == 4 {
                gen_dir(&subpath, depth + 1);
            } else {
                print_hash_line(&subpath);
            }
        }
        i = i + 1;
    }
    return 0;
}

# 校验模式：清单每行 "<64hex>  <路径>"
fn check_manifest(mpath: i64) -> i64 {
    let sz: i64 = read_file(mpath, &mbuf, 65000);
    if sz < 0 {
        fputs_err("qyhash: 清单打不开\n");
        return 1;
    }
    store8(&mbuf + sz, 0);
    let i: i64 = 0;
    while i < sz {
        # 取一行
        let l: i64 = 0;
        while i < sz && load8(&mbuf + i) != 10 {
            store8(&linebuf + l, load8(&mbuf + i));
            l = l + 1;
            i = i + 1;
        }
        store8(&linebuf + l, 0);
        if l > 66 {
            # 前 64 是 hex，后面 "  路径"
            memcpy(&hex_in, &linebuf, 64);
            store8(&hex_in + 64, 0);
            let p: i64 = &linebuf + 64;
            while load8(p) == 32 { p = p + 1; }
            let r: i64 = hash_file(p);
            if r < 0 {
                err_count = err_count + 1;
                print("FAILED(打开) ");
                print(p);
                print("\n");
            } else if hex_equal(&hex_in, &hex) == 1 {
                ok_count = ok_count + 1;
                print("OK ");
                print(p);
                print("\n");
            } else {
                err_count = err_count + 1;
                print("FAILED ");
                print(p);
                print("\n");
            }
        }
        i = i + 1;
    }
    print_i64(ok_count);
    print(" OK / ");
    print_i64(err_count);
    print(" FAILED\n");
    if err_count > 0 { return 1; }
    return 0;
}

fn main() -> i64 {
    if argc() < 2 {
        print("用法:\n");
        print("  qyhash <文件>        单文件哈希\n");
        print("  qyhash -g <目录>     生成清单（重定向保存）\n");
        print("  qyhash -c <清单>     校验清单\n");
        return 1;
    }
    let mode: i64 = argv(1);
    let target: i64 = argv(2);
    if streq(mode, "-g") == 1 {
        let st: i64 = stat_mode(target);
        if st >= 0 && (st & 61440) == 16384 {
            gen_dir(target, 0);
            return 0;
        }
        print_hash_line(target);
        return 0;
    }
    if streq(mode, "-c") == 1 {
        return check_manifest(target);
    }
    # 单文件模式
    if print_hash_line(mode) < 0 { return 1; }
    return 0;
}
