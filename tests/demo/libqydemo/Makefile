CC      ?= gcc
CFLAGS  ?= -O2
PREFIX  ?= /usr
LIBDIR  ?= $(PREFIX)/lib

all: libqydemo.so.1

libqydemo.so.1: qydemo.c
	$(CC) $(CFLAGS) -fPIC -shared -Wl,-soname,libqydemo.so.1 \
	    -o $@ qydemo.c $(LDFLAGS)

install: all
	mkdir -p $(DESTDIR)$(LIBDIR) $(DESTDIR)$(PREFIX)/include
	install -m 0755 libqydemo.so.1 $(DESTDIR)$(LIBDIR)/
	ln -sf libqydemo.so.1 $(DESTDIR)$(LIBDIR)/libqydemo.so
	install -m 0644 qydemo.h $(DESTDIR)$(PREFIX)/include/

clean:
	rm -f libqydemo.so.1
