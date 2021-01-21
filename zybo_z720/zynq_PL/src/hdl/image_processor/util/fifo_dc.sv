//-----------------------------------------------------------------------------
// <fifo_dc> 
//  - Dual-clock first-in/first-out (queue) module
//    - <INITIAL_SIZE> is the initial queue size (= write address)
//  - Read latency: 1 clock cycle
//    - Any written data MUST be read adequate time after the write.
//      Otherwise the data will not be read properly and will be lost
//-----------------------------------------------------------------------------
// Version 1.13 (Dec. 18, 2019)
//  - Code refinement
//-----------------------------------------------------------------------------
// (C) 2018-2019 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns
  
module fifo_dc
  #( parameter int BIT_WIDTH    = -1,
     parameter int FIFO_SIZE    = -1,
     parameter int INITIAL_SIZE = 0 )
   ( wr_clock, rd_clock, n_rst,
     wr_en, rd_en, wr_data, rd_data  );

   // local parameters --------------------------------------------------------
   localparam int ADDR_BITW = $clog2(FIFO_SIZE);

   // inputs/outputs ----------------------------------------------------------
   input wire       	       wr_clock, rd_clock, n_rst, wr_en, rd_en;
   input wire [BIT_WIDTH-1:0]  wr_data;
   output wire [BIT_WIDTH-1:0] rd_data;

   // registers ---------------------------------------------------------------
   reg [ADDR_BITW-1:0] 	       wr_addr, rd_addr;
   reg 			       rd_en_buf;

   // address control ---------------------------------------------------------
   always_ff @(posedge wr_clock) begin
      if(!n_rst)
	wr_addr <= INITIAL_SIZE;
      else begin
	 if(wr_en) begin
	    if(wr_addr == FIFO_SIZE - 1)
	      wr_addr <= 0;
	    else
	      wr_addr <= wr_addr + 1;
	 end
      end
   end
   always_ff @(posedge rd_clock) begin
      if(!n_rst)
	rd_addr <= 0;
      else begin
	 rd_en_buf <= rd_en;
	 if(rd_en) begin
	    if(rd_addr == FIFO_SIZE - 1)
	      rd_addr <= 0;
	    else
	      rd_addr <= rd_addr + 1;
	 end
      end
   end    

   // ram ---------------------------------------------------------------------
   wire [BIT_WIDTH-1:0]        ram_rd_data;
   ram_dc
     #( .WORD_SIZE(BIT_WIDTH), .RAM_SIZE(FIFO_SIZE) )
   ram_0
     (  .wr_clock(wr_clock), .rd_clock(rd_clock), .wr_en(wr_en),
	.wr_addr(wr_addr),   .wr_data(wr_data),
	.rd_addr(rd_addr),   .rd_data(ram_rd_data)    );

   // assigns result ----------------------------------------------------------
   assign rd_data = rd_en_buf ? ram_rd_data : 0;
   
endmodule
`default_nettype wire

