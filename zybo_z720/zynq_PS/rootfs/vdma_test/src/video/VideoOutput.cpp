#include <slab/video/VideoOutput.hpp>

namespace slab {
	VideoOutput::VideoOutput(u32 VTC_dev_id, u32 clkwiz_dev_id)
	{
		XVtc_Config *psVtcConfig;
		XStatus Status;

		psVtcConfig = XVtc_LookupConfig(VTC_dev_id);
		if (NULL == psVtcConfig) {
			throw std::runtime_error(__FILE__ ":" LINE_STRING);
		}

		Status = XVtc_CfgInitialize(&sVtc_, psVtcConfig, psVtcConfig->BaseAddress);
		if (Status != XST_SUCCESS) {
			throw std::runtime_error(__FILE__ ":" LINE_STRING);
		}

		XClk_Wiz_Config *psClkWizConfig;
		psClkWizConfig = XClk_Wiz_LookupConfig(clkwiz_dev_id);
		if (NULL == psClkWizConfig) {
			throw std::runtime_error(__FILE__ ":" LINE_STRING);
		}

		Status = XClk_Wiz_CfgInitialize(&sClkWiz_, psClkWizConfig, psClkWizConfig->BaseAddr);
		if (Status != XST_SUCCESS) {
			throw std::runtime_error(__FILE__ ":" LINE_STRING);
		}
		// Reset clock to hardware default
		XClk_Wiz_WriteReg(sClkWiz_.Config.BaseAddr, 0x0, 0x0000000A);
		// Wait for lock because we will need it later for initializing other IP
		while (!(XClk_Wiz_ReadReg(sClkWiz_.Config.BaseAddr, 0x4) & 0x1));

	}

	void VideoOutput::reset()
	{
		XVtc_Reset(&sVtc_);
	}

	void VideoOutput::configure(Resolution res)
	{
		size_t i;
		for (i = 0; i < sizeof(timing)/sizeof(timing[0]); i++)
		{
			if (timing[i].res == res) break;
		}

		//		Configure video clock generator first, since losing clock will reset all IP connected to it
		u32 divclk = 8;
		double mul = 33.0, clkout_div0 = 33.0;
		switch (timing[i].pclk_freq_Hz)
		{
			case 148500000:
				//Factors for 742.5 MHz
				//mul = 37.125; divclk = 5; clkout_div0 = 1.0; // video_dynclk input clock: 100 MHz
				mul = 59.375; divclk = 4; clkout_div0 = 1.0; // video_dynclk input clock:  50 MHz
				break;
			case 74250000:
				//Factors for 371.25 MHz
				//mul = 37.125; divclk = 4; clkout_div0 = 2.5; // video_dynclk input clock: 100 MHz
				mul = 37.125; divclk = 2; clkout_div0 = 2.5; // video_dynclk input clock:  50 MHz
				break;
			case 25000000:
				//Factors for 125 MHz
				//mul = 10.0; divclk = 1; clkout_div0 = 8.0; // video_dynclk input clock: 100 MHz
				mul = 20.0; divclk = 1; clkout_div0 = 8.0; // video_dynclk input clock:  50 MHz
				break;
		}
		Xil_AssertVoid(mul < 256.0); //one byte limit for integer part
		uint16_t mul_frac = (uint16_t)((mul-(uint8_t)mul)*1000);
		uint8_t mul_int = (uint8_t)mul;
		Xil_AssertVoid(mul_frac <= 875); //MMCME2 limit
		XClk_Wiz_WriteReg(sClkWiz_.Config.BaseAddr, 0x200, ((mul_frac & 0x3FF) << 16) | ((mul_int & 0xFF) << 8) | (divclk & 0xFF));

		Xil_AssertVoid(clkout_div0 < 256.0); //one byte limit for integer part
		uint16_t clkout_div0_frac = (uint16_t)((clkout_div0-(uint8_t)clkout_div0)*1000);
		uint8_t clkout_div0_int = (uint8_t)clkout_div0;
		XClk_Wiz_WriteReg(sClkWiz_.Config.BaseAddr, 0x208, ((clkout_div0_frac & 0x3FF) << 8)| (clkout_div0_int & 0xFF));

		XClk_Wiz_WriteReg(sClkWiz_.Config.BaseAddr, 0x25C, 0x00000003); //Load configuration
		while (!(XClk_Wiz_ReadReg(sClkWiz_.Config.BaseAddr, 0x4) & 0x1)); //Wait for lock


		if (i < sizeof(timing)/sizeof(timing[0]))
		{
			XVtc_Timing sTiming   = {}; //Will init to 0 (C99 6.7.8.21)
			sTiming.HActiveVideo  = timing[i].h_active;
			sTiming.HFrontPorch   = timing[i].h_fp;
			sTiming.HBackPorch    = timing[i].h_bp;
			sTiming.HSyncWidth    = timing[i].h_sync;
			sTiming.HSyncPolarity = (u16)timing[i].h_pol;
			sTiming.VActiveVideo  = timing[i].v_active;
			sTiming.V0FrontPorch  = timing[i].v_fp;
			sTiming.V0BackPorch   = timing[i].v_bp;
			sTiming.V0SyncWidth   = timing[i].v_sync;
			sTiming.VSyncPolarity = (u16)timing[i].v_pol;

			printf("  sTiming.HActiveVideo  : %d\n", sTiming.HActiveVideo);
			printf("  sTiming.HFrontPorch   : %d\n", sTiming.HFrontPorch);
			printf("  sTiming.HBackPorch    : %d\n", sTiming.HBackPorch);
			printf("  sTiming.HSyncWidth    : %d\n", sTiming.HSyncWidth);
			printf("  sTiming.HSyncPolarity : %d\n", sTiming.HSyncPolarity);
			printf("  sTiming.VActiveVideo  : %d\n", sTiming.VActiveVideo);
			printf("  sTiming.V0FrontPorch  : %d\n", sTiming.V0FrontPorch);
			printf("  sTiming.V0BackPorch   : %d\n", sTiming.V0BackPorch);
			printf("  sTiming.V0SyncWidth   : %d\n", sTiming.V0SyncWidth);
			printf("  sTiming.V1FrontPorch  : %d\n", sTiming.V1FrontPorch);
			printf("  sTiming.V1BackPorch   : %d\n", sTiming.V1BackPorch);
			printf("  sTiming.V1SyncWidth   : %d\n", sTiming.V1SyncWidth);
			printf("  sTiming.VSyncPolarity : %d\n", sTiming.VSyncPolarity);
			printf("  sTiming.Interlaced    : %d\n", sTiming.Interlaced);
			printf("\n");

			XVtc_SetGeneratorTiming(&sVtc_, &sTiming);

			printf("  sVtc_.Config.DeviceID    : 0x%04X\n", sVtc_.Config.DeviceId);
			printf("  sVtc_.Config.BaseAddress : 0x%08X\n", sVtc_.Config.BaseAddress);
			printf("  sVtc_.IsReady            : 0x%08X\n", sVtc_.IsReady);
			printf("\n");

			XVtc_RegUpdateEnable(&sVtc_);
		}
	}

	void VideoOutput::enable()
	{
		XVtc_EnableGenerator(&sVtc_);
	}
};
