CC      ?= gcc
CFLAGS  ?= -O2 -Wall -Wextra
LDFLAGS ?=
PREFIX  ?= /usr
DESTDIR ?=

all: qyinit

qyinit: qyinit.c
	$(CC) $(CFLAGS) -o $@ qyinit.c $(LDFLAGS) -lutil

install: all
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	install -m 0755 qyinit $(DESTDIR)$(PREFIX)/bin/qyinit

clean:
	rm -f qyinit
