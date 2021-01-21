//-----------------------------------------------------------------------------
// <tree_adder>
//  - Calculates the sum of all input values using a 2-input adder tree
//    - If <BIT_EXTEND> != 0, bit extension will be performed
//      on every addition so that the result will not overflow
//  - Latency:
//    -  binary mode: ceil(log_2(IN_NUM)) clock cycles
//    - ternary mode: ceil(log_3(IN_NUM)) clock cycles
//-----------------------------------------------------------------------------
// Version 1.04 (Jul. 30, 2020)
//  - Renamed the input port <in_vals>
//  - Added support for ternary adder tree 
//    to reduce resource utilization and latency
//-----------------------------------------------------------------------------
// (C) 2017-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns
  
module tree_adder
  #( parameter int IN_NUM     = -1,  // # of input values
     parameter int IN_BITW    = -1,  // input value bit width
     parameter int BIT_EXTEND =  0,  // to apply bit extension or not
     parameter int TERNARY    =  0)  // 0: binary tree, 1: ternary tree
   ( clock, in_vals, out_sum );

   // local parameters --------------------------------------------------------
   localparam int ADD_DEPTH = 0 + ((TERNARY == 0) ? $clog2(IN_NUM) :
				   $ceil($ln(IN_NUM) / $ln(3)));
   //             // to add 0 is a workaround to avoid problem in Vivado
   localparam int OUT_BITW  = 
		  IN_BITW + ((BIT_EXTEND == 0) ? 0 : $clog2(IN_NUM));
   localparam int UNIT_SIZE = (TERNARY == 0) ? 2 : 3;
   
   // inputs / outputs --------------------------------------------------------
   input wire            	        clock;
   input wire [0:IN_NUM-1][IN_BITW-1:0] in_vals;   // signed
   output wire signed [OUT_BITW-1:0]    out_sum;
   
   // -------------------------------------------------------------------------
   generate
      // calculates the summation of input values
      for(genvar d = 0; d < ADD_DEPTH; d = d + 1) begin : itg_add_d
	 localparam int STEP     = $pow(UNIT_SIZE, d);
	 localparam int BLOCK    = $pow(UNIT_SIZE, d + 1);
	 localparam int EXT_BITW = (BIT_EXTEND == 0) ? IN_BITW :
			(IN_BITW + $clog2(BLOCK));
 	 for(genvar p = 0; p < IN_NUM; p = p + BLOCK) begin : add_p
	    reg signed [EXT_BITW-1:0] sum;
	    // ternary addition
	    if((TERNARY != 0) && (p + STEP * 2 < IN_NUM)) begin: add3
	       wire signed [EXT_BITW-1:0] val_1, val_2, val_3;
	       if(d == 0) begin
		  assign val_1 = $signed(in_vals[p]);
		  assign val_2 = $signed(in_vals[p+1]);
		  assign val_3 = $signed(in_vals[p+2]);
	       end
	       else begin
		  assign val_1 = itg_add_d[d-1].add_p[p].sum;
		  assign val_2 = itg_add_d[d-1].add_p[p + STEP].sum;
		  assign val_3 = itg_add_d[d-1].add_p[p + STEP*2].sum;
	       end
	       always_ff @(posedge clock)
		 sum <= val_1 + val_2 + val_3;
	    end
	    // binary addition
	    else if(p + STEP < IN_NUM) begin : add2
	       wire signed [EXT_BITW-1:0] val_1, val_2;
	       if(d == 0) begin
		  assign val_1 = $signed(in_vals[p]);
		  assign val_2 = $signed(in_vals[p+1]);
	       end
	       else begin
		  assign val_1 = itg_add_d[d-1].add_p[p].sum;
		  assign val_2 = itg_add_d[d-1].add_p[p + STEP].sum;
	       end
	       always_ff @(posedge clock)
		 sum <= val_1 + val_2;
	    end
	    // stray values
	    else begin : no_add
	       if(d == 0) begin
		  always_ff @(posedge clock)
		    sum <= $signed(in_vals[p]);
	       end
	       else begin
		  always_ff @(posedge clock)
		    sum <= itg_add_d[d-1].add_p[p].sum;
	       end
	    end
	 end
      end

      // assigns result --------------------------------------------------
      if(ADD_DEPTH == 0) // if IN_NUM == 1
	assign out_sum = $signed(in_vals[0]);
      else
	assign out_sum = itg_add_d[ADD_DEPTH-1].add_p[0].sum;
   endgenerate

endmodule
`default_nettype wire
