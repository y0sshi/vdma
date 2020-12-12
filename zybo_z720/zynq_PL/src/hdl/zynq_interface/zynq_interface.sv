//-----------------------------------------------------------------------------
// <zynq_interface>
//  - zynq interface module (PS-PL communication)
//-----------------------------------------------------------------------------
// Version 1.00 (Sep. 23, 2020)
//  - Added 32 slave-wires
//  - Other minor refinements
//-----------------------------------------------------------------------------
// (C) 2020 Naofumi Yoshinaga. All rights reserved.
//-----------------------------------------------------------------------------

`default_nettype none

module zynq_ps_interface
	#(
		/* Simple-LSD */
		parameter integer CAM_IMAGE_HEIGHT  = -1,
		parameter integer CAM_IMAGE_WIDTH   = -1,
		parameter integer CAM_FRAME_HEIGHT  = -1,
		parameter integer CAM_FRAME_WIDTH   = -1,
		parameter integer LSDBUF_RAM_SIZE   = -1,

		/* PS-PL */
		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH = -1,
		// Width of S_AXI address bus
		parameter integer C_S_AXI_ADDR_WIDTH = -1
	)
	(
		/* clock */
		output wire ps_clk,
		

		/* Video Direct Memory Access */
		output wire PixelClk,
		output wire SerialClk,
		output wire vid_rstn,
		output wire vid_hsync,
		output wire vid_vsync,
		output wire vid_VDE,
		output wire [23:0] vid_data,

		/* Test */
		input  wire [3:0]  sw,
		output reg  [3:0]  led
	);

	/* local parameters */
	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer OPT_MEM_ADDR_BITS = 4;

	/* wires of zynq_processor */
	reg  [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
	wire [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
	wire [C_S_AXI_DATA_WIDTH-1:0] slv_wire00, slv_wire01, slv_wire02, slv_wire03;
	wire [C_S_AXI_DATA_WIDTH-1:0] slv_wire04, slv_wire05, slv_wire06, slv_wire07;
	wire [C_S_AXI_DATA_WIDTH-1:0] slv_wire08, slv_wire09, slv_wire10, slv_wire11;
	wire [C_S_AXI_DATA_WIDTH-1:0] slv_wire12, slv_wire13, slv_wire14, slv_wire15;
	wire [C_S_AXI_DATA_WIDTH-1:0] slv_wire16, slv_wire17, slv_wire18, slv_wire19;
	wire [C_S_AXI_DATA_WIDTH-1:0] slv_wire20, slv_wire21, slv_wire22, slv_wire23;
	wire [C_S_AXI_DATA_WIDTH-1:0] slv_wire24, slv_wire25, slv_wire26, slv_wire27;
	wire [C_S_AXI_DATA_WIDTH-1:0] slv_wire28, slv_wire29, slv_wire30, slv_wire31;

	/* Block Design */
	block_design_wrapper block_design_inst0 (
		/* zynq clock (50 MHz) */
		//.FCLK_CLK0 (ps_clk),
		

		/* Video Direct Memory Access */
		.PixelClk                (PixelClk ),
		.SerialClk               (SerialClk),
		.vid_locked              (vid_rstn ),
		.vid_io_out_data         (vid_data ),
		.vid_io_out_hsync        (vid_hsync),
		.vid_io_out_vsync        (vid_vsync),
		.vid_io_out_active_video (vid_VDE  ),

		/* wires of zynq_processor */
		.axi_araddr   (axi_araddr  ),
		.reg_data_out (reg_data_out),
		.slv_wire00   (slv_wire00  ),
		.slv_wire01   (slv_wire01  ),
		.slv_wire02   (slv_wire02  ),
		.slv_wire03   (slv_wire03  ),
		.slv_wire04   (slv_wire04  ),
		.slv_wire05   (slv_wire05  ),
		.slv_wire06   (slv_wire06  ),
		.slv_wire07   (slv_wire07  ),
		.slv_wire08   (slv_wire08  ),
		.slv_wire09   (slv_wire09  ),
		.slv_wire10   (slv_wire10  ),
		.slv_wire11   (slv_wire11  ),
		.slv_wire12   (slv_wire12  ),
		.slv_wire13   (slv_wire13  ),
		.slv_wire14   (slv_wire14  ),
		.slv_wire15   (slv_wire15  ),
		.slv_wire16   (slv_wire16  ),
		.slv_wire17   (slv_wire17  ),
		.slv_wire18   (slv_wire18  ),
		.slv_wire19   (slv_wire19  ),
		.slv_wire20   (slv_wire20  ),
		.slv_wire21   (slv_wire21  ),
		.slv_wire22   (slv_wire22  ),
		.slv_wire23   (slv_wire23  ),
		.slv_wire24   (slv_wire24  ),
		.slv_wire25   (slv_wire25  ),
		.slv_wire26   (slv_wire26  ),
		.slv_wire27   (slv_wire27  ),
		.slv_wire28   (slv_wire28  ),
		.slv_wire29   (slv_wire29  ),
		.slv_wire30   (slv_wire30  ),
		.slv_wire31   (slv_wire31  )
	);

	/* PS <- PL */
	always @(*) begin
		// Address decoding for reading registers
		case ( axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
			5'h00   : reg_data_out <= slv_wire00;
			5'h01   : reg_data_out <= slv_wire01;
			5'h02   : reg_data_out <= slv_wire02;
			5'h03   : reg_data_out <= slv_wire03;
			5'h04   : reg_data_out <= slv_wire04;
			5'h05   : reg_data_out <= slv_wire05;
			5'h06   : reg_data_out <= slv_wire06;
			5'h07   : reg_data_out <= slv_wire07;
			5'h08   : reg_data_out <= slv_wire08;
			5'h09   : reg_data_out <= slv_wire09;
			5'h0A   : reg_data_out <= slv_wire10;
			5'h0B   : reg_data_out <= slv_wire11;
			5'h0C   : reg_data_out <= slv_wire12;
			5'h0D   : reg_data_out <= slv_wire13;
			5'h0E   : reg_data_out <= slv_wire14;
			5'h0F   : reg_data_out <= slv_wire15;
			5'h10   : reg_data_out <= slv_wire16;
			5'h11   : reg_data_out <= slv_wire17;
			5'h12   : reg_data_out <= slv_wire18;
			5'h13   : reg_data_out <= slv_wire19;
			5'h14   : reg_data_out <= slv_wire20;
			5'h15   : reg_data_out <= slv_wire21;
			5'h16   : reg_data_out <= slv_wire22;
			5'h17   : reg_data_out <= slv_wire23;
			5'h18   : reg_data_out <= slv_wire24;
			5'h19   : reg_data_out <= slv_wire25;
			5'h1A   : reg_data_out <= slv_wire26;
			5'h1B   : reg_data_out <= slv_wire27;
			5'h1C   : reg_data_out <= slv_wire28;
			5'h1D   : reg_data_out <= slv_wire29;
			5'h1E   : reg_data_out <= slv_wire30;
			5'h1F   : reg_data_out <= {28'd0, sw}; // sw_in
			default : reg_data_out <= 32'h0;
		endcase
	end

	/* PS -> PL */
	always @(posedge ps_clk) begin
		// <= slv_wire0;
		// <= slv_wire1;
		// <= slv_wire2;
		// <= slv_wire3;
		// <= slv_wire4;
		// <= slv_wire5;
		// <= slv_wire6;
		// <= slv_wire7;
		// <= slv_wire8;
		// <= slv_wire9;
		// <= slv_wire10;
		// <= slv_wire11;
		// <= slv_wire12;
		// <= slv_wire13;
		// <= slv_wire14;
		// <= slv_wire15;
		// <= slv_wire16;
		// <= slv_wire17;
		// <= slv_wire18;
		// <= slv_wire19;
		// <= slv_wire20;
		// <= slv_wire21;
		// <= slv_wire22;
		// <= slv_wire23;
		// <= slv_wire24;
		// <= slv_wire25;
		// <= slv_wire26;
		// <= slv_wire27;
		// <= slv_wire28;
		// <= slv_wire29;
		// <= slv_wire30;
		led <= slv_wire31[3:0];
	end
endmodule
`default_nettype wire
