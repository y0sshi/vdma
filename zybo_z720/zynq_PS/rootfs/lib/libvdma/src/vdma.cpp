//-----------------------------------------------------------------------------
// <vdma.cpp>
//  - Defined functions of slab::VDMA class
//-----------------------------------------------------------------------------
// Version 1.00 (Nov. 22, 2020)
//  - Added definition for functions of slab::VDMA class
//-----------------------------------------------------------------------------
// (C) 2020 Naofumi Yoshinaga. All rights reserved.
//-----------------------------------------------------------------------------

#include <slab/vdma.hpp>

namespace slab {
	VDMA::VDMA(uint32_t base_addr_r, uint32_t base_addr_w, Resolution res) :
		base_addr_r_ (base_addr_r                                    ),
		base_addr_w_ (base_addr_w                                    ),
		res_         (res                                            ),
		width_       (timing[static_cast<int>(res_)].h_active        ),
		height_      (timing[static_cast<int>(res_)].v_active        ),
		pixels_      (width_ * height_                               ),
		frameBytes_  (pixels_ * sizeof(bgr_t)                        ),
		irpt_ctl_    (XPAR_PS7_SCUGIC_0_DEVICE_ID                    ),
		vid_         (XPAR_VTC_DEVICE_ID, XPAR_VIDEO_DYNCLK_DEVICE_ID),
		vdma_driver_ (
				XPAR_AXIVDMA_0_DEVICE_ID,
				base_addr_w, // write
				base_addr_r, // read
				irpt_ctl_,
				XPAR_FABRIC_AXI_VDMA_0_MM2S_INTROUT_INTR,
				XPAR_FABRIC_AXI_VDMA_0_S2MM_INTROUT_INTR
				)
	{
		/* map frame-buffer region to memory */
		map_framebuffer();
	}

	VDMA::~VDMA() {
		/* unmap frame-buffer region from memory */
		unmap_framebuffer();
	}

	void VDMA::init() {
	}

	void VDMA::Vdma_StartRead() {
		/* Video start */
		{
			std::cout << "[VDMA Read]  : stage 1" << std::endl;
			vid_.reset();
			vdma_driver_.resetRead();
		}

		{
			std::cout << "[VDMA Read]  : stage 2" << std::endl;
			vid_.configure(res_);
			vdma_driver_.configureRead(width_, height_);
		}

		{
			std::cout << "[VDMA Read]  : stage 3" << std::endl;
			vid_.enable();
			vdma_driver_.enableRead();
		}
	}

	void VDMA::Vdma_StartWrite() {
		{
			std::cout << "[VDMA Write] : stage 1" << std::endl;
			vdma_driver_.resetWrite();
		}

		{
			std::cout << "[VDMA Write] : stage 2" << std::endl;
			vdma_driver_.configureWrite(width_, height_);
		}

		{
			std::cout << "[VDMA Write] : stage 3" << std::endl;
			vdma_driver_.enableWrite();
		}
	}

	void VDMA::map_framebuffer() {
		if((fd_ = open("/dev/mem", O_RDWR | O_SYNC)) == -1) FATAL;
		frame_buf_r_ = (bgr_t*)mmap(0, frameBytes_, PROT_READ | PROT_WRITE, MAP_SHARED, fd_, base_addr_r_ & ~MAP_MASK);
		frame_buf_w_ = (bgr_t*)mmap(0, frameBytes_, PROT_READ | PROT_WRITE, MAP_SHARED, fd_, base_addr_w_ & ~MAP_MASK);
	}

	void VDMA::unmap_framebuffer() {
		/* close memory */
		if(munmap(frame_buf_r_, frameBytes_) == -1) FATAL;
		if(munmap(frame_buf_w_, frameBytes_) == -1) FATAL;
		close(fd_);
	}

	void VDMA::set_framebuffer(const bgr_t* img, const uint8_t frame_index) {
		memcpy(frame_buf_r_ + (pixels_ * frame_index), img, frameBytes_);
	}

	void VDMA::get_framebuffer(bgr_t* img, const uint8_t frame_index) {
		memcpy(img, frame_buf_w_ + (pixels_ * frame_index), frameBytes_);
	}

	/* generate rgb pixel */
	void generate_rgb(bgr_t *img, const uint32_t img_w, const uint32_t img_h, const uint8_t frame_num) {
		for (int i=0; i<img_h; i++) {
			for (int j=0; j<img_w; j++) {
				uint32_t addr = i * img_w + j;
				img[addr].r = frame_num - j;
				img[addr].g = frame_num - i;
				img[addr].b = frame_num - (i + j);
			}
		}
	}

	/* read ppm */
	void read_ppm(bgr_t *img, const uint32_t img_w, const char *filename) {
		FILE *fp;
		char str[256];
		uint32_t loop_cnt = 0;
		uint32_t width, height;

		if ((fp = fopen(filename, "rb")) == NULL) {
			std::cout << "cannot open %s\n" << std::endl;
			return ;
		}

		while (loop_cnt < 3) {
			fgets(str, 256, fp);
			if (str[0] != '#') {
				switch (loop_cnt) {
					case 0:
						break;
					case 1:
						sscanf(str, "%d %d\n", &width, &height);
						break;
					case 2:
						break;
				}
				loop_cnt++;
			}
		}
		printf("input ppm... width:%d, height:%d\n", width, height);

		for (int i=0; i<height; i++) {
			for (int j=0; j<width; j++) {
				uint32_t addr = i * img_w + j;
				img[addr].r = fgetc(fp);
				img[addr].g = fgetc(fp);
				img[addr].b = fgetc(fp);
			}
		}
	}

	/* write ppm */
	void write_ppm(const bgr_t *img, const uint32_t img_w, const uint32_t img_h) {
		const uint32_t img_pixels = img_w * img_h;
		FILE *fp;
		if ((fp = fopen("./test.ppm", "wb")) == NULL) {
			std::cout << "cannot open ./test.ppm" << std::endl;
			return ;
		}
		fprintf(fp, "P6\n%d %d\n256\n", img_w, img_h);
		for (int i=0; i<img_pixels; i++) {
			fputc(img[i].r, fp); // r
			fputc(img[i].g, fp); // g
			fputc(img[i].b, fp); // b
		}
		fclose(fp);
	}
};


