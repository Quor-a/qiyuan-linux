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
sha256 = ["19600d944e05f7ed95bac53c18cbae6ce7eff859c62b434b0c315ca72acb1d3c"]
checksum_pending = False

depends = []
makedepends = ["go"]
provides = []

requires_build_machine = True
network = True
compression = "gz"


def build(ctx):
    ctx.log("Go 静态构建 frpc/frps（CGO 关闭，纯静态，可拷贝到任何 Linux）")
    ctx.env("CGO_ENABLED", "0")
    # frp 的 go.mod 声明 go 1.23.0，本机工具链 1.24.4 时 Go 会尝试
    # 下载 go1.23.0 工具链——用国内代理；模块依赖同样走它
    ctx.env("GOPROXY", "https://goproxy.cn,direct")
    ctx.env("GOSUMDB", "sum.golang.google.cn")
    # strip_components=1 后源码树顶层被剥掉，cmd/frpc 直接在 src 下
    ctx.run("go build -trimpath -ldflags='-s -w' -o frpc ./cmd/frpc")
    ctx.run("go build -trimpath -ldflags='-s -w' -o frps ./cmd/frps")
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
    ctx.run("cp -a README.md LICENSE "
            "{}/usr/share/doc/frp/ 2>/dev/null || true".format(ctx.destdir))
