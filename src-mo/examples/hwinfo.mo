# hwinfo —— 硬件信息探测（用墨语言自己写的）
#
#   ./hwinfo
#
# 墨语言不链接任何 libc，所以读硬件信息全部走两条路：
#   1. 内核导出的 sysfs / procfs（/proc、/sys）—— 普通权限就能读
#   2. 直接系统调用（uname、sysinfo、statfs）
#
# 真正「碰硬件」（/dev/mem、ioperm、iopl）需要 root，
# 这一部分写成 hw_mem 并在权限不足时明确提示，而不是假装成功。
import "io.mo";
import "str.mo";
import "fs.mo";
import "dir.mo";

var b: [8192] byte = 0;
var key: [64] byte = 0;
var u: [128] byte = 0;

# 在 "key: value\n" 形式的文本里找 key，取冒号后的值（去掉前导空格与换行）
fn field(buf: i64, n: i64, k: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        let j: i64 = 0;
        while load8(k + j) != 0 {
            if load8(buf + i + j) != load8(k + j) { break; }
            j = j + 1;
        }
        if load8(k + j) == 0 {
            let p: i64 = i + j;
            # /proc/cpuinfo 用 tab 分隔（"model name\t: xxx"），要先跳过空白再找冒号
            while load8(buf + p) == 32 || load8(buf + p) == 9 { p = p + 1; }
            if load8(buf + p) == 58 {
                p = p + 1;
                while load8(buf + p) == 32 { p = p + 1; }
                let s: i64 = p;
                while load8(buf + p) != 10 {
                    if load8(buf + p) == 0 { break; }
                    p = p + 1;
                }
                memcpy(&key, buf + s, p - s);
                store8(&key + (p - s), 0);
                return 1;
            }
        }
        # 跳到下一行
        while i < n {
            if load8(buf + i) == 10 { i = i + 1; break; }
            i = i + 1;
        }
    }
    return 0;
}

fn show(label: i64, v: i64) -> i64 {
    print("  ");
    print(label);
    print(": ");
    print(v);
    print_nl();
    return 0;
}

fn read_or_dash(path: i64) -> i64 {
    let n: i64 = read_file(path, &b, 8191);
    if n < 0 {
        print("  (不可用: ");
        print(path);
        print(")\n");
        return 0;
    }
    store8(&b + n, 0);
    # 去掉换行
    let i: i64 = 0;
    while load8(&b + i) != 0 {
        if load8(&b + i) == 10 { store8(&b + i, 0); }
        i = i + 1;
    }
    print("  ");
    print(&b);
    print_nl();
    return 0;
}

fn sec(t: i64) -> i64 {
    print("[");
    print(t);
    print("]\n");
    return 0;
}

fn main() -> i64 {
    sec("内核");
    uname_sysname(&u);  show("sysname", &u);
    uname_release(&u);  show("release", &u);
    uname_machine(&u);  show("machine", &u);
    print("  uptime: "); print_i64(uptime_secs()); print(" s\n");

    sec("CPU");
    let n: i64 = read_file("/proc/cpuinfo", &b, 8191);
    if n < 0 {
        print("  (读不到 /proc/cpuinfo)\n");
    } else {
        print("  (cpuinfo "); print_i64(n); print(" bytes)\n");
        store8(&b + n, 0);
        if field(&b, n, "model name") == 1 { show("model", &key); }
        if field(&b, n, "cpu MHz") == 1 { show("MHz", &key); }
        if field(&b, n, "cpu cores") == 1 { show("cores", &key); }
        if field(&b, n, "vendor_id") == 1 { show("vendor", &key); }
    }

    sec("内存");
    print("  total: "); print_i64(mem_total()); print(" bytes\n");
    n = read_file("/proc/meminfo", &b, 8191);
    if n > 0 {
        store8(&b + n, 0);
        if field(&b, n, "MemAvailable") == 1 { show("available", &key); }
        if field(&b, n, "SwapTotal") == 1 { show("swap", &key); }
    }

    sec("温度 / 电源（sysfs，需要驱动导出）");
    read_or_dash("/sys/class/thermal/thermal_zone0/temp");
    read_or_dash("/sys/class/power_supply/BAT0/capacity");

    sec("块设备与文件系统");
    read_or_dash("/proc/partitions");
    # statfs(137)：把根目录的容量信息取出来
    let sb: [120] byte = 0;
    let r: i64 = syscall(137, "/", &sb, 0, 0, 0, 0);
    if r == 0 {
        # x86-64 statfs：f_bsize=+8, f_blocks=+16, f_bfree=+24
        let bs: i64 = rd64le(&sb, 8);
        let blocks: i64 = rd64le(&sb, 16);
        let bfree: i64 = rd64le(&sb, 24);
        print("  / 容量: ");
        print_i64(blocks * bs / 1048576);
        print(" MB，可用 ");
        print_i64(bfree * bs / 1048576);
        print(" MB\n");
    } else {
        print("  (statfs 失败)\n");
    }

    sec("PCI 设备（sysfs）");
    if dir_open("/sys/class/net") == 0 {
        let nm: [256] byte = 0;
        let c: i64 = 0;
        while dir_next(&nm, 0) == 1 {
            print("  net: ");
            print(&nm);
            print_nl();
            c = c + 1;
            if c > 8 { print("  ...\n"); break; }
        }
        dir_close();
    } else {
        print("  (打不开 /sys/class/net)\n");
    }

    sec("直接访问物理内存 /dev/mem");
    let fd: i64 = fopen("/dev/mem", 0, 0);
    if fd < 0 {
        # 绝大多数系统会禁止（或压根没这个设备），明确说明而不是跳过
        print("  打不开 /dev/mem —— 需要 root 且内核开启 CONFIG_STRICT_DEVMEM=n\n");
        print("  这说明：墨语言能做底层访问，但是否成功由系统权限决定\n");
    } else {
        print("  已打开 /dev/mem（root 环境）。示例到此为止，不实读：\n");
        print("  乱读物理地址可能让机器崩溃，这一步留给明确知道自己在做什么的人\n");
        fclose(fd);
    }
    return 0;
}

# 读 8 字节小端整数（sysfs / statfs 这些结构体都是小端）
fn rd64le(p: i64, off: i64) -> i64 {
    let v: i64 = 0;
    let i: i64 = 7;
    while i >= 0 {
        v = v * 256 + load8(p + off + i);
        i = i - 1;
    }
    return v;
}
