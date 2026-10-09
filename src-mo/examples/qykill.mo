# qykill —— 信号管理工具（墨语言实战工具 #8）
#
# 用法:
#   qykill <pid>                 默认 SIGTERM
#   qykill -s <信号名|编号> <pid>  指定信号（TERM/KILL/HUP/INT/USR1/USR2 或数字）
#   qykill -l                    列出支持的信号
#   qykill -0 <pid>              探测进程是否存在（不实际发信号）
#
# 实战压测点：kill 系统调用、errno 返回值判别（ESRCH=3 / EPERM=1）、
# 子进程 fork+exec 发信号后 waitpid 验证、信号名→编号映射表。
import "io.mo";
import "str.mo";
import "pty.mo";

# 信号名表（顺序即编号-1，从 1=SIGHUP 起）
var signames: [360] byte = 0;   # 30 * 12（语法不支持表达式维度）
var sig_n: i64 = 0;

fn sig_init() -> i64 {
    sig_n = 0;
    # 依次登记常用信号名
    let names: [180] byte = 0;   # 15 * 12
    strcpy(&names + 0, "HUP");
    strcpy(&names + 12, "INT");
    strcpy(&names + 24, "QUIT");
    strcpy(&names + 36, "ILL");
    strcpy(&names + 48, "TRAP");
    strcpy(&names + 60, "ABRT");
    strcpy(&names + 72, "BUS");
    strcpy(&names + 84, "FPE");
    strcpy(&names + 96, "KILL");
    strcpy(&names + 108, "USR1");
    strcpy(&names + 120, "SEGV");
    strcpy(&names + 132, "USR2");
    strcpy(&names + 144, "PIPE");
    strcpy(&names + 156, "ALRM");
    strcpy(&names + 168, "TERM");
    let i: i64 = 0;
    while i < 15 {
        strcpy(&signames + i * 12, &names + i * 12);
        i = i + 1;
    }
    sig_n = 15;
    return 0;
}

fn sig_by_name(name: i64) -> i64 {
    let i: i64 = 0;
    while i < sig_n {
        if streq(&signames + i * 12, name) == 1 { return i + 1; }
        i = i + 1;
    }
    return 0 - 1;
}

fn sig_name_of(num: i64, dst: i64) -> i64 {
    if num < 1 || num > sig_n {
        strcpy(dst, "?");
        return 0 - 1;
    }
    strcpy(dst, &signames + (num - 1) * 12);
    return 0;
}

fn sig_send(pid: i64, sig: i64) -> i64 {
    let r: i64 = kill(pid, sig);
    if r == 0 { return 0; }
    # errno: syscall 返回 -errno
    let e: i64 = 0 - r;
    if e == 3 {
        print("qykill: (");
        print_i64(pid);
        print(") - 没有那个进程\n");
    } else if e == 1 {
        print("qykill: (");
        print_i64(pid);
        print(") - 不允许的操作\n");
    } else {
        print("qykill: (");
        print_i64(pid);
        print(") - 错误 ");
        print_i64(e);
        print("\n");
    }
    return 1;
}

fn main() -> i64 {
    sig_init();
    if argc() < 2 {
        print("用法: qykill [-s 信号] <pid> | qykill -l | qykill -0 <pid>\n");
        return 1;
    }
    let a1: i64 = argv(1);
    # -l 列信号
    if streq(a1, "-l") == 1 {
        let i: i64 = 0;
        while i < sig_n {
            print_i64(i + 1);
            print(" SIG");
            print(&signames + i * 12);
            print("\n");
            i = i + 1;
        }
        return 0;
    }
    # -s 信号 pid
    let sig: i64 = 15;   # 默认 TERM
    let pidarg: i64 = 0;
    if streq(a1, "-s") == 1 {
        if argc() < 4 {
            print("qykill: -s 需要信号名和 pid\n");
            return 1;
        }
        let sname: i64 = argv(2);
        if numfits(sname) == 1 {
            sig = atoi(sname);
        } else {
            sig = sig_by_name(sname);
            if sig < 0 {
                print("qykill: 未知信号: ");
                print(sname);
                print("\n");
                return 1;
            }
        }
        pidarg = atoi(argv(3));
    } else if streq(a1, "-0") == 1 {
        if argc() < 3 { print("qykill: -0 需要 pid\n"); return 1; }
        pidarg = atoi(argv(2));
        let r: i64 = kill(pidarg, 0);
        if r == 0 {
            print_i64(pidarg);
            print(" 存在\n");
            return 0;
        }
        print_i64(pidarg);
        print(" 不存在或无权限\n");
        return 1;
    } else {
        if numfits(a1) != 1 {
            print("qykill: 无效 pid: ");
            print(a1);
            print("\n");
            return 1;
        }
        pidarg = atoi(a1);
    }
    return sig_send(pidarg, sig);
}

fn numfits(s: i64) -> i64 {
    if strlen(s) == 0 { return 0; }
    let i: i64 = 0;
    while i < strlen(s) {
        let c: i64 = load8(s + i);
        if c < 48 || c > 57 { return 0; }
        i = i + 1;
    }
    return 1;
}
