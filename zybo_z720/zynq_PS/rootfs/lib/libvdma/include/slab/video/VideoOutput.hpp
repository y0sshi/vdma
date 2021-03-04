/*
 * VideoSource.h
 *
 *  Created on: Aug 30, 2016
 *      Author: Elod
 */

#ifndef VIDEOSOURCE_H_
#define VIDEOSOURCE_H_

#include <stdint.h>
#include <stdexcept>
#include <cstring>

#include <slab/bsp/xaxivdma.h>
#include <slab/bsp/xvtc.h>
#include <slab/bsp/xclk_wiz.h>

#define STRINGIZE(x) STRINGIZE2(x)
#define STRINGIZE2(x) #x
#define LINE_STRING STRINGIZE(__LINE__)

namespace slab {
	enum class Resolution
	{
		R1920_1080_60_PP = 0,
		R1280_720_60_PP,
		R640_480_60_NN
	};

	typedef struct
	{
		enum Polarity {NEG=0, POS=1};
		Resolution res;
		uint16_t h_active, h_fp, h_sync, h_bp;
		Polarity h_pol;
		uint16_t v_active, v_fp, v_sync, v_bp;
		Polarity v_pol;
		uint32_t pclk_freq_Hz;

	} timing_t;

	timing_t const timing[] = {
		{Resolution::R1920_1080_60_PP, 1920, 88, 44, 148, timing_t::POS, 1080, 4, 5, 36, timing_t::POS, 148500000},
		{Resolution::R1280_720_60_PP, 1280, 110, 40, 220, timing_t::POS, 720, 5, 5, 20, timing_t::POS, 74250000},
		{Resolution::R640_480_60_NN, 640, 16, 96, 48, timing_t::NEG, 480, 10, 2, 33, timing_t::NEG, 25000000}
	};

	class VideoOutput
	{
		public:
			VideoOutput(u32 VTC_dev_id, u32 clkwiz_dev_id);
			void reset();
			void configure(Resolution res);
			void enable();
			~VideoOutput() = default;
		private:
			XVtc sVtc_;
			XClk_Wiz sClkWiz_;
	};

} /* namespace slab */

#endif /* VIDEOSOURCE_H_ */
