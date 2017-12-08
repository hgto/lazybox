# vim: set noet tabstop=5:

CC := gcc-7
CXX := g++-7
CPPFLAGS := -D_FORTIFY_SOURCE=2
LOCALMK_CMAKE_FLAGS = -DMIN_LOG_LEVEL=0 -DCMAKE_INSTALL_PREFIX=/usr/local
all:
	setenv
.PHONY: hgtorel
hgtorel: CFLAGS := -O2 -fstack-protector-strong -pie -fPIE
hgtorel: LOCALMK_CMAKE_FLAGS += -DCMAKE_BUILD_TYPE=RelWithDebInfo
hgtorel: _hgtoclean _hgtobuild _hgtoinstall

.PHONY: hgtodebug
hgtodebug: LOCALMK_CMAKE_FLAGS += -DCMAKE_BUILD_TYPE=Debug
hgtodebug: _hgtoclean _hgtobuild _hgtoinstall

.PHONY: _hgtoclean
_hgtoclean: clean
	rm -rf build
	mkdir -p build

.PHONY: hgtodeps
hgtodeps: distclean
	#export CC=$(CC) CXX=$(CC) CPPFLAGS=$(CPPFLAGS) && 
	make deps

.PHONY: _hgtobuild
_hgtobuild: EXPORTS = export CC="$(CC)" CXX="$(CXX)" CPPFLAGS="$(CPPFLAGS)" CFLAGS="$(CFLAGS)"
_hgtobuild: _hgtoclean
	cd build && $(EXPORTS) && cmake .. $(LOCALMK_CMAKE_FLAGS)

.PHONY: _hgtoinstall
_hgtoinstall:
	# make installs
	make

.PHONY: hgtobrew
hgtobrew:
	brew install libtool automake cmake pkg-config gettext ninja gcc
