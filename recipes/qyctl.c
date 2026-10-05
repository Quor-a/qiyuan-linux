/* qyctl —— 启元 Linux 服务管理 CLI
 *
 * 设计原则（与 qyinit 同一哲学：小而可审计）：
 *   - 不依赖 dbus / polkit / systemd，一个静态逻辑的 C 文件
 *   - 与 qyinit 的契约：qyinit 启动服务时写 /run/qyinit/units/<name>.pid
 *     （qyinit 补丁同步落地）；旧版 qyinit 没有该文件时退化为读单元文件
 *     直接拉起 ExecStart（start 子命令），stop 用 pidfile 或 pgrep 兜底。
 *
 * 用法：
 *   qyctl list                 列出全部单元与状态
 *   qyctl status <unit>        单个单元详情
 *   qyctl start <unit>         启动（有 pidfile 且进程活着则跳过）
 *   qyctl stop <unit>          停止（SIGTERM → 5s → SIGKILL）
 *   qyctl restart <unit>       stop + start
 *   qyctl enable <unit>        确保 /etc/qyinit.d/<unit>.unit 存在
 *   qyctl disable <unit>       移走单元文件到 /etc/qyinit.d/disabled/
 */
#define _GNU_SOURCE
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <limits.h>

#define UNIT_DIR     "/etc/qyinit.d"
#define DISABLED_DIR UNIT_DIR "/disabled"
#define PID_DIR      "/run/qyinit/units"
#ifndef LINE_MAX
#define LINE_MAX 1024
#endif

static int unit_alive(const char *unit)
{
    char path[PATH_MAX];
    snprintf(path, sizeof path, PID_DIR "/%s.pid", unit);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    int pid = 0;
    if (fscanf(f, "%d", &pid) != 1) { fclose(f); return 0; }
    fclose(f);
    if (pid <= 1) return 0;
    char pl[64];
    snprintf(pl, sizeof pl, "/proc/%d", pid);
    return access(pl, F_OK) == 0;
}

static int pid_of(const char *unit)
{
    char path[PATH_MAX];
    snprintf(path, sizeof path, PID_DIR "/%s.pid", unit);
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    int pid = -1;
    if (fscanf(f, "%d", &pid) != 1) pid = -1;
    fclose(f);
    return pid;
}

/* 解析单元文件，取 Description / ExecStart / Restart */
static void unit_fields(const char *unit, char *desc, size_t dsz,
                        char *exec, size_t esz, char *restart, size_t rsz)
{
    desc[0] = exec[0] = restart[0] = '\0';
    char path[PATH_MAX];
    snprintf(path, sizeof path, UNIT_DIR "/%s.unit", unit);
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[LINE_MAX];
    while (fgets(line, sizeof line, f)) {
        char *nl = strchr(line, '\n'); if (nl) *nl = '\0';
        char *eq = strchr(line, '=');
        if (!eq || line[0] == '#' || line[0] == '[') continue;
        *eq = '\0';
        const char *key = line, *val = eq + 1;
        if (strcmp(key, "Description") == 0) snprintf(desc, dsz, "%s", val);
        else if (strcmp(key, "ExecStart") == 0) snprintf(exec, esz, "%s", val);
        else if (strcmp(key, "Restart") == 0) snprintf(restart, rsz, "%s", val);
    }
    fclose(f);
}

static int unit_exists(const char *unit)
{
    char path[PATH_MAX];
    snprintf(path, sizeof path, UNIT_DIR "/%s.unit", unit);
    return access(path, F_OK) == 0;
}

static int cmp_str(const void *a, const void *b)
{
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

static int cmd_list(void)
{
    DIR *d = opendir(UNIT_DIR);
    if (!d) { fprintf(stderr, "qyctl: 无法打开 %s: %s\n", UNIT_DIR, strerror(errno)); return 1; }
    const char *names[256]; int n = 0;
    struct dirent *e;
    while ((e = readdir(d)) && n < 256) {
        size_t len = strlen(e->d_name);
        if (len > 5 && strcmp(e->d_name + len - 5, ".unit") == 0)
            names[n++] = strndup(e->d_name, len - 5);
    }
    closedir(d);
    qsort(names, n, sizeof names[0], cmp_str);
    printf("%-16s %-8s %s\n", "UNIT", "STATE", "DESCRIPTION");
    for (int i = 0; i < n; i++) {
        char desc[128], exec[512], restart[32];
        unit_fields(names[i], desc, sizeof desc, exec, sizeof exec, restart, sizeof restart);
        const char *st = unit_alive(names[i]) ? "running" : "inactive";
        printf("%-16s %-8s %s\n", names[i], st, desc);
    }
    return 0;
}

static int cmd_status(const char *unit)
{
    if (!unit_exists(unit)) { fprintf(stderr, "qyctl: 单元不存在: %s\n", unit); return 1; }
    char desc[128], exec[512], restart[32];
    unit_fields(unit, desc, sizeof desc, exec, sizeof exec, restart, sizeof restart);
    int pid = pid_of(unit);
    printf("单元: %s\n", unit);
    printf("  描述: %s\n", desc[0] ? desc : "(无)");
    printf("  启动: %s\n", exec[0] ? exec : "(无)");
    printf("  重启策略: %s\n", restart[0] ? restart : "no");
    if (pid > 0 && unit_alive(unit)) printf("  状态: running (pid %d)\n", pid);
    else printf("  状态: inactive\n");
    return 0;
}

static int spawn_exec(const char *exec)
{
    /* /bin/sh -c "exec" 后台化，输出丢 /dev/null，写 pidfile 由 shell 子进程承担 */
    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return 1; }
    if (pid == 0) {
        setsid();
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) { dup2(devnull, 0); dup2(devnull, 1); dup2(devnull, 2); }
        execl("/bin/sh", "sh", "-c", exec, (char *)NULL);
        _exit(127);
    }
    return (int)pid;
}

static int cmd_start(const char *unit)
{
    if (!unit_exists(unit)) { fprintf(stderr, "qyctl: 单元不存在: %s\n", unit); return 1; }
    if (unit_alive(unit)) { printf("%s: 已在运行 (pid %d)\n", unit, pid_of(unit)); return 0; }
    char exec[512];
    char desc[128], restart[32];
    unit_fields(unit, desc, sizeof desc, exec, sizeof exec, restart, sizeof restart);
    if (!exec[0]) { fprintf(stderr, "qyctl: %s.unit 缺 ExecStart\n", unit); return 1; }
    int pid = spawn_exec(exec);
    /* 尽力写 pidfile（真 pid 是 sh 的子进程；init 托管的会由 qyinit 覆盖） */
    char path[PATH_MAX];
    snprintf(path, sizeof path, PID_DIR "/%s.pid", unit);
    FILE *f = fopen(path, "w");
    if (f) { fprintf(f, "%d\n", pid); fclose(f); }
    printf("%s: 已启动 (pid %d)\n", unit, pid);
    return 0;
}

static int cmd_stop(const char *unit)
{
    int pid = pid_of(unit);
    if (pid <= 1 || !unit_alive(unit)) {
        /* pidfile 兜底失败：尝试按可执行名 pgrep（/proc 扫描，无 procps 依赖） */
        char exec[512], desc[128], restart[32];
        unit_fields(unit, desc, sizeof desc, exec, sizeof exec, restart, sizeof restart);
        if (exec[0]) {
            char base[256];
            const char *sp = strchr(exec, ' ');
            size_t bl = sp ? (size_t)(sp - exec) : strlen(exec);
            if (bl >= sizeof base) bl = sizeof base - 1;
            memcpy(base, exec, bl); base[bl] = '\0';
            const char *bn = strrchr(base, '/'); bn = bn ? bn + 1 : base;
            DIR *d = opendir("/proc");
            struct dirent *e; int found = 0;
            while (d && (e = readdir(d))) {
                if (!isdigit((unsigned char)e->d_name[0])) continue;
                char cl[256]; snprintf(cl, sizeof cl, "/proc/%s/comm", e->d_name);
                FILE *f = fopen(cl, "r");
                if (!f) continue;
                char comm[64]; int got = fscanf(f, "%63s", comm) == 1;
                fclose(f);
                if (got && strcmp(comm, bn) == 0) {
                    pid = atoi(e->d_name);
                    if (pid > 1) {
                        kill(pid, SIGTERM); found = 1;
                        printf("%s: SIGTERM -> pid %d\n", unit, pid);
                    }
                }
            }
            if (d) closedir(d);
            if (!found) { printf("%s: 未在运行\n", unit); return 0; }
        } else { printf("%s: 未在运行\n", unit); return 0; }
    } else {
        kill(pid, SIGTERM);
        printf("%s: SIGTERM -> pid %d\n", unit, pid);
    }
    /* 等 5 秒，还活着就 SIGKILL */
    for (int i = 0; i < 50; i++) {
        if (kill(pid, 0) != 0) break;
        usleep(100000);
    }
    if (kill(pid, 0) == 0) { kill(pid, SIGKILL); printf("%s: SIGKILL\n", unit); }
    char path[PATH_MAX];
    snprintf(path, sizeof path, PID_DIR "/%s.pid", unit);
    unlink(path);
    return 0;
}

static int cmd_enable(const char *unit)
{
    char path[PATH_MAX], from[PATH_MAX];
    snprintf(path, sizeof path, UNIT_DIR "/%s.unit", unit);
    snprintf(from, sizeof from, DISABLED_DIR "/%s.unit", unit);
    if (access(path, F_OK) == 0) { printf("%s: 已启用\n", unit); return 0; }
    if (access(from, F_OK) == 0) {
        if (rename(from, path) != 0) { perror("rename"); return 1; }
        printf("%s: 已启用（从 disabled 恢复）\n", unit);
    } else { fprintf(stderr, "qyctl: 找不到 %s 或 %s\n", path, from); return 1; }
    return 0;
}

static int cmd_disable(const char *unit)
{
    char path[PATH_MAX], to[PATH_MAX];
    snprintf(path, sizeof path, UNIT_DIR "/%s.unit", unit);
    if (access(path, F_OK) != 0) { printf("%s: 本来就未启用\n", unit); return 0; }
    mkdir(DISABLED_DIR, 0755);
    snprintf(to, sizeof to, DISABLED_DIR "/%s.unit", unit);
    if (rename(path, to) != 0) { perror("rename"); return 1; }
    /* 正在跑的先停 */
    if (unit_alive(unit)) cmd_stop(unit);
    printf("%s: 已禁用\n", unit);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr,
            "用法: qyctl <list|status|start|stop|restart|enable|disable> [单元]\n"
            "  启元 Linux 服务管理（无 dbus / polkit 依赖）\n");
        return 2;
    }
    const char *cmd = argv[1];
    if (strcmp(cmd, "list") == 0) return cmd_list();
    if (argc < 3) { fprintf(stderr, "qyctl: %s 需要单元名\n", cmd); return 2; }
    const char *unit = argv[2];
    if (strcmp(cmd, "status") == 0) return cmd_status(unit);
    if (strcmp(cmd, "start") == 0) return cmd_start(unit);
    if (strcmp(cmd, "stop") == 0) return cmd_stop(unit);
    if (strcmp(cmd, "restart") == 0) {
        int r = cmd_stop(unit);
        if (r) return r;
        sleep(1);
        return cmd_start(unit);
    }
    if (strcmp(cmd, "enable") == 0) return cmd_enable(unit);
    if (strcmp(cmd, "disable") == 0) return cmd_disable(unit);
    fprintf(stderr, "qyctl: 未知命令: %s\n", cmd);
    return 2;
}
