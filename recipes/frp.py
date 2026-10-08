"""frp —— 快速反向代理（内网穿透事实标准）

许可证：Apache-2.0
设计依据：用户 2026-10-08 内网穿透清单（首批进仓库二选之一）。
Go 静态二进制：frpc（客户端，跑在内网机器）+ frps（服务端，跑在公网）。
配 systemd/qyinit 单元示例见 files/。

首次构建需要 Go 工具链（recipes/go.py）；之后的构建走 Go 构建缓存。
"""

name = "frp"
version = "0.61.2"
release = 1
summary = "内网穿透反向代理（frpc 客户端 + frps 服务端）"
license = "Apache-2.0"

source = ["https://github.com/fatedier/frp/archive/refs/tags/v0.61.2.tar.gz"]
sha256 = []
checksum_pending = True

depends = []
makedepends = ["go"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.log("Go 静态构建 frpc/frps（CGO 关闭，纯静态，可拷贝到任何 Linux）")
    ctx.env("CGO_ENABLED", "0")
    ctx.run("cd frp-0.61.2 && go build -trimpath -ldflags='-s -w' "
            "-o ../frpc ./cmd/frpc")
    ctx.run("cd frp-0.61.2 && go build -trimpath -ldflags='-s -w' "
            "-o ../frps ./cmd/frps")
    ctx.run("./frpc --version && ./frps --version")


def package(ctx):
    ctx.run("mkdir -p {}/usr/bin {}/etc/frp "
            "{}/usr/share/doc/frp".format(ctx.destdir, ctx.destdir, ctx.destdir))
    ctx.run("install -m755 frpc {}/usr/bin/frpc".format(ctx.destdir))
    ctx.run("install -m755 frps {}/usr/bin/frps".format(ctx.destdir))
    # 示例配置：最小可用的客户端/服务端 TOML
    ctx.run("cat > {0}/etc/frp/frpc.toml <<'EOF'\n"
            "# frp 客户端最小配置\n"
            "serverAddr = \"你的公网服务器IP\"\n"
            "serverPort = 7000\n"
            "\n"
            "[[proxies]]\n"
            "name = \"ssh\"\n"
            "type = \"tcp\"\n"
            "localIP = \"127.0.0.1\"\n"
            "localPort = 22\n"
            "remotePort = 6022\n"
            "EOF".format(ctx.destdir))
    ctx.run("cat > {0}/etc/frp/frps.toml <<'EOF'\n"
            "# frp 服务端最小配置\n"
            "bindPort = 7000\n"
            "auth.token = \"请改成随机长字符串\"\n"
            "EOF".format(ctx.destdir))
    ctx.run("cp -a frp-0.61.2/README* frp-0.61.2/LICENSE "
            "{}/usr/share/doc/frp/ 2>/dev/null || true".format(ctx.destdir))
