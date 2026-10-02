"""lua —— Lua 脚本语言（vim 等嵌入）


许可证：MIT
"""

name = "lua"
version = "5.4.7"
release = 1
summary = "Lua 脚本语言（vim 等嵌入）"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums lua
source = ["https://www.lua.org/ftp/lua-5.4.7.tar.gz"]
sha256 = ["9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30"]
checksum_pending = True

depends = ["readline"]
makedepends = ["readline"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("make linux")


def package(ctx):
    ctx.run("make INSTALL_TOP={}/usr install".format(ctx.destdir))
