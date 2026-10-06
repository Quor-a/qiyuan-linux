/*
 * qyl10n.c — 启元多语言实现: zh→en 字符串表 + 语言探测
 */
#include "qyl10n.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const char *zh, *en; } pair;

static const pair tbl[] = {
    /* 应用菜单 */
    { "文件管理器", "Files" },
    { "终端", "Terminal" },
    { "系统设置", "Settings" },
    { "文本编辑", "Text Editor" },
    { "系统监视", "System Monitor" },
    { "图片查看", "Image Viewer" },
    { "压缩管理", "Archive Manager" },
    { "系统安装", "System Installer" },
    { "用户管理", "User Manager" },
    { "计算器", "Calculator" },
    { "欢迎向导", "Welcome Wizard" },
    { "常用", "Frequent" },
    { "全部应用", "All Apps" },
    { "搜索…", "Search…" },
    { "搜索", "Search" },
    { "无匹配应用", "No matching apps" },
    /* 设置 */
    { "关于", "About" },
    { "显示", "Display" },
    { "字体", "Fonts" },
    { "服务", "Services" },
    { "声音", "Sound" },
    { "语言", "Language" },
    { "音量", "Volume" },
    { "亮度", "Brightness" },
    { "简体中文", "Simplified Chinese" },
    { "English", "English" },
    /* 编辑器/查看器 */
    { "打开", "Open" },
    { "保存", "Save" },
    { "另存为", "Save As" },
    { "退出", "Quit" },
    { "新建", "New" },
    { "文件名", "Filename" },
    { "未命名", "Untitled" },
    /* 压缩 */
    { "创建压缩包", "Create Archive" },
    { "解压到…", "Extract to…" },
    { "添加文件", "Add Files" },
    /* 用户 */
    { "新建用户", "New User" },
    { "删除", "Delete" },
    { "修改密码", "Change Password" },
    { "用户名", "Username" },
    { "密码", "Password" },
    /* 安装器 */
    { "目标磁盘", "Target Disk" },
    { "安装", "Install" },
    { "确认安装", "Confirm Install" },
    { "初始用户", "Initial User" },
    { "跳过", "Skip" },
    { "确定", "OK" },
    { "取消", "Cancel" },
    { "稍后重启", "Reboot Later" },
    { "立即重启", "Reboot Now" },
    /* 欢迎向导 */
    { "主机名", "Hostname" },
    { "确认密码", "Confirm Password" },
    { "时区", "Timezone" },
    { "完成配置", "Finish Setup" },
    /* 监视 */
    { "CPU", "CPU" },
    { "内存", "Memory" },
    { "进程", "Processes" },
    { "磁盘", "Disk" },
};

#define NTBL ((int)(sizeof tbl / sizeof tbl[0]))

static int lang_is_en(void)
{
    const char *e = getenv("QYLANG");
    if (e && (strcmp(e, "en") == 0 || strcmp(e, "en_US") == 0))
        return 1;
    FILE *f = fopen("/etc/qylang", "r");
    if (f) {
        char buf[16] = {0};
        if (fgets(buf, sizeof buf, f)) {
            /* 去尾换行 */
            for (char *p = buf; *p; p++)
                if (*p == '\n' || *p == '\r') { *p = 0; break; }
            if (strcmp(buf, "en") == 0) { fclose(f); return 1; }
        }
        fclose(f);
    }
    return 0;
}

const char *qy_tr(const char *zh, const char *en)
{
    static int cached = -1;
    if (cached < 0) cached = lang_is_en();
    if (!cached) return zh;
    for (int i = 0; i < NTBL; i++)
        if (strcmp(tbl[i].zh, zh) == 0) return tbl[i].en;
    return en ? en : zh;
}
