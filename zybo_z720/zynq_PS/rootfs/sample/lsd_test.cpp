#include <opencv4/opencv2/core.hpp>
#include <opencv4/opencv2/opencv.hpp>
#include <string>
#include <chrono>
#include <slab/vdma.hpp>
#include <slab/uio.hpp>
#include <slab/bsp/xparameters.h>
#include "lsd_test.hpp"

namespace slab {
	bool thread_flag = true;
	UIO uio("/dev/uio0");

	void draw_lines(cv::Mat& img, const int W, const int H, const int line_num, Line_t *lines) {
		img = cv::Scalar(0,0,0);
		for (int i=0; i<line_num; i++) {
			cv::line(img, cv::Point(lines[i].start_h, lines[i].start_v), cv::Point(lines[i].end_h, lines[i].end_v), cv::Scalar(255,255,225), 1);
		}
	}

	void UIO_LSD() {
		/* initialize */
		cv::Mat line_img(cv::Size(WIDTH, HEIGHT), CV_8UC1);
		std::chrono::system_clock::time_point  start, end;
		Line_t line; 
		uint32_t num_of_lines;

		cv::namedWindow("line frame buffer", cv::WINDOW_AUTOSIZE | cv::WINDOW_FREERATIO);

		printf("LSDBUF (result)\n");
		while (thread_flag) {

			/* fetch line-frame from LSDBUF(PL) */
			line_img = cv::Scalar(0,0,0);

			uio.write(WRITE_LSDBUF_PROTECT, 0x1);           // set write_protect
			while (!uio.read(READ_LSDBUF_READY));           // wait buffer-ready
			num_of_lines = uio.read(READ_LSDBUF_LINE_NUM);  // get number of lines
			for (int i=0; i<num_of_lines; i++) {
				//start = std::chrono::system_clock::now();

				uio.write(WRITE_LSDBUF_RADDR, i);              // set read-address
				line.start_h = uio.read(READ_LSDBUF_START_H); // read line-information
				line.start_v = uio.read(READ_LSDBUF_START_V);
				line.end_h   = uio.read(READ_LSDBUF_END_H);
				line.end_v   = uio.read(READ_LSDBUF_END_V);

				//end = std::chrono::system_clock::now();
				//printf("  frame_time : %lf [s]\r", std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count() / 1000000000.0);
				//fflush(stdout);

				cv::line(line_img, cv::Point(line.start_h, line.start_v), cv::Point(line.end_h, line.end_v), cv::Scalar(255,255,225), 1);
			}

			uio.write(WRITE_LSDBUF_PROTECT, 0x0);           // unset write_protect


			/* display window */
			//draw_lines(line_img, WIDTH, HEIGHT, num_of_lines, lines);
			cv::imshow("line frame buffer", line_img);
			char key = cv::waitKey(150);
			switch (key) {
				case 'n': // n : get number of lines
					printf("num of lines: %d\n", num_of_lines);
					break;
				case 's': // s : Stop
					while (true) {
						if (cv::waitKey(0)) {
							break;
						}
					}
					break;
				case 'q': // q : Quit
					thread_flag = false;
					break;
				default: break;
			}

		}
		cv::destroyAllWindows();
		printf("\n");
	}

	void Video_VDMA(std::string filename, Resolution resolution) {
		/* information of image */
		uint32_t width      = timing[static_cast<int>(resolution)].h_active;
		uint32_t height     = timing[static_cast<int>(resolution)].v_active;
		uint32_t pixels     = width * height;
		uint32_t frameBytes = width * height * sizeof(bgr_t);

		/* read image from FrameBuffer(DRAM) to PL-device */
		VDMA vdma(MEM_BASE_ADDR_R, MEM_BASE_ADDR_W, resolution);
		vdma.Vdma_StartRead();

		/* OpenCV */
		cv::Mat frame;
		cv::VideoCapture cap;
		cap.open(filename);
		if (!cap.isOpened()) {
			printf("could not open %s\n", filename.c_str());
			return ;
		}
		uint32_t frames, fps;
		frames = cap.get(cv::CAP_PROP_FRAME_COUNT);
		fps    = cap.get(cv::CAP_PROP_FPS);
		printf("Frames : %d, fps : %d\n", frames, fps);

		/* set frame to RAM (vid-file -> RAM) */
		std::chrono::system_clock::time_point  start, end;

		start = std::chrono::system_clock::now();
		for (int i=0; i<frames; i++) {
			/* capture frame from video */
			cap >> frame;
			if (frame.empty()) break;

			/* set frame to DRAM_framebuffer */
			vdma.set_framebuffer((bgr_t*)frame.data, 0);
		}
		end  = std::chrono::system_clock::now();
		thread_flag = false;

		double time = (double)std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count() / 1000.0;
		printf("VDMA\n");
		printf("  total time : %lf [s], spf : %lf [s], fps : %lf [fps]\n", time, (time/frames),  (frames / time));
	}
};

