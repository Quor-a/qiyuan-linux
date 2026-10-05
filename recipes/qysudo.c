/* qysudo - 启元权限提升工具 (setuid root)
 * 用法: qysudo <命令> [参数...]
 * 校验链: /etc/qysudoers（用户或 %组 授权）→ /etc/shadow 密码校验 → 以 root 执行
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
#include <pwd.h>
#include <grp.h>
#include <termios.h>
#include <shadow.h>
#include <crypt.h>
#include <time.h>

#define PATH_SAFE "/usr/bin:/bin:/usr/sbin:/sbin"

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

/* qysudoers 校验: <user>|%<group> ALL=(ALL) ALL ；一行一条 */
static int authorized(const char *user)
{
    FILE *f = fopen("/etc/qysudoers", "r");
    if (!f) return -1;                       /* 无配置 = 全部拒绝 */
    char line[256];
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
        /* 后面要求出现 ALL=(ALL) ALL */
        if (!strstr(sp, "ALL")) continue;
        if (is_group) {
            if (in_group(user, who) == 1) { ok = 0; break; }
        } else {
            if (strcmp(user, who) == 0) { ok = 0; break; }
        }
    }
    fclose(f);
    return ok;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "用法: qysudo <命令> [参数...]\n");
        return 2;
    }
    uid_t uid = getuid();
    struct passwd *pw = getpwuid(uid);
    if (!pw) { fprintf(stderr, "qysudo: 找不到当前用户\n"); return 3; }

    if (authorized(pw->pw_name) != 0) {
        fprintf(stderr, "qysudo: 用户 %s 不在授权列表 (/etc/qysudoers)\n", pw->pw_name);
        return 4;
    }

    /* root 用户免密 */
    if (uid != 0) {
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
    execvp(argv[1], &argv[1]);
    fprintf(stderr, "qysudo: 执行 %s 失败: %s\n", argv[1], strerror(errno));
    return 7;
}
