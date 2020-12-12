ifeq ($(FILE_OFFSET),64)
CFLAGS_FILE_OFFSET = -D_FILE_OFFSET_BITS=64 -D_LARGEFILE64_SOURCE
endif
CFLAGS  = `pkg-config --libs slab_vdma` $(CFLAGS_FILE_OFFSET)

all : main

main : main.cpp
	g++ main.cpp -o main $(CFLAGS)

clean :
	rm -f main
