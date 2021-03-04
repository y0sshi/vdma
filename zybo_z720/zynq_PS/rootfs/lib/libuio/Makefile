################################ Set env ################################
PREFIX       = /usr
LIB          = $(PREFIX)/lib/slab
INCLUDE      = $(PREFIX)/include/slab
LDCONF       = /etc/ld.so.conf.d/slab.conf
PKGCONF      = $(PREFIX)/lib/arm-linux-gnueabihf/pkgconfig/slab_uio.pc
CFLAGS       = -I`pwd`/include
SHARED_FLAGS = -shared -fPIC $(CFLAGS)
PY_FLAGS     = $(SHARED_FLAGS) $(PY_BOOST)
INSTALL_ALL  = $(LIB)/libslab_uio.so  $(INCLUDE)/uio.hpp\
							 $(LDCONF) $(PKGCONF)
#########################################################################

default: all

################################# Build #################################
all: lib/libslab_uio.so

lib/uio.o: src/uio.cpp
	mkdir -p lib
	g++ -c src/uio.cpp -o lib/uio.o $(CFLAGS)

lib/libslab_uio.so: src/uio.cpp
	mkdir -p lib
	g++ $(SHARED_FLAGS) src/uio.cpp -o lib/libslab_uio.so

#########################################################################


################################ Install ################################
install: $(INSTALL_ALL)

uninstall:
	rm -f $(INSTALL_ALL)
	ldconfig

$(LIB)/libslab_uio.so: lib/libslab_uio.so
	mkdir -p $(LIB)
	cp lib/libslab_uio.so $(LIB)/libslab_uio.so

$(INCLUDE)/uio.hpp: include/slab/uio.hpp
	mkdir -p $(PREFIX)/include/slab
	cp include/slab/uio.hpp $(INCLUDE)/uio.hpp

$(LDCONF): config/slab.conf
	mkdir -p /etc/ld.so.conf.d/
	cp config/slab.conf $(LDCONF)
	ldconfig

$(PKGCONF): config/slab_uio.pc
	mkdir -p $(PREFIX)/lib/arm-linux-gnueabihf/pkgconfig/
	cp config/slab_uio.pc $(PKGCONF)
#########################################################################


################################# Clean #################################
clean:
	rm -rf lib sample/*/main

#########################################################################
