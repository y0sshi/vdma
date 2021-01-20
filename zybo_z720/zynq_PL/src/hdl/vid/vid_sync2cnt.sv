`default_nettype none

module vid_sync2cnt
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
		input  wire                       in_vsync,
		input  wire                       in_hsync,
		output wire [$clog2(V_FRAME)-1:0] out_vcnt,
		output wire [$clog2(H_FRAME)-1:0] out_hcnt
	);

	/* buffer */
	reg prev_vsync, prev_hsync;
	always @(posedge clk) begin
		if (rst) begin
			prev_vsync <= 1'b0;
			prev_hsync <= 1'b0;
		end
		else begin
			prev_vsync <= in_vsync;
			prev_hsync <= in_hsync;
		end
	end

	/* hcnt */
	reg [$clog2(H_FRAME)-1:0] hcnt;
	always @(posedge clk) begin
		if (rst) begin
			hcnt <= 'd0;
		end
		else begin
			if (!prev_hsync && in_hsync) begin
				hcnt <= H_ACTIVE + H_FRONT_PORCH + 1;
			end
			else begin
				hcnt <= (hcnt == H_FRAME - 1) ? 'd0 : hcnt + 1;
			end
		end
	end

	/* vcnt */
	reg [$clog2(V_FRAME)-1:0] vcnt;
	always @(posedge clk) begin
		if (rst) begin
			vcnt <= 'd0;
		end
		else begin
			if (!prev_vsync && in_vsync) begin
				vcnt <= V_ACTIVE + V_FRONT_PORCH;
			end
			else if (hcnt == H_FRAME - 1) begin
				vcnt <= (vcnt == V_FRAME - 1) ? 'd0 : vcnt + 1;
			end
		end
	end
	assign out_vcnt = vcnt;
	assign out_hcnt = hcnt;

endmodule

`default_nettype wire
