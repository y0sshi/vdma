#include <slab/vdma.hpp>
#include <slab/bsp/xparameters.h>
#include <chrono>

#define MEM_BASE_ADDR (XPAR_DDR_MEM_BASEADDR + 0x0A000000)

int main(int argc, char *argv[]) {
	slab::Resolution resolution = slab::Resolution::R1920_1080_60_PP;
	uint32_t width      = slab::timing[static_cast<int>(resolution)].h_active;
	uint32_t height     = slab::timing[static_cast<int>(resolution)].v_active;
	uint32_t pixels     = width * height;
	uint32_t frameBytes = width * height * sizeof(slab::bgr_t);
	slab::VDMA vdma(MEM_BASE_ADDR, resolution);

	/* start read pixel from Memory(frame-buffer) to PL-device */
	vdma.Vdma_StartRead();
	
	/* check argument */
	if (argc < 2) {
		std::cout << "argument error" << std::endl;
		return -1;
	}
	std::string filename = argv[1];

	/* open vid-file */
	FILE *fp;
	if ((fp = fopen(filename.c_str(), "rb")) == NULL) {
		printf("cannot open %s\n", filename.c_str());
		return -1;
	}

	/* read header information */
	int w, h, frames;
	double fps;
	fscanf(fp, "%d %d\n%d\n%lf\n", &w, &h, &frames, &fps);
	printf("FRAME_SIZE  : %d x %d\n", w, h);
	printf("FRAME_COUNT : %d\n", frames);
	printf("FRAME_RATE  : %lf\n", fps);

	/* set frame to RAM (vid-file -> RAM) */
	std::chrono::system_clock::time_point  start, end;
	end = std::chrono::system_clock::now();
	slab::bgr_t *frame = new slab::bgr_t[pixels];
	for (int i=0; i<frames; i++) {
		start = end;

		fread(frame, sizeof(slab::bgr_t), pixels, fp);
		vdma.set_framebuffer(frame, 0);

		end = std::chrono::system_clock::now();
		printf(" frame rates : %2.6lf [fps] \r", (1000.0 / std::chrono::duration_cast<std::chrono::milliseconds>(end-start).count()));
		fflush(stdout);
	}

	/* open vid-file */
	fclose(fp);

	return 0;
}
