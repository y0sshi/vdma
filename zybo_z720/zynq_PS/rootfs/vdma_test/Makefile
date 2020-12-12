################################ Set env ################################
PREFIX       = /usr
LIB          = $(PREFIX)/lib/slab
INCLUDE      = $(PREFIX)/include/slab
LDCONF       = /etc/ld.so.conf.d/slab.conf
PKGCONF      = $(PREFIX)/lib/arm-linux-gnueabihf/pkgconfig/slab_vdma.pc
CFLAGS       = -I`pwd`/include
SRCS         = src/vdma.cpp src/video/VideoOutput.cpp \
							 src/bsp/standalone.c src/bsp/xaxivdma.c src/bsp/xclk_wiz.c \
							 src/bsp/xscugic.c src/bsp/xvtc.c
SHARED_FLAGS = -shared -fPIC $(CFLAGS)
PY_FLAGS     = $(SHARED_FLAGS) $(PY_BOOST)
INSTALL_ALL  = $(LIB)/libslab_vdma.so \
							 $(INCLUDE)/vdma.hpp \
							 $(INCLUDE)/video \
							 $(INCLUDE)/bsp \
							 $(LDCONF) $(PKGCONF)
#########################################################################

default : all

################################# Build #################################
all: lib/libslab_vdma.so

lib/libslab_vdma.so : $(SRCS)
	mkdir -p lib
	g++ $(SHARED_FLAGS) $(SRCS) -o lib/libslab_vdma.so

#########################################################################


################################ Install ################################
install: $(INSTALL_ALL)

uninstall:
	rm -f $(INSTALL_ALL)
	ldconfig

$(LIB)/libslab_vdma.so: lib/libslab_vdma.so
	mkdir -p $(LIB)
	cp lib/libslab_vdma.so $(LIB)/libslab_vdma.so

$(INCLUDE)/vdma.hpp : include/slab/vdma.hpp
	mkdir -p $(INCLUDE)
	cp include/slab/vdma.hpp $(INCLUDE)/vdma.hpp

$(INCLUDE)/video : include/slab/video
	mkdir -p $(INCLUDE)
	cp -r include/slab/video $(INCLUDE)/video

$(INCLUDE)/bsp : include/slab/bsp
	mkdir -p $(INCLUDE)
	cp -r include/slab/bsp $(INCLUDE)/bsp

$(LDCONF): config/slab.conf
	mkdir -p /etc/ld.so.conf.d/
	cp config/slab.conf $(LDCONF)
	ldconfig

$(PKGCONF): config/slab_vdma.pc
	mkdir -p $(PREFIX)/lib/arm-linux-gnueabihf/pkgconfig/
	cp config/slab_vdma.pc $(PKGCONF)

#########################################################################


################################# Clean #################################
clean :
	rm -rf lib

#########################################################################
