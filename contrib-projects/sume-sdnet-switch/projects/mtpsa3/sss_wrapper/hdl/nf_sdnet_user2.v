//
// Copyright (c) 2020 -
// All rights reserved.
//
// @NETFPGA_LICENSE_HEADER_START@
//
// Licensed to NetFPGA C.I.C. (NetFPGA) under one or more contributor
// license agreements.  See the NOTICE file distributed with this work for
// additional information regarding copyright ownership.  NetFPGA licenses this
// file to you under the NetFPGA Hardware-Software License, Version 1.0 (the
// "License"); you may not use this file except in compliance with the
// License.  You may obtain a copy of the License at:
//
//   http://www.netfpga-cic.org
//
// Unless required by applicable law or agreed to in writing, Work distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations under the License.
//
// @NETFPGA_LICENSE_HEADER_END@
//

`timescale 1ns / 1ps

module nf_sdnet_user2 #(

// PARAMETERS

//Master AXI Stream Data Width
parameter                                                      C_M_AXIS_DATA_WIDTH = 256,
parameter                                                      C_S_AXIS_DATA_WIDTH = 256,
parameter                                                      C_M_AXIS_TUSER_WIDTH = 304,
parameter                                                      C_S_AXIS_TUSER_WIDTH = 128,

// AXI Registers Data Width
parameter                                                      C_S_AXI_DATA_WIDTH = 32,
parameter                                                      C_S_AXI_ADDR_WIDTH = 12,

// SDNet Address Width
parameter                                                      SDNET_ADDR_WIDTH = 12,

parameter                                                      DIGEST_WIDTH = 256

)
(

// INTERFACES

// AXIS CLK & RST SIGNALS
input                                                           axis_aclk,
input                                                           axis_resetn, // Need to invert this for the SDNet block (this is active low)

// AXIS PACKET OUTPUT INTERFACE
output          [C_M_AXIS_DATA_WIDTH - 1:0]                     m_axis_tdata,
output          [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0]             m_axis_tkeep,
output          [C_M_AXIS_TUSER_WIDTH-1:0]                      m_axis_tuser,
output 	                                                        m_axis_tvalid,
input                                                           m_axis_tready,
output                                                          m_axis_tlast,

// AXIS PACKET INPUT INTERFACE
input           [C_S_AXIS_DATA_WIDTH - 1:0]                     s_axis_tdata,
input           [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]             s_axis_tkeep,
input           [C_S_AXIS_TUSER_WIDTH-1:0]                      s_axis_tuser,
input                                                           s_axis_tvalid,
output                                                          s_axis_tready,
input                                                           s_axis_tlast,

// AXI CLK & RST SIGNALS
input                                                           S_AXI_ACLK,
input                                                           S_AXI_ARESETN, // Need to invert this for the SDNet block (this is active low)

// AXI-LITE CONTROL INTERFACE
input           [C_S_AXI_ADDR_WIDTH-1 : 0]                      S_AXI_AWADDR,
input                                                           S_AXI_AWVALID,
input           [C_S_AXI_DATA_WIDTH-1 : 0]                      S_AXI_WDATA,
input           [C_S_AXI_DATA_WIDTH/8-1 : 0]                    S_AXI_WSTRB,
input                                                           S_AXI_WVALID,
input                                                           S_AXI_BREADY,
input           [C_S_AXI_ADDR_WIDTH-1 : 0]                      S_AXI_ARADDR,
input                                                           S_AXI_ARVALID,
input                                                           S_AXI_RREADY,
output                                                          S_AXI_ARREADY,
output          [C_S_AXI_DATA_WIDTH-1 : 0]                      S_AXI_RDATA,
output          [1 : 0]                                         S_AXI_RRESP,
output                                                          S_AXI_RVALID,
output                                                          S_AXI_WREADY,
output          [1 :0]                                          S_AXI_BRESP,
output                                                          S_AXI_BVALID,
output                                                          S_AXI_AWREADY

);

/* Format of s_axis_tuser signal:
 *     [15:0]    pkt_len; // unsigned int
 *     [23:16]   src_port; // one-hot encoded: {DMA, NF3, DMA, NF2, DMA, NF1, DMA, NF0}
 *     [31:24]   dst_port; // one-hot encoded: {DMA, NF3, DMA, NF2, DMA, NF1, DMA, NF0}
 *     [39:32]   drop; // only bit 32 is used
 *     [47:40]   send_dig_to_cpu; // only bit 40 is used
 *     [63:48]   nf0_q_size;
 *     [79:64]   nf1_q_size;
 *     [95:80]   nf2_q_size;
 *     [111:96]  nf3_q_size;
 *     [127:112] dma_q_size;
 */


//########################
//## SUME -> SDNet signals
//########################
wire      mtpsa_tuple_in_VALID;
wire      SDNet_in_TLAST;

//########################
//## SDNet -> SUME signals
//########################
wire  [C_S_AXIS_TUSER_WIDTH-1:0]         mtpsa_tuple_out_DATA;
wire  [DIGEST_WIDTH-1:0]                 digest_tuple_out_DATA;

//#####################
//## debugging signals
//#####################
wire         mtpsa_tuple_out_VALID;
wire         digest_tuple_out_VALID;
wire         internal_rst_done;

//##################################
//## Logic to convert the SUME TUSER signal into the SDNet
//## tuple_DATA and tuple_VALID signals.
//##################################
mtpsa_to_sdnet mtpsa_to_sdnet_i (

// clk/rst input
.axis_aclk                        (axis_aclk),
.axis_resetn                      (axis_resetn),

// input SUME axi signals
.SUME_axis_tvalid                 (s_axis_tvalid),
.SUME_axis_tlast                  (s_axis_tlast),
.SUME_axis_tready                 (s_axis_tready),

// output SDNet signals
.SDNet_tuple_VALID                (mtpsa_tuple_in_VALID),
.SDNet_axis_TLAST                 (SDNet_in_TLAST)

); // mtpsa_to_sdnet_i

// SDNet module
user2Switch user2Switch_inst (

// AXIS PACKET INPUT INTERFACE
.packet_in_packet_in_TVALID                                        (s_axis_tvalid),
.packet_in_packet_in_TREADY                                        (s_axis_tready),
.packet_in_packet_in_TDATA                                         (s_axis_tdata),
.packet_in_packet_in_TKEEP                                         (s_axis_tkeep),
.packet_in_packet_in_TLAST                                         (SDNet_in_TLAST),

// TUPLE INPUT INTERFACE
.tuple_in_mtpsa_metadata_VALID                                      (mtpsa_tuple_in_VALID),
.tuple_in_mtpsa_metadata_DATA	                                   (s_axis_tuser),


// AXI-LITE CONTROL INTERFACE
.control_S_AXI_AWADDR                                              (S_AXI_AWADDR[SDNET_ADDR_WIDTH-1:0]), // MISMATCH
.control_S_AXI_AWVALID                                             (S_AXI_AWVALID),
.control_S_AXI_AWREADY                                             (S_AXI_AWREADY),
.control_S_AXI_WDATA                                               (S_AXI_WDATA),
.control_S_AXI_WSTRB                                               (S_AXI_WSTRB),
.control_S_AXI_WVALID                                              (S_AXI_WVALID),
.control_S_AXI_WREADY                                              (S_AXI_WREADY),
.control_S_AXI_BRESP                                               (S_AXI_BRESP),
.control_S_AXI_BVALID                                              (S_AXI_BVALID),
.control_S_AXI_BREADY                                              (S_AXI_BREADY),
.control_S_AXI_ARADDR                                              (S_AXI_ARADDR[SDNET_ADDR_WIDTH-1:0]), // MISMATCH
.control_S_AXI_ARVALID                                             (S_AXI_ARVALID),
.control_S_AXI_ARREADY                                             (S_AXI_ARREADY),
.control_S_AXI_RDATA                                               (S_AXI_RDATA),
.control_S_AXI_RRESP                                               (S_AXI_RRESP),
.control_S_AXI_RVALID                                              (S_AXI_RVALID),
.control_S_AXI_RREADY                                              (S_AXI_RREADY),

// ENABLE SIGNAL
.enable_processing                                                 (1'b1), // CONSTANT

// AXIS PACKET OUTPUT INTERFACE
.packet_out_packet_out_TVALID                                      (m_axis_tvalid),
.packet_out_packet_out_TREADY                                      (m_axis_tready),
.packet_out_packet_out_TDATA                                       (m_axis_tdata),
.packet_out_packet_out_TKEEP                                       (m_axis_tkeep),
.packet_out_packet_out_TLAST                                       (m_axis_tlast),

// TUPLE OUTPUT INTERFACE
.tuple_out_mtpsa_metadata_VALID                                     (mtpsa_tuple_out_VALID),   // unused
.tuple_out_mtpsa_metadata_DATA                                      (mtpsa_tuple_out_DATA),
.tuple_out_digest_data_VALID                                       (digest_tuple_out_VALID), // unused
.tuple_out_digest_data_DATA                                        (digest_tuple_out_DATA),

// LINE CLK & RST SIGNALS
.clk_line_rst                                                      (~axis_resetn), // INV
.clk_line                                                          (axis_aclk),

// PACKET CLK & RST SIGNALS
.clk_lookup_rst                                                    (~axis_resetn), // INV
.clk_lookup                                                        (axis_aclk),

// CONTROL CLK & RST SIGNALS
.clk_control_rst                                                   (~S_AXI_ARESETN), // INV
.clk_control                                                       (S_AXI_ACLK),

// RST DONE SIGNAL
.internal_rst_done                                                 (internal_rst_done) // indicates when the internal reset of the SDNet block is complete

); // p4_processor_inst

// replace q_size data in mtpsa_tuple_out_DATA with digest_data
/* Format of m_axis_tuser signal:
 *     [15:0]    pkt_len; // unsigned int
 *     [23:16]   src_port; // one-hot encoded: {DMA, NF3, DMA, NF2, DMA, NF1, DMA, NF0}
 *     [31:24]   dst_port; // one-hot encoded: {DMA, NF3, DMA, NF2, DMA, NF1, DMA, NF0}
 *     [39:32]   drop; // only bit 32 is used
 *     [47:40]   send_dig_to_cpu; // only bit 40 is used
 *     [127:48]  digest_data;
 */
assign m_axis_tuser = {digest_tuple_out_DATA, mtpsa_tuple_out_DATA[C_M_AXIS_TUSER_WIDTH-DIGEST_WIDTH-1:0]};

// debugging signals
wire [15:0] in_pkt_len    = s_axis_tuser[15:0];
wire [7:0] in_src_port    = s_axis_tuser[23:16];
wire [7:0] in_dst_port    = s_axis_tuser[31:24];

wire [15:0] out_pkt_len    = m_axis_tuser[15:0];
wire [7:0] out_src_port    = m_axis_tuser[23:16];
wire [7:0] out_dst_port    = m_axis_tuser[31:24];
wire [7:0] out_drop        = m_axis_tuser[39:32];
wire [7:0] out_send_dig    = m_axis_tuser[47:40];

endmodule
