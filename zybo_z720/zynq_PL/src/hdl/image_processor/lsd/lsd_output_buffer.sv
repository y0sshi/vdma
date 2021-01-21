//-----------------------------------------------------------------------------
// <lsd_output_buffer>
//  - Buffer of the outputs from <simple_lsd>
//    - Compatible with <simple_lsd> from version 1.06 to 1.07
//  - The write protected version is <lsd_output_buffer_wp> 
//-----------------------------------------------------------------------------
// Version 1.00 (Nov. 14, 2019)
//  - Initial version
//-----------------------------------------------------------------------------
// (C) 2019 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------

`default_nettype none
`timescale 1ns/1ns

module lsd_output_buffer
  #( parameter integer BIT_WIDTH    = 8,
     parameter integer IMAGE_HEIGHT = -1,
     parameter integer IMAGE_WIDTH  = -1,
     parameter integer FRAME_HEIGHT = -1,
     parameter integer FRAME_WIDTH  = -1,
     parameter integer RAM_SIZE     = 4096 )
   ( clock, n_rst,
     in_flag, in_valid, in_start_v, in_start_h, in_end_v, in_end_h,
     in_rd_addr, out_ready, out_line_num, out_data, 
     out_start_v, out_start_h, out_end_v, out_end_h // add by saikai
     );

   // following parameters are calculated automatically -----------------------
   localparam integer H_BITW    = log2(FRAME_WIDTH);
   localparam integer V_BITW    = log2(FRAME_HEIGHT);
   localparam integer ADDR_BITW = log2(RAM_SIZE);
   localparam integer WORD_SIZE = (H_BITW + V_BITW) * 2;

   // inputs from simple_lsd --------------------------------------------------
   input wire 	                clock, n_rst, in_flag, in_valid;
   input wire [V_BITW-1:0] 	in_start_v, in_end_v;
   input wire [H_BITW-1:0] 	in_start_h, in_end_h;
   
   // inputs from / outputs to PS ---------------------------------------------
   input wire [ADDR_BITW-1:0] 	in_rd_addr;    // read address
   output reg 			out_ready;     // flag showing data is ready
   output reg [ADDR_BITW:0] 	out_line_num;  // total number of valid lines
   output wire [WORD_SIZE-1:0] 	out_data;      // read data
   output wire [V_BITW-1:0] 	out_start_v, out_end_v; // add by saikai
   output wire [H_BITW-1:0]     out_start_h, out_end_h; // add by saikai
   
   // RAM for valid line segments ---------------------------------------------
   reg [WORD_SIZE-1:0] 		line_data [0:RAM_SIZE-1];   // RAM   
   reg [ADDR_BITW-1:0] 		wr_addr;
   // write
   always @(posedge clock) begin
      if(in_flag && in_valid)
	line_data[wr_addr] <= {in_start_v, in_start_h, in_end_v, in_end_h};
   end
   // read
   assign out_data = line_data[in_rd_addr];
   assign {out_start_v, out_start_h, out_end_v, out_end_h} = line_data[in_rd_addr]; // add by saikai
   
   // state control -----------------------------------------------------------
   always @(posedge clock) begin
      if(!n_rst) begin
	 out_ready    <= 0;
	 out_line_num <= 0;
      end
      else begin
	 if(in_flag) begin
	    out_ready <= 0;
	    if(in_valid) begin
	       wr_addr  <= wr_addr + 1;
	       out_line_num <= wr_addr + 1;
	    end
	 end
	 else begin
	    if(out_line_num != 0)
	      out_ready <= 1;
	    wr_addr <= 0;
	 end
      end
   end

   // functions ---------------------------------------------------------------
   function integer log2;
      input integer value;
      begin
     	 value = value - 1;
	 for ( log2 = 0; value > 0; log2 = log2 + 1 )
	   value = value >> 1;
      end
   endfunction   

endmodule
`default_nettype wire
