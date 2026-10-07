"""rsync —— 增量文件同步工具（系统必备）

https://rsync.samba.org
许可证：GPL-3.0+
"""

name = "rsync"
version = "3.4.1"
release = 1
summary = "远程与本地文件的快速增量同步"
homepage = "https://rsync.samba.org"
license = "GPL-3.0+"

source = ["https://download.samba.org/pub/rsync/src/rsync-3.4.1.tar.gz"]
sha256 = ["2924bcb3a1ed8b551fc101f740b9f0fe0a202b115027647cf69850d65fd88c52"]

depends = ["zlib", "openssl"]


def fetch(ctx):
    ctx.default_fetch()


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-md2man --disable-lz4 --disable-zstd --disable-xxhash")
    ctx.run("make -j2")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
