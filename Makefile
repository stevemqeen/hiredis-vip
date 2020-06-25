# Hiredis Makefile
# Copyright (C) 2010-2011 Salvatore Sanfilippo <antirez at gmail dot com>
# Copyright (C) 2010-2011 Pieter Noordhuis <pcnoordhuis at gmail dot com>
# This file is released under the BSD license, see the COPYING file

OBJ=lib/hiredis/alloc.o lib/hiredis/net.o lib/hiredis/hiredis.o lib/hiredis/sds.o lib/hiredis/async.o lib/hiredis/read.o lib/hiredis/sockcompat.o hiarray.o hiutil.o command.o crc16.o adlist.o hircluster.o
EXAMPLES=hiredis-example hiredis-example-libevent hiredis-example-libev hiredis-example-glib
TESTS=hiredis-test
LIBNAME=libhiredis_vip
PKGCONFNAME=hiredis_vip.pc

HIREDIS_VIP_MAJOR=$(shell grep HIREDIS_VIP_MAJOR hircluster.h | awk '{print $$3}')
HIREDIS_VIP_MINOR=$(shell grep HIREDIS_VIP_MINOR hircluster.h | awk '{print $$3}')
HIREDIS_VIP_PATCH=$(shell grep HIREDIS_VIP_PATCH hircluster.h | awk '{print $$3}')

# Installation related variables and target
PREFIX?=/usr/local
INCLUDE_PATH?=include/hiredis-vip
INCLUDE_HIREDIS_PATH?=include/hiredis-vip/lib/hiredis
LIBRARY_PATH?=lib
PKGCONF_PATH?=pkgconfig
INSTALL_INCLUDE_PATH= $(DESTDIR)$(PREFIX)/$(INCLUDE_PATH)
INSTALL_LIBRARY_PATH= $(DESTDIR)$(PREFIX)/$(LIBRARY_PATH)
INSTALL_PKGCONF_PATH= $(INSTALL_LIBRARY_PATH)/$(PKGCONF_PATH)
INSTALL_INCLUDE_HPATH= $(DESTDIR)$(PREFIX)/$(INCLUDE_HIREDIS_PATH)

# redis-server configuration used for testing
REDIS_PORT=56379
REDIS_SERVER=redis-server
define REDIS_TEST_CONFIG
	daemonize yes
	pidfile /tmp/hiredis-test-redis.pid
	port $(REDIS_PORT)
	bind 127.0.0.1
	unixsocket /tmp/hiredis-test-redis.sock
endef
export REDIS_TEST_CONFIG

# Fallback to gcc when $CC is not in $PATH.
CC:=$(shell sh -c 'type $(CC) >/dev/null 2>/dev/null && echo $(CC) || echo gcc')
OPTIMIZATION?=-O3
WARNINGS=-Wall -W -Wstrict-prototypes -Wwrite-strings
DEBUG?= -g -ggdb
REAL_CFLAGS=$(OPTIMIZATION) -fPIC $(CFLAGS) $(WARNINGS) $(DEBUG) $(ARCH)
REAL_LDFLAGS=$(LDFLAGS) $(ARCH)

DYLIBSUFFIX=so
STLIBSUFFIX=a
DYLIB_MINOR_NAME=$(LIBNAME).$(DYLIBSUFFIX).$(HIREDIS_VIP_MAJOR).$(HIREDIS_VIP_MINOR)
DYLIB_MAJOR_NAME=$(LIBNAME).$(DYLIBSUFFIX).$(HIREDIS_VIP_MAJOR)
DYLIBNAME=$(LIBNAME).$(DYLIBSUFFIX)
DYLIB_MAKE_CMD=$(CC) -shared -Wl,-soname,$(DYLIB_MINOR_NAME) -o $(DYLIBNAME) $(LDFLAGS)
STLIBNAME=$(LIBNAME).$(STLIBSUFFIX)
STLIB_MAKE_CMD=ar rcs $(STLIBNAME)

# Platform-specific overrides
uname_S := $(shell sh -c 'uname -s 2>/dev/null || echo not')
ifeq ($(uname_S),SunOS)
  REAL_LDFLAGS+= -ldl -lnsl -lsocket
  DYLIB_MAKE_CMD=$(CC) -G -o $(DYLIBNAME) -h $(DYLIB_MINOR_NAME) $(LDFLAGS)
  INSTALL= cp -r
endif
ifeq ($(uname_S),Darwin)
  DYLIBSUFFIX=dylib
  DYLIB_MINOR_NAME=$(LIBNAME).$(HIREDIS_VIP_MAJOR).$(HIREDIS_VIP_MINOR).$(DYLIBSUFFIX)
  DYLIB_MAJOR_NAME=$(LIBNAME).$(HIREDIS_VIP_MAJOR).$(DYLIBSUFFIX)
  DYLIB_MAKE_CMD=$(CC) -shared -Wl,-install_name,$(DYLIB_MINOR_NAME) -o $(DYLIBNAME) $(LDFLAGS)
endif

all: $(DYLIBNAME) $(STLIBNAME) hiredis-test $(PKGCONFNAME)

# Deps (use make dep to generate this)

adlist.o: adlist.c adlist.h hiutil.h
command.o: command.c command.h lib/hiredis/hiredis.h lib/hiredis/read.h lib/hiredis/sds.h adlist.h hiutil.h hiarray.h
crc16.o: crc16.c hiutil.h
hiarray.o: hiarray.c hiarray.h hiutil.h
hircluster.o: hircluster.c lib/hiredis/fmacros.h hircluster.h lib/hiredis/hiredis.h lib/hiredis/read.h lib/hiredis/sds.h lib/hiredis/alloc.h adlist.h hiarray.h hiutil.h lib/hiredis/async.h command.h lib/hiredis/dict.c lib/hiredis/dict.h
hiutil.o: hiutil.c hiutil.h

$(DYLIBNAME): $(OBJ)
	$(DYLIB_MAKE_CMD) $(OBJ)

$(STLIBNAME): $(OBJ)
	$(STLIB_MAKE_CMD) $(OBJ)

dynamic: $(DYLIBNAME)
static: $(STLIBNAME)

# Binaries:
hiredis-example-libevent: examples/example-libevent.c adapters/libevent.h $(STLIBNAME)
	$(CC) -o examples/$@ $(REAL_CFLAGS) $(REAL_LDFLAGS) -I. $< -levent $(STLIBNAME)

hiredis-example-libev: examples/example-libev.c adapters/libev.h $(STLIBNAME)
	$(CC) -o examples/$@ $(REAL_CFLAGS) $(REAL_LDFLAGS) -I. $< -lev $(STLIBNAME)

hiredis-example-glib: examples/example-glib.c adapters/glib.h $(STLIBNAME)
	$(CC) -o examples/$@ $(REAL_CFLAGS) $(REAL_LDFLAGS) $(shell pkg-config --cflags --libs glib-2.0) -I. $< $(STLIBNAME)

ifndef AE_DIR
hiredis-example-ae:
	@echo "Please specify AE_DIR (e.g. <redis repository>/src)"
	@false
else
hiredis-example-ae: examples/example-ae.c adapters/ae.h $(STLIBNAME)
	$(CC) -o examples/$@ $(REAL_CFLAGS) $(REAL_LDFLAGS) -I. -I$(AE_DIR) $< $(AE_DIR)/ae.o $(AE_DIR)/zmalloc.o $(AE_DIR)/../deps/jemalloc/lib/libjemalloc.a -pthread $(STLIBNAME)
endif

ifndef LIBUV_DIR
hiredis-example-libuv:
	@echo "Please specify LIBUV_DIR (e.g. ../libuv/)"
	@false
else
hiredis-example-libuv: examples/example-libuv.c adapters/libuv.h $(STLIBNAME)
	$(CC) -o examples/$@ $(REAL_CFLAGS) $(REAL_LDFLAGS) -I. -I$(LIBUV_DIR)/include $< $(LIBUV_DIR)/.libs/libuv.a -lpthread $(STLIBNAME)
endif

hiredis-example: examples/example.c $(STLIBNAME)
	$(CC) -o examples/$@ $(REAL_CFLAGS) $(REAL_LDFLAGS) -I. $< $(STLIBNAME)

examples: $(EXAMPLES)

hiredis-test: lib/hiredis/test.o $(STLIBNAME)

hiredis-%: %.o $(STLIBNAME)
	$(CC) $(REAL_CFLAGS) -o $@ $(REAL_LDFLAGS) $< $(STLIBNAME)

test: hiredis-test
	./hiredis-test

check: hiredis-test
	@echo "$$REDIS_TEST_CONFIG" | $(REDIS_SERVER) -
	$(PRE) ./hiredis-test -h 127.0.0.1 -p $(REDIS_PORT) -s /tmp/hiredis-test-redis.sock || \
			( kill `cat /tmp/hiredis-test-redis.pid` && false )
	kill `cat /tmp/hiredis-test-redis.pid`

.c.o:
	$(CC) -std=c99 -pedantic -c $(REAL_CFLAGS) $<

clean:
	rm -rf $(DYLIBNAME) $(STLIBNAME) $(TESTS) $(PKGCONFNAME) examples/hiredis-example* *.o *.gcda *.gcno *.gcov

dep:
	$(CC) -MM *.c

ifeq ($(uname_S),SunOS)
  INSTALL?= cp -r
endif

INSTALL?= cp -a

$(PKGCONFNAME): lib/hiredis/hiredis.h
	@echo "Generating $@ for pkgconfig..."
	@echo prefix=$(PREFIX) > $@
	@echo exec_prefix=\$${prefix} >> $@
	@echo libdir=$(PREFIX)/$(LIBRARY_PATH) >> $@
	@echo includedir=$(PREFIX)/$(INCLUDE_PATH) >> $@
	@echo >> $@
	@echo Name: hiredis-vip >> $@
	@echo Description: Minimalistic C client library for Redis and Redis Cluster. >> $@
	@echo Version: $(HIREDIS_VIP_MAJOR).$(HIREDIS_VIP_MINOR).$(HIREDIS_VIP_PATCH) >> $@
	@echo Libs: -L\$${libdir} -lhiredis_vip >> $@
	@echo Cflags: -I\$${includedir} -D_FILE_OFFSET_BITS=64 >> $@

install: $(DYLIBNAME) $(STLIBNAME) $(PKGCONFNAME)
	mkdir -p $(INSTALL_INCLUDE_PATH) $(INSTALL_INCLUDE_HPATH) $(INSTALL_LIBRARY_PATH)
	$(INSTALL) hiutil.h hiarray.h adlist.h hircluster.h $(INSTALL_INCLUDE_PATH)
	$(INSTALL) lib/hiredis/alloc.h lib/hiredis/hiredis.h lib/hiredis/async.h lib/hiredis/read.h lib/hiredis/sds.h lib/hiredis/dict.h lib/hiredis/dict.c lib/hiredis/fmacros.h lib/hiredis/adapters $(INSTALL_INCLUDE_HPATH)
	$(INSTALL) $(DYLIBNAME) $(INSTALL_LIBRARY_PATH)/$(DYLIB_MINOR_NAME)
	cd $(INSTALL_LIBRARY_PATH) && ln -sf $(DYLIB_MINOR_NAME) $(DYLIB_MAJOR_NAME)
	cd $(INSTALL_LIBRARY_PATH) && ln -sf $(DYLIB_MAJOR_NAME) $(DYLIBNAME)
	$(INSTALL) $(STLIBNAME) $(INSTALL_LIBRARY_PATH)
	mkdir -p $(INSTALL_PKGCONF_PATH)
	$(INSTALL) $(PKGCONFNAME) $(INSTALL_PKGCONF_PATH)

32bit:
	@echo ""
	@echo "WARNING: if this fails under Linux you probably need to install libc6-dev-i386"
	@echo ""
	$(MAKE) CFLAGS="-m32" LDFLAGS="-m32"

32bit-vars:
	$(eval CFLAGS=-m32)
	$(eval LDFLAGS=-m32)

gprof:
	$(MAKE) CFLAGS="-pg" LDFLAGS="-pg"

gcov:
	$(MAKE) CFLAGS="-fprofile-arcs -ftest-coverage" LDFLAGS="-fprofile-arcs"

coverage: gcov
	make check
	mkdir -p tmp/lcov
	lcov -d . -c -o tmp/lcov/hiredis.info
	genhtml --legend -o tmp/lcov/report tmp/lcov/hiredis.info

noopt:
	$(MAKE) OPTIMIZATION=""

.PHONY: all test check clean dep install 32bit gprof gcov noopt
