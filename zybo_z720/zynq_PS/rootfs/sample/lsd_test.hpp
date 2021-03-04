#ifndef _LSD_TEST_H_
#define _LSD_TEST_H_

#include <opencv4/opencv2/opencv.hpp>
#include <stdint.h>
#include <string>
#include <slab/vdma.hpp>
#include <slab/uio.hpp>

#define WIDTH  640
#define HEIGHT 480
#define MAXNUM_OF_LINES 4096

/* index of slave register */
#define READ_LSDBUF_LINE_NUM 0
#define READ_LSDBUF_READY    1
#define READ_LSDBUF_START_H  2
#define READ_LSDBUF_START_V  3
#define READ_LSDBUF_END_H    4
#define READ_LSDBUF_END_V    5
#define WRITE_LSDBUF_PROTECT 0
#define WRITE_LSDBUF_RADDR   1

/* FrameBuffer(DRAM) BASE_ADDR */
#define MEM_BASE_ADDR_R (XPAR_DDR_MEM_BASEADDR + 0x0A000000)
#define MEM_BASE_ADDR_W (XPAR_DDR_MEM_BASEADDR + 0x0C000000)

namespace slab {
	typedef struct {
		uint32_t start_h, start_v, end_h, end_v;
	} Line_t;

	void draw_lines(cv::Mat&, const int, const int, const int, Line_t*);
	void UIO_LSD();
	void Video_VDMA(std::string, slab::Resolution);
};

#endif // _LSD_TEST_H_
