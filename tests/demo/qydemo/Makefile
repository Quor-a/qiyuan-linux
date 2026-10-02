CC      ?= gcc
CFLAGS  ?= -O2
PREFIX  ?= /usr

all: qydemo

qydemo: main.c
	$(CC) $(CFLAGS) -o $@ main.c -lqydemo $(LDFLAGS)

install: all
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	install -m 0755 qydemo $(DESTDIR)$(PREFIX)/bin/qydemo

clean:
	rm -f qydemo
