//-----------------------------------------------------------------------------
// <vdma_top>
//  - Top module of vdma_test project
//-----------------------------------------------------------------------------
// Version 1.00 (Sep. 23, 2020)
//  - initial version
//-----------------------------------------------------------------------------
// (C) 2020 Naofumi Yoshinaga. All rights reserved.
//-----------------------------------------------------------------------------

`default_nettype none

module vdma_top
	#(
		/* Clock */
		parameter integer PS_CLK_FREQ      = -1,

		/* HDMI */
		parameter integer VID_H_ACTIVE      = -1,
		parameter integer VID_H_FRONT_PORCH = -1,
		parameter integer VID_H_SYNC_WIDTH  = -1,
		parameter integer VID_H_BACK_PORCH  = -1,
		parameter integer VID_V_ACTIVE      = -1,
		parameter integer VID_V_FRONT_PORCH = -1,
		parameter integer VID_V_SYNC_WIDTH  = -1,
		parameter integer VID_V_BACK_PORCH  = -1,

		/* AXI parameters (PS-PL) */
		parameter integer C_S_AXI_DATA_WIDTH = -1,
		parameter integer C_S_AXI_ADDR_WIDTH = -1
	)
	(
		/* HDMI */
		output wire       hdmi_tx_clk_n, hdmi_tx_clk_p,
		output wire [2:0] hdmi_tx_n, hdmi_tx_p,

		/* System */
		input  wire [3:0] btn,
		input  wire [3:0] sw,
		output wire [2:0] led5, led6,
		output wire [3:0] led
	);

	/* local parameter */
	localparam integer VID_H_BLANK = VID_H_FRONT_PORCH + VID_H_SYNC_WIDTH + VID_H_BACK_PORCH;
	localparam integer VID_V_BLANK = VID_V_FRONT_PORCH + VID_V_SYNC_WIDTH + VID_V_BACK_PORCH;
	localparam integer VID_H_FRAME = VID_H_ACTIVE + VID_H_BLANK;
	localparam integer VID_V_FRAME = VID_V_ACTIVE + VID_V_BLANK;
	localparam integer VID_PIXELS  = VID_H_ACTIVE * VID_V_ACTIVE;
	localparam integer LSD_BUFSIZE = 4096;

	/* clock and reset */
	wire ps_clk;     // 50.00 MHz (ps-pl, motor)
	wire rst;
	reg [3:0] sys_reset_sync_regs = 4'h0;
	always @(posedge ps_clk) begin
		sys_reset_sync_regs <= {sys_reset_sync_regs[2:0], !btn[0]};
	end
	assign rst = sys_reset_sync_regs[3];
	
	/* Video Direct Memory Access */
	wire PixelClk, SerialClk, vid_rstn;
	wire vid_in_hsync, vid_in_vsync, vid_in_VDE;
	wire [$clog2(VID_H_FRAME)-1:0] vid_in_hcnt;
	wire [$clog2(VID_V_FRAME)-1:0] vid_in_vcnt;
	wire vid_out_hsync, vid_out_vsync, vid_out_VDE;
	wire [$clog2(VID_H_FRAME)-1:0] vid_out_hcnt;
	wire [$clog2(VID_V_FRAME)-1:0] vid_out_vcnt;
	wire vid_out_hblank, vid_out_vblank, vid_out_field;
	wire [7:0] vid_in_r, vid_in_g, vid_in_b;
	wire [7:0] vid_out_r, vid_out_g, vid_out_b;

	/* Video Sync to Count */
	vid_sync2cnt #(
		.H_ACTIVE      (VID_H_ACTIVE     ),
		.H_FRONT_PORCH (VID_H_FRONT_PORCH),
		.H_SYNC_WIDTH  (VID_H_SYNC_WIDTH ),
		.H_BACK_PORCH  (VID_H_BACK_PORCH ),
		.V_ACTIVE      (VID_V_ACTIVE     ),
		.V_FRONT_PORCH (VID_V_FRONT_PORCH),
		.V_SYNC_WIDTH  (VID_V_SYNC_WIDTH ),
		.V_BACK_PORCH  (VID_V_BACK_PORCH )
	) vid_sync2cnt_inst (
		.clk      (PixelClk    ),
		.rst      (!vid_rstn   ),
		.in_vsync (vid_in_vsync),
		.in_hsync (vid_in_hsync),
		.out_vcnt (vid_in_vcnt ),
		.out_hcnt (vid_in_hcnt )
	);
    
	/* Image Processing */
	wire [$clog2(LSD_BUFSIZE)-1:0] lsdbuf_raddr, lsdbuf_line_num;
	wire [$clog2(VID_H_FRAME)-1:0] lsdbuf_start_h, lsdbuf_end_h;
	wire [$clog2(VID_V_FRAME)-1:0] lsdbuf_start_v, lsdbuf_end_v;
	wire lsdbuf_write_protect, lsdbuf_ready;
	image_processor #(
		.DATA_WIDTH (8           ),
		.H_ACTIVE   (VID_H_ACTIVE),
		.V_ACTIVE   (VID_V_ACTIVE),
		.H_FRAME    (VID_H_FRAME ),
		.V_FRAME    (VID_V_FRAME ),
		.RAM_SIZE   (LSD_BUFSIZE )
	) image_processor_inst (
		.pixelclk                (PixelClk      ),
		.psclk                   (ps_clk        ),
		.rst                     (!vid_rstn     ),
		.sw                      (sw            ),

		/* Video input (from VDMA IP) */
		.in_data                 ({vid_in_r, vid_in_g, vid_in_b}),
		.in_vcnt                 (vid_in_vcnt   ),
		.in_hcnt                 (vid_in_hcnt   ),

		/* Video output (to HDMI) */
		.out_data                ({vid_out_r, vid_out_g, vid_out_b}),
		.out_vcnt                (vid_out_vcnt  ),
		.out_hcnt                (vid_out_hcnt  ),
		.out_hblank              (vid_out_hblank),
		.out_vblank              (vid_out_vblank),
		.out_field               (vid_out_field ),
		.out_vde                 (vid_out_VDE   ),

		/* LSD Buffer (to Userspace I/O) */
		.out_lsdbuf_line_num     (lsdbuf_line_num     ), // number of lines
		.in_lsdbuf_raddr         (lsdbuf_raddr        ),
		.in_lsdbuf_write_protect (lsdbuf_write_protect),
		.out_lsdbuf_start_v      (lsdbuf_start_v      ),
		.out_lsdbuf_start_h      (lsdbuf_start_h      ),
		.out_lsdbuf_end_v        (lsdbuf_end_v        ),
		.out_lsdbuf_end_h        (lsdbuf_end_h        ),
		.out_lsdbuf_ready        (lsdbuf_ready        )
	);

	/* Count to Video Sync */
	vid_cnt2sync #(
		.H_ACTIVE      (VID_H_ACTIVE     ),
		.H_FRONT_PORCH (VID_H_FRONT_PORCH),
		.H_SYNC_WIDTH  (VID_H_SYNC_WIDTH ),
		.H_BACK_PORCH  (VID_H_BACK_PORCH ),
		.V_ACTIVE      (VID_V_ACTIVE     ),
		.V_FRONT_PORCH (VID_V_FRONT_PORCH),
		.V_SYNC_WIDTH  (VID_V_SYNC_WIDTH ),
		.V_BACK_PORCH  (VID_V_BACK_PORCH )
	) vid_cnt2sync_inst (
		.clk                      (PixelClk     ),
		.rst                      (!vid_rstn    ),
		.in_vcnt                  (vid_out_vcnt   ),
		.in_hcnt                  (vid_out_hcnt   ),
		.out_vsync                (vid_out_vsync  ),
		.out_hsync                (vid_out_hsync  )
	);

	/* Zynq Interface */
	zynq_ps_interface #(
		.H_FRAME            (VID_H_FRAME       ),
		.V_FRAME            (VID_V_FRAME       ),
		.LSD_BUFSIZE        (LSD_BUFSIZE       ),
		.C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH)
	)
	zynq_ps_interface_inst0 (
		/* Clock */
		.ps_clk    (ps_clk), // 50 MHz

		/* Video Direct Memory Access */
		.PixelClk      (PixelClk                         ),
		.SerialClk     (SerialClk                        ),
		.vid_rstn      (vid_rstn                         ),
		.vid_out_VDE   (vid_in_VDE                       ),
		.vid_out_hsync (vid_in_hsync                     ),
		.vid_out_vsync (vid_in_vsync                     ),
		.vid_out_data  ({vid_in_r, vid_in_g, vid_in_b}   ),
		//.vid_in_VDE    (vid_out_VDE                      ),
		//.vid_in_hsync  (vid_out_hsync                    ),
		//.vid_in_vsync  (vid_out_vsync                    ),
		//.vid_in_data   ({vid_out_r, vid_out_g, vid_out_b}),

		/* LSD Buffer (to Userspace I/O) */
		.out_lsdbuf_raddr         (lsdbuf_raddr        ),
		.out_lsdbuf_write_protect (lsdbuf_write_protect),
		.in_lsdbuf_line_num       (lsdbuf_line_num     ),
		.in_lsdbuf_start_v        (lsdbuf_start_v      ),
		.in_lsdbuf_start_h        (lsdbuf_start_h      ),
		.in_lsdbuf_end_v          (lsdbuf_end_v        ),
		.in_lsdbuf_end_h          (lsdbuf_end_h        ),
		.in_lsdbuf_ready          (lsdbuf_ready        ),

		/* debug */
		.led       (led),
		.sw        (sw)
	);
	
	rgb2dvi_0 rgb2dvi_inst (
		.PixelClk    (PixelClk                         ),
		.SerialClk   (SerialClk                        ),
		.aRst_n      (vid_rstn                         ),
		.vid_pData   ({vid_out_r, vid_out_b, vid_out_g}),
		.vid_pVDE    (vid_out_VDE                      ),
		.vid_pHSync  (vid_out_hsync                    ),
		.vid_pVSync  (vid_out_vsync                    ),
		.TMDS_Data_p (hdmi_tx_p                        ),
		.TMDS_Data_n (hdmi_tx_n                        ),
		.TMDS_Clk_p  (hdmi_tx_clk_p                    ),
		.TMDS_Clk_n  (hdmi_tx_clk_n                    )
	);
	
	/* Block RAM */
	//localparam integer VID_PIXELS = VID_H_ACTIVE * VID_V_ACTIVE;
	//reg [$clog2(VID_PIXELS)-1:0] bram_addr;
	//wire [23:0] bram_rgb;
	//reg bram_r, bram_g, bram_b;
	//BRAM #(
	//   .DATA_WIDTH (24),
	//   .FIFO_WIDTH (VID_PIXELS)
	//) bram_inst(
	//   .clk   (PixelClk),
	//   .n_rst (!btn[0] ),
	//   .ena   (),
	//   .enb   (1'b1),
	//   .wea   (),
	//   .addra (),
	//   .addrb (bram_addr),
	//   .dia   (),
	//   .doa   (),
	//   .dob   (bram_rgb)
	//);
	//always @(posedge PixelClk) begin
	//   if (!btn[0]) begin
	//       bram_addr <= 0;
	//   end
	//   else begin
	//       bram_addr <= (bram_addr == VID_PIXELS-1) ? 0 : bram_addr + 1;
	//   end
	//end
    //
	//always @(posedge PixelClk) begin
	//   bram_r <= (bram_rgb[23:16] == 8'hff);
	//   bram_g <= (bram_rgb[15: 8] == 8'hff);
	//   bram_b <= (bram_rgb[ 7: 0] == 8'hff);
	//end
	
	//assign led[3:2]  = {lsdbuf_write_protect, lsdbuf_ready};
	assign led5 = {vid_out_r[7], vid_out_g[7], vid_out_b[7]};
	//assign led5 = {bram_r, bram_g, bram_b};
	assign led6 = {vid_in_r[7], vid_in_g[7], vid_in_b[7]};

endmodule
`default_nettype wire
