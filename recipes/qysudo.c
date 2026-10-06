/* qysudo - 启元权限提升工具 (setuid root)
 * 用法: qysudo <命令> [参数...]
 *       qysudo -n <命令> ...   免交互（不提示密码，仅供 NOPASSWD 白名单命中时）
 * 校验链: /etc/qysudoers（用户或 %组 授权）→ /etc/shadow 密码校验 → 以 root 执行
 * qysudoers 语法（一行一条，# 注释）:
 *   <user>|%<group> ALL=(ALL)            —— 需输密码执行任意命令
 *   <user>|%<group> ALL=(NOPASSWD) /cmd1,/cmd2  —— 白名单命令免密
 * 依赖: libcrypt (crypt_r, SHA512 $6$)
 * 安全: 不接受环境变量 PATH 提权注入 —— 执行时重置为 /usr/bin:/bin:/usr/sbin:/sbin
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <pwd.h>
#include <grp.h>
#include <termios.h>
#include <shadow.h>
#include <crypt.h>
#include <time.h>

#define PATH_SAFE "/usr/bin:/bin:/usr/sbin:/sbin"
#ifndef QYSUDOERS_PATH
#define QYSUDOERS_PATH "/etc/qysudoers"
#endif

/* 读一行（无回显）密码 */
static void read_password(const char *prompt, char *buf, size_t n)
{
    struct termios old, noecho;
    printf("%s", prompt);
    fflush(stdout);
    tcgetattr(0, &old);
    noecho = old;
    noecho.c_lflag &= ~ECHO;
    tcsetattr(0, TCSANOW, &noecho);
    if (!fgets(buf, (int)n, stdin)) buf[0] = 0;
    tcsetattr(0, TCSANOW, &old);
    printf("\n");
    buf[strcspn(buf, "\n")] = 0;
}

/* 校验 shadow 行密码字段; 返回 0=OK */
static int verify_password(const char *hash, const char *input)
{
    if (!hash || hash[0] == '!' || hash[0] == '*') return -1;   /* 锁定 */
    if (hash[0] == 0) return 0;                                  /* 空密码 */
    struct crypt_data cd;
    memset(&cd, 0, sizeof cd);
    char *r = crypt_r(input, hash, &cd);
    if (!r) return -1;
    return strcmp(r, hash) == 0 ? 0 : -1;
}

/* 用户是否在组里（按组名） */
static int in_group(const char *user, const char *group)
{
    struct group *gr = getgrnam(group);
    if (!gr) return 0;
    if (gr->gr_mem) {
        for (char **m = gr->gr_mem; *m; m++)
            if (strcmp(*m, user) == 0) return 1;
    }
    /* 主组同名也算 */
    struct passwd *pw = getpwnam(user);
    if (pw && gr->gr_gid == pw->pw_gid) return 1;
    return 0;
}

/* 本行主体（用户或组）是否匹配当前用户 */
static int who_matches(const char *who, int is_group, const char *user)
{
    if (is_group) return in_group(user, who) == 1;
    return strcmp(user, who) == 0;
}

/* 白名单命令匹配: list 为逗号分隔的绝对路径命令; 返回 1=命令在白名单 */
static int cmd_in_list(const char *list, const char *cmd)
{
    char buf[1024];
    if (!list || !cmd || cmd[0] != '/') return 0;
    if (strstr(cmd, "..")) return 0;
    strncpy(buf, list, sizeof buf - 1);
    buf[sizeof buf - 1] = 0;
    char *save = NULL;
    for (char *tok = strtok_r(buf, ",", &save); tok; tok = strtok_r(NULL, ",", &save)) {
        while (*tok == ' ' || *tok == '\t') tok++;
        char *e = tok + strlen(tok);
        while (e > tok && (e[-1] == ' ' || e[-1] == '\t')) *--e = 0;
        if (*tok == 0) continue;
        struct stat st;
        if (stat(tok, &st) != 0 || !S_ISREG(st.st_mode)) continue;
        if (strcmp(tok, cmd) == 0) return 1;
    }
    return 0;
}

/* qysudoers 校验。
 * 返回: 0=授权需密码  1=授权免密(NOPASSWD 且命令命中白名单或无白名单)
 *      -1=拒绝 */
static int authorized(const char *user, const char *cmd)
{
    FILE *f = fopen(QYSUDOERS_PATH, "r");
    if (!f) return -1;                       /* 无配置 = 全部拒绝 */
    char line[1024];
    int ok = -1;
    while (fgets(line, sizeof line, f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#' || *p == '\n' || !*p) continue;
        p[strcspn(p, "\n")] = 0;
        char who[64];
        int is_group = 0;
        if (*p == '%') { is_group = 1; p++; }
        char *sp = strchr(p, ' ');
        if (!sp) continue;
        size_t n = (size_t)(sp - p);
        if (n >= sizeof who) continue;
        memcpy(who, p, n); who[n] = 0;
        if (!who_matches(who, is_group, user)) continue;
        /* 剩余: "ALL=(ALL)" 或 "ALL=(NOPASSWD) /cmd,/cmd2" */
        const char *np = strstr(sp, "(NOPASSWD)");
        if (np) {
            const char *cl = np + strlen("(NOPASSWD)");
            if (*cl == 0 || cmd_in_list(cl, cmd)) { ok = 1; break; }
        } else if (strstr(sp, "ALL")) {
            ok = 0;   /* 需密码授权; 继续找可能存在的 NOPASSWD 行 */
        }
    }
    fclose(f);
    return ok;
}

int main(int argc, char **argv)
{
    int noforce = 0;   /* -n: 不提示密码 */
    int argi = 1;
    if (argc >= 2 && strcmp(argv[1], "-n") == 0) { noforce = 1; argi = 2; }
    if (argc < argi + 1) {
        fprintf(stderr, "用法: qysudo [-n] <命令> [参数...]\n");
        return 2;
    }
    uid_t uid = getuid();
    struct passwd *pw = getpwuid(uid);
    if (!pw) { fprintf(stderr, "qysudo: 找不到当前用户\n"); return 3; }

    /* 命令解析: 绝对路径直接用; 裸名在安全 PATH 中解析 */
    char cmdbuf[512];
    const char *cmd = argv[argi];
    if (cmd[0] == '/') {
        strncpy(cmdbuf, cmd, sizeof cmdbuf - 1); cmdbuf[sizeof cmdbuf - 1] = 0;
    } else {
        const char *dirs[] = {"/usr/bin", "/bin", "/usr/sbin", "/sbin"};
        int found = 0;
        for (unsigned i = 0; i < 4; i++) {
            snprintf(cmdbuf, sizeof cmdbuf, "%s/%s", dirs[i], cmd);
            struct stat st;
            if (stat(cmdbuf, &st) == 0 && S_ISREG(st.st_mode) && access(cmdbuf, X_OK) == 0) {
                found = 1; break;
            }
        }
        if (!found) {
            fprintf(stderr, "qysudo: 找不到命令 %s\n", cmd);
            return 8;
        }
    }
    if (strstr(cmdbuf, "..")) {
        fprintf(stderr, "qysudo: 拒绝含相对路径的命令\n");
        return 8;
    }

    int auth = authorized(pw->pw_name, cmdbuf);
    if (auth < 0) {
        fprintf(stderr, "qysudo: 用户 %s 不在授权列表 (/etc/qysudoers)\n", pw->pw_name);
        return 4;
    }

    /* root 用户免密 */
    if (uid != 0 && auth == 0) {
        if (noforce) {
            fprintf(stderr, "qysudo: 需要密码（-n 且命令不在 NOPASSWD 白名单）\n");
            return 9;
        }
        struct spwd *sp = getspnam(pw->pw_name);
        char input[256];
        int tries = 3;
        int ok = -1;
        while (tries--) {
            read_password("[qysudo] 密码: ", input, sizeof input);
            ok = verify_password(sp ? sp->sp_pwdp : NULL, input);
            if (ok == 0) break;
            fprintf(stderr, "qysudo: 密码错误\n");
        }
        if (ok != 0) return 5;
    }

    /* 提权执行 */
    if (setgid(0) != 0 || setuid(0) != 0) {
        fprintf(stderr, "qysudo: 提权失败: %s\n", strerror(errno));
        return 6;
    }
    setenv("PATH", PATH_SAFE, 1);
    setenv("HOME", "/root", 1);
    setenv("USER", "root", 1);
    execv(cmdbuf, &argv[argi]);
    fprintf(stderr, "qysudo: 执行 %s 失败: %s\n", cmdbuf, strerror(errno));
    return 7;
}
