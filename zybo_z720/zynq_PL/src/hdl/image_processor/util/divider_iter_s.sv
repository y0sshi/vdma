//-----------------------------------------------------------------------------
// <divider_iter_s>
//  - Simple divider (signed version)
//    - a = bq + r
//    - <in_a>, <in_b>, <out_q>, and <out_r> are all signed.
//      Please use <divider_iter_u> for unsigned division
//    - The quotient <q> will be truncated toward 0.
//      Thus, if <a> is negative, the remainder <r> will also be negative
//    - if <b> is 0, the quotient <q> will be 0 no matter what <a> is
//  - Give <in_a> and <in_b> and assert <in_en> at the same time
//    while <out_ready> is 1 to start calculation
//  - Input values are regarded as integer, and output values have
//    the fixed-point format whose fractional bit width is <OUT_FRAC_BITW>
//  - Required processing time varies depending on the inputs
//    - Maximum: (BIT_WIDTH + OUT_FRAC_BITW + 2) clock cycles
//    - Minimum: 3 clock cycles
//    - Results are output at the same time <out_ready> gets back to 1
//-----------------------------------------------------------------------------
// Version 1.03 (Feb. 18, 2020)
//  - Renamed from <divider_iter>
//  - Removed <out_flag> port
//  - Added <OUT_FRAC_BITW> parameter
//  - Reduced required clock cycles depending on the inputs
//-----------------------------------------------------------------------------
// (C) 2018-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns
  
module divider_iter_s
  #( parameter int BIT_WIDTH     = -1,
     parameter int OUT_FRAC_BITW = 0 )
   ( clock, n_rst, in_en, in_a, in_b, out_ready, out_q, out_r );

   // local parameters --------------------------------------------------------
   localparam int  TOTAL_BITW = BIT_WIDTH + OUT_FRAC_BITW;
   
   // inputs / outputs --------------------------------------------------------
   input wire         	              clock, n_rst, in_en;
   input wire signed [BIT_WIDTH-1:0]  in_a, in_b;
   output wire 			      out_ready;
   output reg signed [TOTAL_BITW:0]   out_q;
   output reg signed [TOTAL_BITW-1:0] out_r;

   // registers and wires -----------------------------------------------------
   reg [TOTAL_BITW-1:0] 	      r, q, b;
   reg 				      r_minus, q_minus;
   reg [$clog2(TOTAL_BITW)-1:0]       scale;
   wire [$clog2(TOTAL_BITW+1)-1:0]    a_zero_count, b_zero_count;
   wire [TOTAL_BITW-1:0] 	      scaled_b;
   
   // -------------------------------------------------------------------------
   assign a_zero_count = top_zero_count(r);
   assign b_zero_count = top_zero_count(b);
   assign scaled_b     = b << scale;

   // state control
   reg [1:0] 			      state;
   always_ff @(posedge clock) begin
      if(!n_rst)
	state <= 0;
      // [0] wait and preparation
      else if(state == 0) begin
	 if(in_en)
	   state <= 1;
      end
      // [1] calculates required step cycles
      else if(state == 1) begin
	 // (b == 0) or (b == 1) or (a < b)
	 if(b_zero_count >= (TOTAL_BITW - 1) || b_zero_count < a_zero_count)
	   state <= 3;
	 else
	   state <= 2;
      end
      // [2] iterative comparison and subtraction
      else if(state == 2) begin
	 if(scale == 0)
	   state <= 3;
      end
      // [3] outputs results
      else if(state == 3)
	state <= 0;
   end   

   // absolute value
   always_ff @(posedge clock) begin
      // [0] wait and preparation
      if(state == 0) begin
	 if(in_en) begin
	    r <= {{(OUT_FRAC_BITW + 1){1'b0}}, 
		  ((in_a >= 0) ? in_a : -in_a)} << OUT_FRAC_BITW;
	    q <= 0;
	    b <= (in_b >= 0) ? in_b : -in_b;
	 end
      end
      // [1] calculates required step cycles
      else if(state == 1) begin
	 if(b_zero_count == (TOTAL_BITW - 1)) begin   // b == 1
	    r <= 0;
	    q <= r;
	 end
	 scale <= b_zero_count - a_zero_count;	 
      end
      // [2] iterative comparison and subtraction
      else if(state == 2) begin
	 if(r >= scaled_b) begin
	    r <= r - scaled_b;
	    q <= q | ({{TOTAL_BITW{1'b0}}, 1'b1} << scale);
	 end
	 scale <= scale - 1;
      end
   end

   // sign processing
   always_ff @(posedge clock) begin
      if(!n_rst) begin
	 {out_q, out_r} <= 0;
      end
      // [0] wait and preparation
      else if(state == 0) begin
	 if(in_en) begin
	    {out_q, out_r} <= 0;
	    r_minus <= (in_a <= 0);      
	    q_minus <= (in_a < 0 && in_b >= 0) || (in_a >= 0 && in_b < 0);
	 end
      end
      // [3] outputs results
      else if(state == 3) begin
	 out_q <= q_minus ? -({1'b0, q}) : q;
	 out_r <= r_minus ? -r : r;
      end
   end
   assign out_ready = (state == 0);
   
   // functions ---------------------------------------------------------------
   function [$clog2(TOTAL_BITW+1)-1:0] top_zero_count;
      input [TOTAL_BITW-1:0] val;
      begin
	 top_zero_count = 0;
	 for(int i = 0; i < TOTAL_BITW; i = i + 1) begin
	    if((val >> (TOTAL_BITW - i - 1)) == 0)
	      top_zero_count = i + 1;
	 end
      end
   endfunction
   
endmodule
`default_nettype wire
