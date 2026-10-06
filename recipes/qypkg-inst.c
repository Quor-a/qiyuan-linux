/*
 * qypkg-inst — 启元 .qyp 包安装器 (v1.9.5)
 * 用法: qypkg-inst [-l] <pkg.qyp> [<pkg.qyp>...]
 *       qypkg-inst -r <name>       卸载 (读 /var/lib/qypkg/installed/<name>.files)
 * QYPKG 格式: 128B 头 (MAGIC "QYPKG\0\0\0" + <8sII6Q32s32s) + meta json + data tar + sig
 * 解包: data 段 spool 到临时文件, 按 meta.build.compression (gz|xz) fork tar 解到 /
 * 已装记录: /var/lib/qypkg/installed/<name> (json 摘要) + <name>.files (文件清单)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <dirent.h>

#ifndef QYREPO_DIR
#define QYREPO_DIR "/usr/share/qyrepo"
#endif
#define INST_DIR   "/var/lib/qypkg/installed"
#define HDR_SIZE   128
static const char QY_MAGIC[8] = { 'Q','Y','P','K','G',0,1,0 };

static unsigned long long rd64(const unsigned char *p) {
    unsigned long long v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | p[i];
    return v;
}

/* 从 meta json 提取字符串字段 "key":"value" (简易扫描, 无转义处理足够包名/版本) */
static int json_str(const char *js, const char *key, char *out, size_t outsz) {
    char pat[64];
    snprintf(pat, sizeof pat, "\"%s\"", key);
    const char *k = strstr(js, pat);
    if (!k) return -1;
    k = strchr(k + strlen(pat), ':');
    if (!k) return -1;
    while (*k && *k != '"') k++;
    if (*k != '"') return -1;
    k++;
    size_t i = 0;
    while (*k && *k != '"' && i + 1 < outsz) out[i++] = *k++;
    out[i] = 0;
    return 0;
}

static int spool_data(const char *path, long doff, long dlen, char *tmp, size_t tsz) {
    snprintf(tmp, tsz, "/tmp/.qypkg-data.XXXXXX");
    int tfd = mkstemp(tmp);
    if (tfd < 0) return -1;
    int fd = open(path, O_RDONLY);
    if (fd < 0) { close(tfd); unlink(tmp); return -1; }
    if (lseek(fd, doff, SEEK_SET) < 0) { close(fd); close(tfd); unlink(tmp); return -1; }
    char buf[65536];
    long left = dlen;
    while (left > 0) {
        ssize_t r = read(fd, buf, left > (long)sizeof buf ? sizeof buf : (size_t)left);
        if (r <= 0) break;
        ssize_t w = write(tfd, buf, r);
        if (w != r) { close(fd); close(tfd); unlink(tmp); return -1; }
        left -= r;
    }
    close(fd);
    close(tfd);
    return left == 0 ? 0 : -1;
}

/* files 清单: 从 meta 的 "files":[...] 里抓 "path":"..."  (含 dir 条目, 记录时过滤) */
static int write_filelist(const char *js, const char *listpath) {
    FILE *f = fopen(listpath, "w");
    if (!f) return -1;
    const char *p = js;
    while ((p = strstr(p, "\"path\""))) {
        const char *q = strchr(p, ':');
        if (!q) break;
        while (*q && *q != '"') q++;
        if (*q != '"') { p += 6; continue; }
        q++;
        char pathbuf[512]; size_t i = 0;
        while (*q && *q != '"' && i + 1 < sizeof pathbuf) pathbuf[i++] = *q++;
        pathbuf[i] = 0;
        if (i && strstr(p, "\"type\":\"file\""))
            fprintf(f, "%s\n", pathbuf);
        p = q;
    }
    fclose(f);
    return 0;
}

static int install_one(const char *path) {
    unsigned char hdr[HDR_SIZE];
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "qypkg-inst: 打不开 %s: %s\n", path, strerror(errno)); return 3; }
    if (fread(hdr, 1, HDR_SIZE, f) != HDR_SIZE || memcmp(hdr, QY_MAGIC, 8) != 0) {
        fprintf(stderr, "qypkg-inst: %s 不是 QYPKG 包\n", path); fclose(f); return 3;
    }
    long meta_off = (long)rd64(hdr + 16),  meta_len = (long)rd64(hdr + 24);
    long data_off = (long)rd64(hdr + 32),  data_len = (long)rd64(hdr + 40);
    char *js = malloc(meta_len + 1);
    if (!js || fread(js, 1, meta_len, f) != (size_t)meta_len) { fclose(f); return 3; }
    js[meta_len] = 0;
    fclose(f);

    char name[128] = "", ver[64] = "", comp[32] = "";
    json_str(js, "name", name, sizeof name);
    json_str(js, "version", ver, sizeof ver);
    json_str(js, "compression", comp, sizeof comp);
    if (!name[0]) { fprintf(stderr, "qypkg-inst: meta 缺 name\n"); free(js); return 3; }
    printf("安装 %s-%s (%s) ...\n", name, ver, comp);

    char tmp[64];
    if (spool_data(path, data_off, data_len, tmp, sizeof tmp) != 0) {
        fprintf(stderr, "qypkg-inst: data 段读取出错\n"); free(js); return 4;
    }

    char cmd[512];
    if (strcmp(comp, "xz") == 0)
        snprintf(cmd, sizeof cmd, "exec xzcat '%s' 2>/dev/null | exec busybox tar -xf - -C / -p", tmp);
    else
        snprintf(cmd, sizeof cmd, "exec busybox tar -xzf '%s' -C / -p", tmp);
    /* busybox tar 无 --strip; 包内路径自带 usr/... 前缀, 直接解到 / */
    int rc = system(cmd);
    unlink(tmp);
    if (rc != 0) { fprintf(stderr, "qypkg-inst: tar 解包失败\n"); free(js); return 5; }

    mkdir("/var/lib", 0755);
    mkdir("/var/lib/qypkg", 0755);
    mkdir(INST_DIR, 0755);
    char rec[300], listpath[300];
    snprintf(rec, sizeof rec, INST_DIR "/%s", name);
    snprintf(listpath, sizeof listpath, INST_DIR "/%s.files", name);
    FILE *r = fopen(rec, "w");
    if (r) { fprintf(r, "{\"name\":\"%s\",\"version\":\"%s\",\"file\":\"%s\"}\n", name, ver, path); fclose(r); }
    write_filelist(js, listpath);
    free(js);
    printf("已安装 %s-%s\n", name, ver);
    return 0;
}

static int remove_one(const char *name) {
    char listpath[300];
    snprintf(listpath, sizeof listpath, INST_DIR "/%s.files", name);
    FILE *f = fopen(listpath, "r");
    if (!f) { fprintf(stderr, "qypkg-inst: 未安装 %s\n", name); return 6; }
    char line[512];
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\n")] = 0;
        struct stat st;
        if (stat(line, &st) == 0) {
            if (S_ISDIR(st.st_mode)) rmdir(line);
            else if (unlink(line) != 0 && errno != ENOENT)
                fprintf(stderr, "qypkg-inst: unlink %s: %s\n", line, strerror(errno));
        }
    }
    fclose(f);
    char rec[300];
    snprintf(rec, sizeof rec, INST_DIR "/%s", name);
    unlink(rec);
    unlink(listpath);
    printf("已卸载 %s\n", name);
    return 0;
}

static int list_installed(void) {
    mkdir("/var/lib/qypkg", 0755);
    mkdir(INST_DIR, 0755);
    DIR *d = opendir(INST_DIR);
    if (!d) return 1;
    struct dirent *e;
    while ((e = readdir(d))) {
        size_t n = strlen(e->d_name);
        if (n > 6 && strcmp(e->d_name + n - 6, ".files") == 0) continue;
        if (e->d_name[0] == '.') continue;
        printf("%s\n", e->d_name);
    }
    closedir(d);
    return 0;
}

int main(int argc, char **argv) {
    if (argc >= 2 && strcmp(argv[1], "-l") == 0) return list_installed();
    if (argc >= 3 && strcmp(argv[1], "-r") == 0) return remove_one(argv[2]);
    if (argc < 2) { fprintf(stderr, "用法: qypkg-inst [-l|-r name] pkg.qyp...\n"); return 2; }
    int rc = 0;
    for (int i = 1; i < argc; i++) {
        int r = install_one(argv[i]);
        if (r != 0) rc = r;
    }
    return rc;
}
