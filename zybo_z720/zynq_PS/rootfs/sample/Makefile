CFLAGS  =  -lpthread `pkg-config --libs slab_vdma slab_uio opencv4`

all : main

main : main.cpp lsd_test.cpp
	g++ main.cpp lsd_test.cpp -o main $(CFLAGS)

clean :
	rm -f main
