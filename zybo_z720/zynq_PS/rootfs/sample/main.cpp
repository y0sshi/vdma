#include "lsd_test.hpp"
#include <slab/vdma.hpp>
#include <slab/bsp/xparameters.h>
#include <thread>

int main(int argc, char *argv[]) {
	/* check argument */
	if (argc < 2) {
		std::cout << "argument error" << std::endl;
		return -1;
	}

	/* set resolution and framerate */
	slab::Resolution resolution = slab::Resolution::R640_480_60_NN; // 640x480, 60 fps

	/* generate threads */
	std::thread th1(slab::Video_VDMA, argv[1], resolution);
	std::thread th2(slab::UIO_LSD);

	/* join threads */
	th1.join();
	th2.join();

	return 0;
}


