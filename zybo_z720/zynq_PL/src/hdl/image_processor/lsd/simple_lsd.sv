//-----------------------------------------------------------------------------
// <simple_lsd>
//  - Simplified Line Segment Detector
//-----------------------------------------------------------------------------
// Version 1.10 (Sep. 14, 2020)
//  - Improved region growing algorithm using approximate average angles
//  - Improved accuracy of output angles
//  - Fixed the asymmetry between in-line and inter-line region growing
//  - Other minor refinements
//-----------------------------------------------------------------------------
// (C) 2019-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns

module simple_lsd
  #( parameter int BIT_WIDTH    =    8, // input pixel bit width
     parameter int IMAGE_HEIGHT =   -1, // | image size
     parameter int IMAGE_WIDTH  =   -1, // | 
     parameter int FRAME_HEIGHT =   -1, //  | frame size (including sync.)
     parameter int FRAME_WIDTH  =   -1, //  |
     parameter int ANGLE_THRES  =   16, // (tau) max. angle difference
     parameter int GRAD_THRES   =   22, // (rho) min. gradient magnitude
     parameter int LENGTH_THRES =    8, //       min. length of line segments
     parameter int START_VCNT   =    0, // vcnt where line detection starts
     parameter int RAM_SIZE     = 4096) // size of line segments RAM
   ( clock, n_rst, 
     in_y, in_vcnt, in_hcnt, out_flag, out_valid, 
     out_start_v, out_start_h, out_end_v, out_end_h, out_angle   );

   // local parameters --------------------------------------------------------
   localparam int ANGLE_BITW   = 8;     // currently only 8 is supported
   localparam int TUNING_STEP  = 16;
   localparam int ATAN_LATENCY = 5;
   localparam int MAX_PIXS     = (IMAGE_HEIGHT + IMAGE_WIDTH) * 2;

   // following parameters are calculated automatically -----------------------
   localparam int OVER_THRES   = (RAM_SIZE * 9) / 10;
   localparam int H_BITW       = $clog2(FRAME_WIDTH);
   localparam int V_BITW       = $clog2(FRAME_HEIGHT);
   localparam int ADDR_BITW    = $clog2(RAM_SIZE);
   localparam int PIXS_BITW    = $clog2(MAX_PIXS);
   localparam int V_SUM_BITW   = $clog2(IMAGE_HEIGHT * MAX_PIXS);
   localparam int H_SUM_BITW   = $clog2(IMAGE_WIDTH  * MAX_PIXS);
   localparam int A_SUM_BITW   = ANGLE_BITW + PIXS_BITW;
   localparam int WORD_SIZE    =
		  1 + PIXS_BITW + (V_BITW + H_BITW) * 2 +
		  V_SUM_BITW + H_SUM_BITW + 2 + A_SUM_BITW + ANGLE_BITW;

   // inputs / outputs --------------------------------------------------------
   input wire 	                clock, n_rst;
   input wire [BIT_WIDTH-1:0] 	in_y;
   input wire [V_BITW-1:0] 	in_vcnt;
   input wire [H_BITW-1:0] 	in_hcnt;
   output reg 			out_flag,    out_valid;
   output reg [V_BITW-1:0] 	out_start_v, out_end_v;
   output reg [H_BITW-1:0] 	out_start_h, out_end_h;
   output reg [ANGLE_BITW-1:0] 	out_angle;

   // preprocessing -----------------------------------------------------------
   // 3x3 gaussian filter
   wire [BIT_WIDTH-1:0] 	gau_pixel;
   wire signed [BIT_WIDTH:0] 	gau_pixel_tmp;   // >= 0
   wire [V_BITW-1:0] 		gau_vcnt;
   wire [H_BITW-1:0] 		gau_hcnt;
   conv_layer_fixed
     #( .IMAGE_HEIGHT(IMAGE_HEIGHT), .IMAGE_WIDTH(IMAGE_WIDTH),
	.FRAME_HEIGHT(FRAME_HEIGHT), .FRAME_WIDTH(FRAME_WIDTH),
	.IN_BITW(BIT_WIDTH + 1),     .OUT_BITW(BIT_WIDTH + 1),
	.IN_FRAC_BITW(0),  .WGT_FRAC_BITW(4), .OUT_FRAC_BITW(0),
	.IN_CHS(1),        .OUT_CHS(1),       .FLT_SIZE(3),
	.WEIGHTS('{0.0625, 0.1250, 0.0625,
		   0.1250, 0.2500, 0.1250,
		   0.0625, 0.1250, 0.0625}),  .BIASES('{0.0})    )
   cvf_gaussian
     (  .clock(clock),               .n_rst(n_rst),
	.in_vals({1'b0, in_y}),      .out_vals(gau_pixel_tmp),
	.in_vcnt(in_vcnt),           .out_vcnt(gau_vcnt),
	.in_hcnt(in_hcnt),           .out_hcnt(gau_hcnt)         );   
   assign gau_pixel = gau_pixel_tmp;

   // 2x2 differential filter
   reg signed [BIT_WIDTH:0] 	  gx, gy;   
   wire [0:1][0:1][BIT_WIDTH-1:0] stp_patch;
   wire [V_BITW-1:0] 		  stp_vcnt;
   wire [H_BITW-1:0] 		  stp_hcnt;
   stream_patch
     #( .BIT_WIDTH(BIT_WIDTH), 
	.IMAGE_HEIGHT(IMAGE_HEIGHT), .IMAGE_WIDTH(IMAGE_WIDTH),
	.FRAME_HEIGHT(FRAME_HEIGHT), .FRAME_WIDTH(FRAME_WIDTH),
	.PATCH_HEIGHT(2), .PATCH_WIDTH(2), .CENTER_V(0), .CENTER_H(0) )
   stp_diff_window
     (  .clock(clock),         .n_rst(n_rst), 
	.in_pixel(gau_pixel),  .in_vcnt(gau_vcnt),  .in_hcnt(gau_hcnt),
	.out_patch(stp_patch), .out_vcnt(stp_vcnt), .out_hcnt(stp_hcnt) );
   always_ff @(posedge clock) begin
      gx <= $signed(({2'b0, stp_patch[0][1]} + stp_patch[1][1]) -
		    ({2'b0, stp_patch[0][0]} + stp_patch[1][0])) >>> 1;
      gy <= $signed(({2'b0, stp_patch[1][0]} + stp_patch[1][1]) -
		    ({2'b0, stp_patch[0][0]} + stp_patch[0][1])) >>> 1;
   end
   
   // prepares valid flag and gradient angle
   wire 			grd_valid;
   wire [ANGLE_BITW-1:0] 	grd_angle;   
   wire [V_BITW-1:0] 		grd_vcnt;
   wire [H_BITW-1:0] 		grd_hcnt;
   reg [BIT_WIDTH*2:0]          gx2, gy2;
   reg [BIT_WIDTH*2:0] 		grd_thres_offset;
   always_ff @(posedge clock) begin
      gx2 <= gx * gx;
      gy2 <= gy * gy;
   end
   delay
     #( .BIT_WIDTH(1), .LATENCY(ATAN_LATENCY - 1) )
   dly_grad
     (  .clock(clock), .n_rst(n_rst), .out_data(grd_valid),
	.in_data(((gx2 + gy2) >= 
		  (GRAD_THRES * GRAD_THRES + grd_thres_offset))) );
   
   arctan_calc
     #( .IN_BITW(BIT_WIDTH + 1),  .OUT_BITW(ANGLE_BITW)          )
   atan_grad
     (  .clock(clock), .in_y(gx), .in_x(gy), .out_val(grd_angle) );

   coord_adjuster
     #( .FRAME_HEIGHT(FRAME_HEIGHT), .FRAME_WIDTH(FRAME_WIDTH), 
	.LATENCY(ATAN_LATENCY + 1))
   cad_grad
     (  .clock(clock), .in_vcnt(stp_vcnt), .in_hcnt(stp_hcnt),
	.out_vcnt(grd_vcnt), .out_hcnt(grd_hcnt) );

   // registers and wires -----------------------------------------------------
   // state
   reg [1:0]                       state;
   reg 				   overused;
   reg [ADDR_BITW:0] 		   seg_num, rd_segid;
   // neighbors ([1][1] is the current pixel)
   wire [0:2][0:3] 		   valid_map;
   wire [0:2][0:3][ANGLE_BITW-1:0] angle_map;
   reg signed [ADDR_BITW:0] 	   segid_map [1:3];
   wire [V_BITW-1:0] 		   vcnt;
   wire [H_BITW-1:0] 		   hcnt;
   // parameters of the current region
   reg 				   merging, last;
   reg [PIXS_BITW-1:0] 		   total_pixs;
   reg [V_BITW-1:0] 		   sv, ev;
   reg [H_BITW-1:0] 		   sh, eh;
   reg [V_SUM_BITW-1:0] 	   v_sum;
   reg [H_SUM_BITW-1:0] 	   h_sum;
   reg [1:0] 			   base_angle;
   reg signed [A_SUM_BITW-1:0] 	   angle_sum;
   reg [ANGLE_BITW-1:0] 	   avg_angle;
   reg signed [ADDR_BITW:0] 	   segid, alias_id;
   // parameters of the candidate region in the previous line
   wire 			   p_exist;
   reg 				   p_found;
   wire [PIXS_BITW-1:0] 	   p_total_pixs;
   wire [V_BITW-1:0] 		   p_sv, p_ev;
   wire [H_BITW-1:0] 		   p_sh, p_eh;
   wire [V_SUM_BITW-1:0] 	   p_v_sum;
   wire [H_SUM_BITW-1:0] 	   p_h_sum;
   wire [1:0] 			   p_base_angle;
   wire signed [A_SUM_BITW-1:0]    p_angle_sum;
   wire [ANGLE_BITW-1:0] 	   p_avg_angle;
   reg signed [ADDR_BITW:0] 	   p_segid;
   // stage 1 temporary wires
   wire 			   s1_last;
   wire [PIXS_BITW-1:0] 	   s1_total_pixs;
   wire [V_BITW-1:0] 		   s1_sv, s1_ev;
   wire [H_BITW-1:0] 		   s1_sh, s1_eh;
   wire [V_SUM_BITW-1:0] 	   s1_v_sum;
   wire [H_SUM_BITW-1:0] 	   s1_h_sum;
   wire [1:0] 			   s1_base_angle;
   wire signed [A_SUM_BITW-1:0]    s1_angle_sum;
   wire [ANGLE_BITW-1:0] 	   s1_avg_angle;
   wire signed [ADDR_BITW:0] 	   s1_segid, s1_alias_id;
   wire [1:0] 			   tmp_b_angle;
   // stage 2 temporary wires
   wire 			   s2_last;
   wire [PIXS_BITW-1:0] 	   s2_total_pixs;
   wire [V_BITW-1:0] 		   s2_sv, s2_ev;
   wire [H_BITW-1:0] 		   s2_sh, s2_eh;
   wire [V_SUM_BITW-1:0] 	   s2_v_sum;
   wire [H_SUM_BITW-1:0] 	   s2_h_sum;
   wire [1:0] 			   s2_base_angle;
   wire signed [A_SUM_BITW-1:0]    s2_angle_sum;
   wire [ANGLE_BITW-1:0] 	   s2_avg_angle;
   wire signed [ADDR_BITW:0] 	   s2_segid, s2_alias_id;
   wire [1:0] 			   tmp_mrg_type;
   wire signed [PIXS_BITW+6:0] 	   tmp_asum_bias;
   // whether there is a candidate in the next line
   wire 			   n_found;
   
   // state and output address control ----------------------------------------
   always_ff @(posedge clock) begin
      if(!n_rst) begin
	 state <= 0;
      end
      else if(state == 0) begin   // wait for a new frame
	 if((vcnt == (START_VCNT == 0 ? FRAME_HEIGHT - 1 : START_VCNT - 1)) &&
	    (hcnt == FRAME_WIDTH - 1)) begin
	    state <= 1;
	 end
      end
      else if(state == 1) begin   // search
	 if(vcnt == IMAGE_HEIGHT - 1 && hcnt == FRAME_WIDTH - 1) begin
	    if(seg_num != 0)
	      state <= 2;
	    else
	      state <= 0;
	    rd_segid <= 0;
	 end
      end
      else if(state == 2) begin   // wait for read
	 state    <= 3;
	 rd_segid <= 1;
      end
      else if(state == 3) begin   // output
	 if(rd_segid == seg_num) begin
	    state <= 0;
	 end
	 rd_segid <= rd_segid + 1;
      end
   end

   // automatic threshold control ---------------------------------------------
   always_ff @(posedge clock) begin
      if(!n_rst) begin
	 {overused, grd_thres_offset} <= 0;
      end
      else begin
	 if((vcnt < IMAGE_HEIGHT) && (OVER_THRES < seg_num)) begin
	    overused <= 1;
	 end
	 else if((vcnt == IMAGE_HEIGHT) && (hcnt == 0)) begin
	    if(overused)
	      grd_thres_offset <= grd_thres_offset + TUNING_STEP;
	    else if(TUNING_STEP <= grd_thres_offset)
	      grd_thres_offset <= grd_thres_offset - TUNING_STEP;
	    overused <= 0;
	 end
      end
   end 
   
   // conditions --------------------------------------------------------------
   wire 			   valid;
   wire 			   cond_save, cond_update, cond_continue;
   wire 			   cond_merge, cond_inval;
   assign valid = (hcnt < IMAGE_WIDTH) && valid_map[1][1];
   assign cond_save     
     = merging && !(valid &&
		    angle_check(angle_map[1][1], avg_angle) &&
		    angle_check(angle_map[1][1], angle_map[1][0]));
   assign cond_update = valid && !cond_save;
   assign cond_continue 
     = merging || (p_found && (alias_id == p_segid) &&
		   angle_check(angle_map[1][1], avg_angle));
   assign cond_merge  = p_found && p_exist && (p_segid != s1_segid) &&
			angle_check(p_avg_angle, s1_avg_angle);
   assign cond_inval  = cond_update && cond_merge && merging;
   
   // prepares valid_map, angle_map, and segid_map ----------------------------
   wire [0:2][0:3][ANGLE_BITW:0]   tmp_vamap;
   wire signed [ADDR_BITW:0] 	   tmp_segid;
   stream_patch
     #( .BIT_WIDTH(1 + ANGLE_BITW),        .PADDING(0),
	.IMAGE_HEIGHT(IMAGE_HEIGHT),       .IMAGE_WIDTH(IMAGE_WIDTH),
	.FRAME_HEIGHT(FRAME_HEIGHT),       .FRAME_WIDTH(FRAME_WIDTH),
	.PATCH_HEIGHT(3), .PATCH_WIDTH(4), .CENTER_V(1), .CENTER_H(1) )
   stp_vamap
     (  .clock(clock),                     .n_rst(n_rst),  
	.in_pixel({grd_valid, grd_angle}), .out_patch(tmp_vamap),
	.in_vcnt(grd_vcnt),                .out_vcnt(vcnt), 
	.in_hcnt(grd_hcnt),                .out_hcnt(hcnt)            );
   generate
      for(genvar v = 0; v < 3; v = v + 1) begin: lsd_map_v
	 for(genvar h = 0; h < 4; h = h + 1) begin: lsd_map_h
	    assign {valid_map[v][h], angle_map[v][h]} = tmp_vamap[v][h];
	 end
      end
   endgenerate
   delay
     #( .BIT_WIDTH(ADDR_BITW + 1),    .LATENCY(FRAME_WIDTH - 3)    )
   dly_idmap
     (  .clock(clock), .n_rst(n_rst), .out_data(tmp_segid),
	.in_data(cond_update ? s2_segid : {(ADDR_BITW + 1){1'b1}}) );
   always_ff @(posedge clock) begin
      segid_map[3] <= tmp_segid;
      segid_map[2] <= segid_map[3];
      segid_map[1] <= segid_map[2];
   end

   // RAM for seg_data --------------------------------------------------------
   wire [0:WORD_SIZE-1] 	   ram_rd_data;
   wire signed [ADDR_BITW:0] 	   p_segid_tmp;
   ram_sc
     #( .WORD_SIZE(WORD_SIZE), .RAM_SIZE(RAM_SIZE), .FORWARD(1) )
   ram_0
     (  .clock(clock),         
	.wr_en((state == 1) && (cond_save || cond_inval)),
	.wr_addr(cond_inval ? p_segid[ADDR_BITW-1:0] : segid[ADDR_BITW-1:0]), 
	.wr_data(cond_inval ? {WORD_SIZE{1'b0}} :
		 {1'b1, total_pixs, sv, sh, ev, eh, v_sum, h_sum, 
		  base_angle, angle_sum, avg_angle}),
	.rd_addr((state == 1) ? p_segid_tmp[ADDR_BITW-1:0] : 
		 rd_segid[ADDR_BITW-1:0]), 
	.rd_data(ram_rd_data) );

   // searches for candidates in the previous line ----------------------------
   assign p_segid_tmp
     = ((segid_map[1] != -1) && (hcnt != FRAME_WIDTH - 1) && 
	angle_check(angle_map[0][1], angle_map[1][2])) ? segid_map[1] :
       ((segid_map[2] != -1) && 
	angle_check(angle_map[0][2], angle_map[1][2])) ? segid_map[2] :
       ((segid_map[3] != -1) && (hcnt != IMAGE_WIDTH - 2) && 
	angle_check(angle_map[0][3], angle_map[1][2])) ? segid_map[3] : -1;
   always_ff @(posedge clock) begin
      p_found <= (p_segid_tmp != -1) && (vcnt > 0);
      p_segid <= p_segid_tmp;
   end
   assign {p_exist, p_total_pixs, p_sv, p_sh, p_ev, p_eh, p_v_sum, p_h_sum,
	   p_base_angle, p_angle_sum, p_avg_angle} = ram_rd_data;

   // searches for candidates in the next line --------------------------------
   assign n_found
     = (vcnt < IMAGE_HEIGHT - 1) &&
       ((valid_map[2][0] && (hcnt != 0) &&
	 angle_check(angle_map[2][0], angle_map[1][1])) ||
	(valid_map[2][1] && 
	 angle_check(angle_map[2][1], angle_map[1][1])) ||
	(valid_map[2][2] && (hcnt != IMAGE_WIDTH - 1) &&
	 angle_check(angle_map[2][2], angle_map[1][1])));

   // [stage 1] ---------------------------------------------------------------
   assign s1_last       = cond_continue ? last : 1;
   assign s1_total_pixs = cond_continue ? total_pixs + 1 : 1;
   assign s1_sv         = cond_continue ? sv : vcnt;
   assign s1_sh         = cond_continue ? sh : hcnt;
   assign s1_ev         = cond_continue ? ev : vcnt;
   assign s1_eh         = cond_continue ? ((eh > hcnt) ? eh : hcnt) : hcnt;
   assign s1_v_sum      = cond_continue ? v_sum + vcnt : vcnt;
   assign s1_h_sum      = cond_continue ? h_sum + hcnt : hcnt;
   assign tmp_b_angle   = (angle_map[1][1] + 6'd32) >> 6;
   assign s1_base_angle = cond_continue ? base_angle : tmp_b_angle;
   assign s1_angle_sum  
     = cond_continue ? 
       (angle_sum + relative_angle(base_angle, angle_map[1][1])) :
       relative_angle(tmp_b_angle, angle_map[1][1]);
   assign s1_avg_angle  = cond_continue ? avg_angle : angle_map[1][1];
   assign s1_segid      = cond_continue ? segid     : seg_num;
   assign s1_alias_id   = cond_continue ? alias_id  : -1;
   
   // [stage 2] ---------------------------------------------------------------
   assign s2_last       = n_found    ? 0 : s1_last;
   assign s2_total_pixs = cond_merge ? 
			  (s1_total_pixs + p_total_pixs) : s1_total_pixs;
   assign s2_sv         = (cond_merge && (p_sv < s1_sv)) ? p_sv : s1_sv;
   assign s2_sh         = (cond_merge && (p_sh < s1_sh)) ? p_sh : s1_sh;
   assign s2_ev         = (cond_merge && (p_ev > s1_ev)) ? p_ev : s1_ev;
   assign s2_eh         = (cond_merge && (p_eh > s1_eh)) ? p_eh : s1_eh;
   assign s2_v_sum      = cond_merge ? s1_v_sum + p_v_sum : s1_v_sum;
   assign s2_h_sum      = cond_merge ? s1_h_sum + p_h_sum : s1_h_sum;
   assign s2_base_angle = s1_base_angle;
   assign tmp_mrg_type  = s1_base_angle - p_base_angle;
   assign tmp_asum_bias = {1'b0, p_total_pixs, 6'd0};
   assign s2_angle_sum
     = cond_merge ?
       (((tmp_mrg_type == 1) ? (p_angle_sum - tmp_asum_bias) :
	 (tmp_mrg_type == 3) ? (p_angle_sum + tmp_asum_bias) : p_angle_sum)
	+ s1_angle_sum) : s1_angle_sum;
   assign s2_segid      = (cond_merge && !merging) ? p_segid : s1_segid;
   assign s2_alias_id   = (cond_merge &&  merging) ? p_segid : s1_alias_id;

   // approximate average angle calculation -----------------------------------
   logic [$clog2(PIXS_BITW+1)-1:0] div_w;
   wire [$clog2(PIXS_BITW+1)-1:0]  div_w1;
   wire [3:0] 			   div_w2;
   wire signed [A_SUM_BITW-1:0]    div_a;
   wire [5:0] 			   div_inv_b;
   wire [ANGLE_BITW-1:0] 	   div_avg_angle;
   // table
   logic [5:0] 			   inv_table_s [64];
   always_comb begin
      for(int i = 0; i < 64; i = i + 1)
	inv_table_s[i] = $pow(2.0, $clog2(i+1) + 4) / i;
   end
   // div_w = $clog2(s2_total_pixs + 1);
   always_comb begin
      div_w = 0;
      for(int i = 0; i < PIXS_BITW; i = i + 1) begin
	 if(s2_total_pixs[i])
	   div_w = i + 1;
      end
   end
   assign div_w1        = (div_w > 6) ? div_w - 6 : 0;
   assign div_w2        = (div_w > 6) ? 10 : div_w + 4;
   assign div_a         = s2_angle_sum >>> div_w1;
   assign div_inv_b     = inv_table_s[s2_total_pixs >> div_w1];
   assign s2_avg_angle  = ($signed({{5{div_a[A_SUM_BITW-1]}}, div_a})
			   * $signed({1'b0, div_inv_b}) >>> div_w2)
     + $signed({1'b0, s2_base_angle, 6'd0});

   // parameter update --------------------------------------------------------
   always_ff @(posedge clock) begin
      if((vcnt == (START_VCNT == 0 ? FRAME_HEIGHT - 1 : START_VCNT - 1)) &&
	 (hcnt == FRAME_WIDTH - 1)) begin
	 seg_num  <=  0;
	 merging  <=  0;
	 alias_id <= -1;
      end
      else if(cond_save) begin
	 if((segid == seg_num) && 
	    (!last || ((ev - sv) + (eh - sh) >= LENGTH_THRES)))
	   seg_num <= seg_num + 1;
	 merging <=  0;
      end
      else if(cond_update) begin
	 {last, total_pixs, sv, ev, sh, eh, v_sum, h_sum, base_angle,
	  angle_sum, avg_angle, segid, alias_id}
	   <= {s2_last, s2_total_pixs, s2_sv, s2_ev, s2_sh, s2_eh, 
	       s2_v_sum, s2_h_sum, s2_base_angle, s2_angle_sum, 
	       s2_avg_angle, s2_segid, s2_alias_id};
	 if(n_found)
	   last <= 0;
	 merging <= 1;
      end
   end

   // outputs results ---------------------------------------------------------
   localparam int TABLE_BITW = 9;
   localparam int MULT_BITW  = 17;
   localparam int FRAC_BITW  = 10;
   localparam int W2_BITW    = $clog2(TABLE_BITW + MULT_BITW - 2 + 1);

   // [stage 1] bit truncation
   reg [TABLE_BITW-1:0] 	   r1_total_pixs;
   reg [V_SUM_BITW-1:0]            r1_v_sum;
   reg [H_SUM_BITW-1:0]            r1_h_sum;
   reg signed [A_SUM_BITW:0] 	   r1_angle_sum;
   reg [W2_BITW-1:0] 		   r1_w2;
   // calculates bit shift width   
   logic [$clog2(PIXS_BITW+1)-1:0] tmp_r1_w;
   wire [$clog2(PIXS_BITW+1)-1:0]  tmp_r1_w1;
   wire [W2_BITW-1:0] 		   tmp_r1_w2;
   always_comb begin
      tmp_r1_w = 0;
      for(int i = 0; i < PIXS_BITW; i = i + 1) begin
	 if(p_total_pixs[i])
	   tmp_r1_w = i + 1;
      end
   end
   assign tmp_r1_w1 = (tmp_r1_w > TABLE_BITW) ? (tmp_r1_w - TABLE_BITW) : 0;
   assign tmp_r1_w2 = (tmp_r1_w > TABLE_BITW) ? (TABLE_BITW + MULT_BITW - 2) :
		      (tmp_r1_w + MULT_BITW - 2);
   always_ff @(posedge clock) begin
      if(tmp_r1_w1 == 0) begin
	 r1_total_pixs <= p_total_pixs;
	 {r1_v_sum, r1_h_sum, r1_angle_sum} 
	   <= {p_v_sum, p_h_sum, p_angle_sum, 1'b0};
      end
      else begin
	 r1_total_pixs <= ((p_total_pixs  >> (tmp_r1_w1 - 1)) + 1)  >> 1;
	 r1_v_sum      <= ((p_v_sum       >> (tmp_r1_w1 - 1)) + 1)  >> 1;
	 r1_h_sum      <= ((p_h_sum       >> (tmp_r1_w1 - 1)) + 1)  >> 1;
	 r1_angle_sum  <= (($signed({p_angle_sum, 1'b0})
			    >>> (tmp_r1_w1 - 1)) + 1) >>> 1;
      end
      r1_w2 <= tmp_r1_w2;
   end

   // [stage 2] reads the reciprocal of total_pixs using a LUT
   reg [MULT_BITW-1:0]             r2_weight;
   reg [V_SUM_BITW-1:0]            r2_v_sum;
   reg [H_SUM_BITW-1:0] 	   r2_h_sum;
   reg signed [A_SUM_BITW:0] 	   r2_angle_sum;
   reg [W2_BITW-1:0] 		   r2_w2;
   // table
   logic [MULT_BITW-1:0] 	   inv_table [1 << TABLE_BITW];
   always_comb begin
      for(int i = 0; i < (1 << TABLE_BITW); i = i + 1)
	inv_table[i] = $pow(2.0, $clog2(i+1) + MULT_BITW - 2) / i;
   end
   always_ff @(posedge clock) begin
      r2_weight <= inv_table[r1_total_pixs];
      {r2_w2, r2_v_sum, r2_h_sum, r2_angle_sum}
	<= {r1_w2, r1_v_sum, r1_h_sum, r1_angle_sum};
   end

   // [stage 3] multiplication
   reg [V_SUM_BITW+MULT_BITW-2:0]  r3_v_prod;
   reg [H_SUM_BITW+MULT_BITW-2:0]  r3_h_prod;
   reg signed [A_SUM_BITW+MULT_BITW:0]  r3_angle_prod;
   reg [W2_BITW-1:0] 		   r3_w2;
   always_ff @(posedge clock) begin
      r3_v_prod     <= r2_v_sum     * r2_weight;
      r3_h_prod     <= r2_h_sum     * r2_weight;
      r3_angle_prod <= r2_angle_sum * $signed({1'b0, r2_weight});
      r3_w2         <= r2_w2;
   end

   // [stage 4] rounding
   reg [V_BITW-1:0]                r4_gv;
   reg [H_BITW-1:0] 		   r4_gh;
   reg signed [ANGLE_BITW:0] 	   r4_aa;
   wire [1:0] 			   r4_base_angle;
   delay
     #( .BIT_WIDTH(2), .LATENCY(4) )
   dly_bangle
     (  .clock(clock), .n_rst(n_rst), 
	.in_data(p_base_angle), .out_data(r4_base_angle)  );
   always_ff @(posedge clock) begin
      if(r3_w2 == 0) begin
	 r4_gv <= r3_v_prod;
	 r4_gh <= r3_h_prod;
	 r4_aa <= r3_angle_prod;
      end
      else begin
	 r4_gv <= ((r3_v_prod      >> (r3_w2 - 1)) + 1)  >> 1;
	 r4_gh <= ((r3_h_prod      >> (r3_w2 - 1)) + 1)  >> 1;
	 r4_aa <= ((r3_angle_prod >>> (r3_w2 - 1)) + 1) >>> 1;
      end
   end

   // [stage 5] timing adjustment for sine calculation
   reg [V_BITW-1:0] 		   r5_gv;
   reg [H_BITW-1:0] 		   r5_gh;
   reg signed [ANGLE_BITW:0] 	   r5_aa;
   reg [1:0] 			   r5_base_angle;
   wire [V_BITW-1:0] 		   r5_sv, r5_ev;
   wire [H_BITW-1:0] 		   r5_sh, r5_eh;
   delay
     #( .BIT_WIDTH((V_BITW + H_BITW) * 2), .LATENCY(5) )
   dly_box
     (  .clock(clock), .n_rst(n_rst), .in_data({p_sv, p_sh, p_ev, p_eh}), 
	.out_data({r5_sv, r5_sh, r5_ev, r5_eh})  );
   always_ff @(posedge clock) begin
      {r5_gv, r5_gh, r5_aa, r5_base_angle} 
	<= {r4_gv, r4_gh, r4_aa, r4_base_angle};
   end
   
   // [stage 6] waits for sine calculation
   reg [ANGLE_BITW:0]              r6_angle;
   reg [V_BITW-1:0] 		   r6_gv, r6_sv, r6_ev;
   reg [H_BITW-1:0] 		   r6_gh, r6_a,  r6_b;
   wire [ANGLE_BITW:0] 		   tmp_r6_angle;
   assign tmp_r6_angle = r5_aa + {r5_base_angle, 7'd0};
   always_ff @(posedge clock) begin
      r6_angle       <= tmp_r6_angle;
      if(tmp_r6_angle[ANGLE_BITW-1] == 1'b0)
	{r6_a, r6_b} <= {r5_sh, r5_eh};
      else
	{r6_a, r6_b} <= {r5_eh, r5_sh};
      {r6_gv, r6_sv, r6_ev, r6_gh} <= {r5_gv, r5_sv, r5_ev, r5_gh};
   end
      
   // [stage 5-7] sine calculation
   wire signed [FRAC_BITW+2:0]     r7_w1, r7_w2;
   reg signed [H_BITW:0] 	   r7_d1, r7_d3;
   reg signed [V_BITW:0] 	   r7_d2, r7_d4;
   reg [ANGLE_BITW:0]              r7_angle;
   reg [V_BITW-1:0] 		   r7_gv;
   reg [H_BITW-1:0]                r7_a,  r7_b;
   wire [ANGLE_BITW-1:0] 	   tmp_r7_phase1, tmp_r7_phase2;
   wire signed [FRAC_BITW+1:0] 	   tmp_r7_sin1,   tmp_r7_sin2;
   assign tmp_r7_phase1 = r4_aa + {r4_base_angle, 7'd0};
   assign tmp_r7_phase2 = r4_aa + {r4_base_angle, 7'd0} + 64;
   sin_calc
     #( .IN_BITW(ANGLE_BITW), .OUT_BITW(FRAC_BITW + 2) )
   sin_w1
     (  .clock(clock), .in_phase(tmp_r7_phase1), .out_val(tmp_r7_sin1) );
   sin_calc
     #( .IN_BITW(ANGLE_BITW), .OUT_BITW(FRAC_BITW + 2) )
   sin_w2
     (  .clock(clock), .in_phase(tmp_r7_phase2), .out_val(tmp_r7_sin2) );
   assign r7_w1 = tmp_r7_sin1;
   assign r7_w2 = 1024 - tmp_r7_sin2;
   always_ff @(posedge clock) begin
      r7_d1 <= {1'b0, r6_gh} - r6_a;
      r7_d2 <= {1'b0, r6_gv} - r6_ev;
      r7_d3 <= {1'b0, r6_gh} - r6_b;
      r7_d4 <= {1'b0, r6_gv} - r6_sv;
      {r7_angle, r7_gv, r7_a, r7_b} <= {r6_angle, r6_gv, r6_a, r6_b};
   end

   // [stage 8] multiplication
   reg signed [FRAC_BITW+H_BITW+3:0] r8_w1d1, r8_w1d3, r8_w2d1, r8_w2d3;   
   reg signed [FRAC_BITW+V_BITW+3:0] r8_w1d2, r8_w1d4, r8_w2d2, r8_w2d4;
   reg [ANGLE_BITW:0]                r8_angle;
   reg [V_BITW-1:0] 		     r8_gv;
   reg [H_BITW-1:0] 		     r8_a,  r8_b;
   always_ff @(posedge clock) begin
      r8_w1d1 <= r7_w1 * r7_d1;
      r8_w1d2 <= r7_w1 * r7_d2;
      r8_w1d3 <= r7_w1 * r7_d3;
      r8_w1d4 <= r7_w1 * r7_d4;
      r8_w2d1 <= r7_w2 * r7_d1;
      r8_w2d2 <= r7_w2 * r7_d2;
      r8_w2d3 <= r7_w2 * r7_d3;
      r8_w2d4 <= r7_w2 * r7_d4;
      {r8_angle, r8_gv, r8_a, r8_b} <= {r7_angle, r7_gv, r7_a, r7_b};
   end

   // [stage 9]
   reg signed [V_BITW+1:0]         r9_v1, r9_v2;
   reg signed [H_BITW+1:0] 	   r9_h1, r9_h2;
   reg [ANGLE_BITW:0] 		   r9_angle;
   always_ff @(posedge clock) begin
      r9_v1 <= ((((r8_w1d1 - r8_w2d2) >>> FRAC_BITW) + 1) >>> 1) + r8_gv;
      r9_v2 <= ((((r8_w1d3 - r8_w2d4) >>> FRAC_BITW) + 1) >>> 1) + r8_gv;
      r9_h1 <= ((((r8_w1d2 + r8_w2d1) >>> FRAC_BITW) + 1) >>> 1) + r8_a;
      r9_h2 <= ((((r8_w1d4 + r8_w2d3) >>> FRAC_BITW) + 1) >>> 1) + r8_b;
      r9_angle <= r8_angle;
   end

   // [stage 10] clipping
   reg [V_BITW-1:0]                ra_v1, ra_v2;
   reg [H_BITW-1:0] 		   ra_h1, ra_h2;
   reg [ANGLE_BITW-1:0] 	   ra_angle;
   reg signed [V_BITW:0] 	   ra_vd;
   reg signed [H_BITW:0] 	   ra_hd;
   wire [V_BITW-1:0] 		   tmp_ra_v1, tmp_ra_v2;
   wire [H_BITW-1:0] 		   tmp_ra_h1, tmp_ra_h2;
   assign tmp_ra_v1
     = (r9_v1 < 0) ? 0 : (IMAGE_HEIGHT <= r9_v1) ? IMAGE_HEIGHT - 1 : r9_v1;
   assign tmp_ra_v2
     = (r9_v2 < 0) ? 0 : (IMAGE_HEIGHT <= r9_v2) ? IMAGE_HEIGHT - 1 : r9_v2;
   assign tmp_ra_h1
     = (r9_h1 < 0) ? 0 : (IMAGE_WIDTH  <= r9_h1) ? IMAGE_WIDTH  - 1 : r9_h1;
   assign tmp_ra_h2
     = (r9_h2 < 0) ? 0 : (IMAGE_WIDTH  <= r9_h2) ? IMAGE_WIDTH  - 1 : r9_h2;
   always_ff @(posedge clock) begin
      {ra_v1, ra_h1, ra_v2, ra_h2} 
	<= (r9_angle < 256) ? {tmp_ra_v1, tmp_ra_h1, tmp_ra_v2, tmp_ra_h2} :
	   {tmp_ra_v2, tmp_ra_h2, tmp_ra_v1, tmp_ra_h1};
      ra_vd    <= $signed({1'b0, tmp_ra_v1}) - $signed({1'b0, tmp_ra_v2});
      ra_hd    <= $signed({1'b0, tmp_ra_h1}) - $signed({1'b0, tmp_ra_h2});
      ra_angle <= (r9_angle + 1) >> 1;
   end

   // [stage 11] calculates line length
   reg [PIXS_BITW*2-1:0]           rb_len1, rb_len2;
   reg [V_BITW-1:0]                rb_v1,   rb_v2;
   reg [H_BITW-1:0] 		   rb_h1,   rb_h2;
   reg [ANGLE_BITW-1:0] 	   rb_angle;
   wire 			   rb_flag, rb_exist;
   delay
     #( .BIT_WIDTH(2), .LATENCY(11) )
   dly_flags
     (  .clock(clock),                     .n_rst(n_rst), 
	.in_data({(state == 3), p_exist}), .out_data({rb_flag, rb_exist}) );
   always_ff @(posedge clock) begin
      rb_len1 <= ra_vd * ra_vd;
      rb_len2 <= ra_hd * ra_hd;
      {rb_v1, rb_h1, rb_v2, rb_h2, rb_angle} 
	<= {ra_v1, ra_h1, ra_v2, ra_h2, ra_angle};
   end

   // [stage 12] outputs results
   always_ff @(posedge clock) begin
      out_flag  <= rb_flag;
      out_valid <= rb_exist && (rb_len1 + rb_len2 >= 
				(LENGTH_THRES * LENGTH_THRES));
      {out_start_v, out_start_h, out_end_v, out_end_h, out_angle}
	<= {rb_v1, rb_h1, rb_v2, rb_h2, rb_angle};
   end
   
   // functions ---------------------------------------------------------------
   // calculates angle difference
   function angle_check;
      input [ANGLE_BITW-1:0] a, b;
      reg [ANGLE_BITW-1:0]   abs_diff;  // not a register
      begin
	 abs_diff = (a > b) ? (a - b) : (b - a);
	 angle_check 
	   = (({abs_diff, 1'b0} < (1 << ANGLE_BITW)) ?
	      abs_diff : (1 << ANGLE_BITW) - abs_diff) < ANGLE_THRES;
      end
   endfunction

   function signed [ANGLE_BITW-1:0] relative_angle;
      input [1:0]            base;
      input [ANGLE_BITW-1:0] a;
      begin
	 relative_angle = a - {base, 6'd0};
      end
   endfunction
   
endmodule
`default_nettype wire
