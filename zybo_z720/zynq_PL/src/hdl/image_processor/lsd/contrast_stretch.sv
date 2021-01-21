//-----------------------------------------------------------------------------
// <contrast_stretch> 
//  - Applies contrast stretching to the input image stream
//    based on the histogram of the previous frame
//    - Pixel value distribution [a, b] is stretched to [0, 2^(BIT_WIDTH)-1]
//    - If WINDOW_RANGE (r) < 100, center windowing is applied.
//      i.e. the r/2 and (100 - r/2) percentiles of all the pixels are 
//      used as a and b, respectively
//              <---------------- 100 % of pixels ---------------->
//      [before]        <--------- r % of pixels --------->
//        |-----|=======|#################################|=======|-------|
//        0    min      a                                 b      max     255
//      [after]
//        |###############################################################|
//        0                                                              255
//  - <EQUALIZE_HIST> == 0: simple linear transformation mode
//    - An input value x (a <= x <= b) will be transformed into
//      f(x) = (2^(BIT_WIDTH) - 1) * (x - a) / (b - a)
//  - <EQUALIZE_HIST> == 1: histogram equalization mode
//    - Given that the number of pixels in [0, i] is N(i),
//      the total number of pixels is T (= IMAGE_HEIGHT * IMAGE_WIDTH),
//      and C = T * (100 - r) / 200, then
//      f(x) = (2^(BIT_WIDTH) - 1) * (N(x) - C) / (T - C * 2)
//  - Latency: 2 clock cycles
//-----------------------------------------------------------------------------
// Version 1.01 (Aug. 18, 2020)
//  - Improved the table generation method
//-----------------------------------------------------------------------------
// (C) 2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns
  
module contrast_stretch
  #( parameter int BIT_WIDTH     =  8, // I/O bit width (<= 30)
     parameter int IMAGE_HEIGHT  = -1, // | image size
     parameter int IMAGE_WIDTH   = -1, // |
     parameter int FRAME_HEIGHT  = -1, //  | frame size (including sync.)
     parameter int FRAME_WIDTH   = -1, //  |
     parameter int WINDOW_RANGE  = 90, // value range for windowing (%)
     parameter int EQUALIZE_HIST =  0) // to apply histogram equalization
   ( clock, n_rst, 
     in_pixel, in_vcnt, in_hcnt, out_pixel, out_vcnt, out_hcnt );

   // the following parameters are calculated automatically -------------------
   localparam int V_BITW     = $clog2(FRAME_HEIGHT);
   localparam int H_BITW     = $clog2(FRAME_WIDTH);
   localparam int DRANGE     = 1 << BIT_WIDTH;
   localparam int TOTAL_PIXS = IMAGE_HEIGHT * IMAGE_WIDTH;
   localparam int COUNT_BITW = $clog2(TOTAL_PIXS);
   localparam int CLIP_PIXS  = (TOTAL_PIXS * (100 - WINDOW_RANGE)) / 200;
   
   // inputs / outputs --------------------------------------------------------
   input wire       	       clock, n_rst;
   input wire [BIT_WIDTH-1:0]  in_pixel;
   input wire [V_BITW-1:0]     in_vcnt;
   input wire [H_BITW-1:0]     in_hcnt;
   output wire [BIT_WIDTH-1:0] out_pixel;
   output reg [V_BITW-1:0]     out_vcnt;
   output reg [H_BITW-1:0]     out_hcnt;

   // tables ------------------------------------------------------------------
   logic [BIT_WIDTH*2-1:0]     inv_table [DRANGE];
   always_comb begin
      for(int i = 0; i < DRANGE; i = i + 1)
	inv_table[i] = (($pow(2.0, BIT_WIDTH) - 1.0) / i) * 
		  $pow(2.0, BIT_WIDTH);
   end
   
   // state register ----------------------------------------------------------
   reg [1:0] 		       state;
   
   // RAM for saving histogram ------------------------------------------------
   reg 			       hst_wr_en;
   reg [BIT_WIDTH-1:0] 	       hst_wr_addr;
   reg [BIT_WIDTH-1:0] 	       hst_rd_addr;
   wire [COUNT_BITW-1:0]       hst_rd_data;
   ram_sc
     #( .WORD_SIZE(COUNT_BITW), .RAM_SIZE(DRANGE), .FORWARD(1) )
   hst_ram
     (  .clock(clock),      .wr_en(hst_wr_en),    .wr_addr(hst_wr_addr), 
	.wr_data((state < 3) ? (hst_rd_data + 1'b1) : {COUNT_BITW{1'b0}}),
	.rd_addr((state < 1) ? in_pixel : hst_rd_addr),
	.rd_data(hst_rd_data)                                           );
   
   // RAM for conversion table ------------------------------------------------
   reg 			       ctb_wr_en;
   reg [BIT_WIDTH-1:0] 	       ctb_wr_addr;
   reg [BIT_WIDTH-1:0] 	       ctb_wr_data;
   wire [BIT_WIDTH-1:0]        ctb_rd_data;
   ram_sc
     #( .WORD_SIZE(BIT_WIDTH), .RAM_SIZE(DRANGE), .FORWARD(0) )
   ctb_ram
     (  .clock(clock),         .wr_en(ctb_wr_en),    
	.wr_addr(ctb_wr_addr), .wr_data(ctb_wr_data),
	.rd_addr(in_pixel),    .rd_data(ctb_rd_data)  );

   // state control -----------------------------------------------------------
   always_ff @(posedge clock) begin
      if(!n_rst) begin
	 state <= 0;
      end
      // [0] counts pixels
      else if(state == 0) begin
	 if((in_vcnt == (IMAGE_HEIGHT - 1)) && (in_hcnt == (IMAGE_WIDTH - 1)))
	   state <= 1;
      end
      // [1] analyzes statistics
      else if(state == 1) begin
	 if(hst_rd_addr == (DRANGE - 1))
	   state <= 2;
      end
      // [2] updates conversion table
      else if(state == 2) begin
	 if(ctb_wr_addr == (DRANGE - 1))
	   state <= 3;
      end
      // [3] clears histogram
      else if(state == 3) begin
	 if(hst_wr_addr == (DRANGE - 1))
	   state <= 0;
      end
   end
   
   // histogram RAM control ---------------------------------------------------
   always_ff @(posedge clock) begin
      if(!n_rst) begin
	 hst_wr_en   <= 0;
      end
      else if(state == 0) begin
	 hst_wr_en   <= (in_vcnt < IMAGE_HEIGHT) && (in_hcnt < IMAGE_WIDTH);
	 hst_wr_addr <= in_pixel;
	 hst_rd_addr <= 0;
      end
      else if(state == 1) begin
	 hst_wr_en   <= 0;
	 hst_rd_addr <= hst_rd_addr + 1;
      end
      else if(state == 2) begin
	 if(ctb_wr_addr == (DRANGE - 1)) begin
	    hst_wr_en   <= 1;
	    hst_wr_addr <= 0;
	 end
      end
      else if(state == 3) begin
	 hst_wr_addr <= hst_wr_addr + 1;
	 if(hst_wr_addr == (DRANGE - 1))
	   hst_wr_en <= 0;
      end
   end

   // accumulates the number of pixels ----------------------------------------
   reg                         counting;
   reg [COUNT_BITW-1:0]        total_count;
   wire [COUNT_BITW-1:0]       current_total;
   assign current_total = total_count + hst_rd_data;
   always_ff @(posedge clock) begin
      if(state == 0) begin
	 total_count <= 0;
	 counting    <= 0;
      end
      else if(state == 1) begin
	 counting    <= 1;
      end
      else if(state == 2) begin
	 counting    <= 0;
      end
      if(counting)
	total_count <= current_total;
   end
   
   // conversion table control ------------------------------------------------
   generate
      // linear transformation
      if(EQUALIZE_HIST == 0) begin: cst_linear
	 // finds the minimum and maximum value
	 reg                   min_found, max_found;
	 reg [BIT_WIDTH-1:0]   min_val,   max_val;
	 always_ff @(posedge clock) begin
	    if((state == 1) && !counting) begin
	       {min_found, max_found} <= 0;
	    end
	    else if(counting) begin
	       if(!min_found && (CLIP_PIXS < current_total)) begin
		  min_found <= 1;
		  min_val   <= hst_rd_addr - 1;
	       end
	       if(!max_found && 
		  ((TOTAL_PIXS - CLIP_PIXS) <= current_total)) begin
		  max_found <= 1;
		  max_val   <= hst_rd_addr - 1;
	       end
	    end
	 end
	 // calculates corresponding values
	 reg [BIT_WIDTH-1:0]   target;
	 reg [BIT_WIDTH*2-1:0] weight, val, prod_buf, prod;
	 reg [1:0] 	       wait_count;
	 always_ff @(posedge clock) begin
	    if(state == 2) begin
	       if(counting) begin
		  target     <= 0;
		  weight     <= inv_table[max_val - min_val];
		  wait_count <= 0;
	       end
	       else begin
		  target     <= target + 1;
		  if(wait_count < 3)
		    wait_count <= wait_count + 1;
	       end
	    end
	    val      <= (target < min_val) ? 0 : (max_val < target) ? 
			(max_val - min_val) : (target - min_val);
	    prod_buf <= val * weight;
	    prod     <= prod_buf;
	 end
	 // RAM control
	 always_ff @(posedge clock) begin
	    if(!n_rst) begin
	       ctb_wr_en <= 0;
	    end
	    else if(state == 1) begin
	       ctb_wr_addr <= 0;
	       ctb_wr_data <= 0;
	    end
	    else if(state == 2) begin
	       if(!counting && (wait_count == 3)) begin
		  if(ctb_wr_addr == (DRANGE - 1))
		    ctb_wr_en <= 0;
		  else
		    ctb_wr_en <= 1;
		  ctb_wr_addr <= target - 3;
		  ctb_wr_data <= ((prod >> (BIT_WIDTH - 1)) + 1) >> 1;
	       end
	    end
	 end
      end
      // histogram equalization
      else begin: cst_eq_hist
	 // calculates corresponding values
	 localparam [BIT_WIDTH+COUNT_BITW-1:0] WEIGHT
	   = ((DRANGE - 1.0) / (TOTAL_PIXS - 2.0 * CLIP_PIXS)) *
	     $pow(2.0, COUNT_BITW);
	 reg [COUNT_BITW-1:0]           val;
	 reg [BIT_WIDTH+COUNT_BITW-1:0] prod_buf,  prod;
	 reg [BIT_WIDTH-1:0] 		addr_buf2, addr_buf, addr;
	 reg [1:0] 			wait_count;
	 always_ff @(posedge clock) begin
	    if(state == 0) begin
	       wait_count <= 0;
	    end
	    else if(counting && (wait_count < 3)) begin
	       wait_count <= wait_count + 1;
	    end
	    val       <= (current_total <= CLIP_PIXS) ? 0 : 
			 (((TOTAL_PIXS - CLIP_PIXS) <= current_total) ? 
			  (TOTAL_PIXS - CLIP_PIXS * 2) :
			  (current_total - CLIP_PIXS));
	    addr_buf2 <= hst_rd_addr - 1;
	    prod_buf  <= val * WEIGHT;
	    addr_buf  <= addr_buf2;
	    {prod, addr} <= {prod_buf, addr_buf};
	 end
	 // RAM control
	 always_ff @(posedge clock) begin
	    if(((state == 1) || (state == 2)) && (wait_count == 3)) begin
	       if((state == 2) && (ctb_wr_addr == (DRANGE - 1)))
		 ctb_wr_en <= 0;
	       else
		 ctb_wr_en <= 1;
	       ctb_wr_addr <= addr;
	       ctb_wr_data <= ((prod >> (COUNT_BITW - 1)) + 1) >> 1;
	    end
	 end
      end
   endgenerate
   
   // outputs results ---------------------------------------------------------
   reg [BIT_WIDTH-1:0] res_pixel;
   reg [V_BITW-1:0]    res_vcnt;
   reg [H_BITW-1:0]    res_hcnt;
   always_ff @(posedge clock) begin
      {res_vcnt, res_hcnt} <= {in_vcnt, in_hcnt};
      {out_vcnt, out_hcnt} <= {res_vcnt, res_hcnt};
      res_pixel <= ((res_vcnt < IMAGE_HEIGHT) && 
		    (res_hcnt < IMAGE_WIDTH)) ? ctb_rd_data : 0;
   end
   assign out_pixel = res_pixel;
   
endmodule
`default_nettype wire
