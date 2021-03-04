//-----------------------------------------------------------------------------
// <lsd_output_buffer>
//  - Buffer of the outputs from <simple_lsd>
//    - Compatible with <simple_lsd> from version 1.06 to 1.07
//-----------------------------------------------------------------------------
// Version 1.00 (Nov. 14, 2019)
//  - Initial version
//-----------------------------------------------------------------------------
// (C) 2019 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns

module lsd_output_buffer_wp
  #(
    parameter integer BIT_WIDTH    = 8,
    parameter integer IMAGE_HEIGHT = -1,
    parameter integer IMAGE_WIDTH  = -1,
    parameter integer FRAME_HEIGHT = -1,
    parameter integer FRAME_WIDTH  = -1,
    parameter integer RAM_SIZE     = 4096 )
    ( wclock, rclock, n_rst,
    in_flag, in_valid, in_start_v, in_start_h, in_end_v, in_end_h,
    in_rd_addr, 
    in_write_protect,  // add by yoshinaga
    out_ready, out_line_num,
    out_start_v, out_start_h, out_end_v, out_end_h // add by saikai
  );

  // following parameters are calculated automatically -----------------------
  localparam integer H_BITW    = log2(FRAME_WIDTH);
  localparam integer V_BITW    = log2(FRAME_HEIGHT);
  localparam integer ADDR_BITW = log2(RAM_SIZE);
  localparam integer WORD_SIZE = (H_BITW + V_BITW) * 2;

  // inputs from simple_lsd --------------------------------------------------
  input wire 	                wclock, rclock, n_rst, in_flag, in_valid;
  input wire [V_BITW-1:0] 	in_start_v, in_end_v;
  input wire [H_BITW-1:0] 	in_start_h, in_end_h;

  // inputs from / outputs to PS ---------------------------------------------
  input wire [ADDR_BITW-1:0] 	in_rd_addr;    // read address
  input wire in_write_protect; // add by yoshinaga
  //output reg 			out_ready;     // flag showing data is ready
  output wire			out_ready;     // flag showing data is ready
  output reg [ADDR_BITW:0] 	out_line_num;  // total number of valid lines
  output wire [V_BITW-1:0] 	out_start_v, out_end_v; // add by saikai
  output wire [H_BITW-1:0]     out_start_h, out_end_h; // add by saikai

  // RAM for valid line segments ---------------------------------------------
  reg [WORD_SIZE-1:0] 		line_data [0:RAM_SIZE-1];   // RAM   
  reg [ADDR_BITW-1:0] 		wr_addr;
  reg                     write_protect; // add by yoshi
  reg [WORD_SIZE-1:0]     line_data_buf; // add by yoshi
  reg [ADDR_BITW:0] 	    line_num;      // add by yoshi
  reg [ADDR_BITW-1:0]     rd_addr;       // add by yoshi

  // write
  always @(posedge wclock) begin
    if(in_flag && in_valid && !write_protect) begin
      line_data[wr_addr] <= {in_start_v, in_start_h, in_end_v, in_end_h};
    end
  end

  // read
  always @(posedge rclock) begin
    rd_addr <= in_rd_addr;
    if (!n_rst) begin
      out_line_num  <= 0;
    end else begin
      out_line_num  <= line_num;
    end
  end
  assign {out_start_v, out_start_h, out_end_v, out_end_h} = line_data[rd_addr]; // add by yoshi
  //assign {out_start_v, out_start_h, out_end_v, out_end_h} = line_data[in_rd_addr]; // add by saikai

  // state control -----------------------------------------------------------
  always @(posedge wclock) begin
    if(!n_rst) begin
      //out_ready    <= 0;
      write_protect <= 0;
      line_num <= 0;
      wr_addr <= 0;
    end
    else begin
      if(in_flag) begin
				write_protect <= write_protect;
        if(in_valid && !write_protect) begin
          wr_addr  <= wr_addr + 1;
          //out_ready <= 0;
          line_num <= wr_addr + 1;
        end
      end
      else begin
        if(out_line_num != 0) begin
          write_protect <= in_write_protect;
          //out_ready <= 1;
        end
				else begin
					write_protect <= write_protect;
				end
        wr_addr <= 0;
      end
    end
  end
  assign out_ready = write_protect;

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
