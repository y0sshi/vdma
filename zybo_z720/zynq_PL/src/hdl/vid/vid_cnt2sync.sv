`default_nettype none

module vid_cnt2sync
	#(
		parameter integer H_ACTIVE      = -1,
		parameter integer H_FRONT_PORCH = -1,
		parameter integer H_SYNC_WIDTH  = -1,
		parameter integer H_BACK_PORCH  = -1,
		parameter integer V_ACTIVE      = -1,
		parameter integer V_FRONT_PORCH = -1,
		parameter integer V_SYNC_WIDTH  = -1,
		parameter integer V_BACK_PORCH  = -1,
		parameter integer H_BLANK       = H_FRONT_PORCH + H_SYNC_WIDTH + H_BACK_PORCH,
		parameter integer H_FRAME       = H_ACTIVE + H_BLANK,
		parameter integer V_BLANK       = V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH,
		parameter integer V_FRAME       = V_ACTIVE + V_BLANK
	)
	(
		input  wire                       clk,
		input  wire                       rst,
		input  wire [$clog2(V_FRAME)-1:0] in_vcnt,
		input  wire [$clog2(H_FRAME)-1:0] in_hcnt,
		output wire                       out_vsync,
		output wire                       out_hsync
	);

	/* hsync */
	reg hsync;
	always @(posedge clk) begin
		if (rst) begin
			hsync <= 1'b1;
		end
		else begin
			if      (in_hcnt == H_ACTIVE + H_FRONT_PORCH - 1) begin
				hsync <= 1'b0;
			end
			else if (in_hcnt == H_ACTIVE + H_FRONT_PORCH + H_SYNC_WIDTH - 1) begin
				hsync <= 1'b1;
			end
		end
	end

	/* vsync */
	reg vsync;
	always @(posedge clk) begin
		if (rst) begin
			vsync <= 1'b1;
		end
		else begin
		  if (in_hcnt == H_ACTIVE + H_FRONT_PORCH -1) begin
			if      (in_vcnt == V_ACTIVE + V_FRONT_PORCH) begin
				vsync <= 1'b0;
			end
			else if (in_vcnt == V_ACTIVE + V_FRONT_PORCH + V_SYNC_WIDTH) begin
				vsync <= 1'b1;
			end
		  end
		end
	end

	assign out_vsync = vsync;
	assign out_hsync = hsync;

endmodule
