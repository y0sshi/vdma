#ifndef _VDMA_H_
#define _VDMA_H_

#include <iostream>
#include <stdint.h>
#include <slab/video/AXI_VDMA.hpp>
#include <slab/video/ScuGicInterruptController.hpp>
#include <slab/video/VideoOutput.hpp>
#include <slab/bsp/xparameters.h>
#include <slab/bsp/xaxivdma.h>

namespace slab {
	typedef struct bgr_t {
		uint8_t b, g, r;
	} bgr_t;

	class VDMA {
		public:
			VDMA(uint32_t, uint32_t, Resolution);
			~VDMA();
			void init();
			void Vdma_StartRead();
			void Vdma_StartWrite();
			void set_framebuffer(const bgr_t*, const uint8_t);
			void get_framebuffer(bgr_t*, const uint8_t);
		protected:
		private:
			ScuGicInterruptController           irpt_ctl_;
			AXI_VDMA<ScuGicInterruptController> vdma_driver_;
			VideoOutput                         vid_;
			Resolution                          res_;
			uint32_t                            base_addr_r_, base_addr_w_, width_, height_, pixels_, frameBytes_;
			off_t                               fd_;
			bgr_t                               *frame_buf_r_, *frame_buf_w_; 
			void                                map_framebuffer();
			void                                unmap_framebuffer();
	};

	void generate_rgb(bgr_t *, const uint32_t , const uint32_t, uint8_t);
	void read_ppm(bgr_t *, const uint32_t, const char *);
	void write_ppm(const bgr_t *, const uint32_t, const uint32_t);
};

#endif // _VMDA_H_
