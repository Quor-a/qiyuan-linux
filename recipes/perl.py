"""perl —— Perl 脚本语言（很多构建系统依赖它）

https://www.perl.org
许可证：GPL-1.0-or-later OR Artistic-1.0-Perl
"""

name = "perl"
version = "5.40.1"
release = 1
summary = "Perl 脚本语言（很多构建系统依赖它）"
homepage = "https://www.perl.org"
license = "GPL-1.0-or-later OR Artistic-1.0-Perl"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums perl
source = ["https://www.cpan.org/src/5.0/perl-5.40.1.tar.xz"]
sha256 = ["dfa20c2eef2b4af133525610bbb65dd13777ecf998c9c5b1ccf0d308e732ee3f"]

depends = ["gdbm", "zlib"]
makedepends = ["coreutils", "gdbm", "zlib"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./Configure -des -Dprefix=/usr -Dvendorprefix=/usr -Dprivlib=/usr/lib/perl5/5.40/core_perl -Darchlib=/usr/lib/perl5/5.40/core_perl -Dsitelib=/usr/lib/perl5/5.40/site_perl -Dsitearch=/usr/lib/perl5/5.40/site_perl -Dman1dir=/usr/share/man/man1 -Dman3dir=/usr/share/man/man3 -Duseshrplib -Dusethreads")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
