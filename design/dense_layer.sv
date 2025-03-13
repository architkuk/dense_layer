// ============================================================================
// Amazon FPGA Hardware Development Kit
//
// Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Amazon Software License (the "License"). You may not use
// this file except in compliance with the License. A copy of the License is
// located at
//
//    http://aws.amazon.com/asl/
//
// or in the "license" file accompanying this file. This file is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
// implied. See the License for the specific language governing permissions and
// limitations under the License.
// ============================================================================


//====================================================================================
// Top level module file for dense_layer
//====================================================================================

module dense_layer
    #(
      parameter EN_DDR = 0,
      parameter EN_HBM = 0
    )
    (
      `include "cl_ports.vh"
    );

`include "cl_id_defines.vh" // CL ID defines required for all examples
`include "dense_layer_defines.vh"

//---------------------------------------------------------------------
// User Internal Debug Signals (hidden from the external interface)
//---------------------------------------------------------------------
logic [31:0] heartbeat_counter;
always_ff @(posedge clk_main_a0 or negedge rst_main_n) begin
    if (!rst_main_n) heartbeat_counter <= 32'd0;
    else heartbeat_counter <= heartbeat_counter + 1;
end

logic debug_rst_local;
logic [31:0] debug_counter_local;

always_ff @(posedge clk_main_a0 or negedge rst_main_n) begin
  if (!rst_main_n)
    debug_counter_local <= 32'd0;
  else
    debug_counter_local <= debug_counter_local + 1;
end

//---------------------------------------------------------------------
// User Design Signals
//---------------------------------------------------------------------
logic signed [31:0] input_x [0:63];
logic signed [31:0] weights   [0:127][0:63];
logic signed [31:0] biases    [0:127];
logic signed [31:0] output_y  [0:127];
logic               start;
logic [127:0]       done;

initial begin
    for (int i = 0; i < 128; i++) begin
        biases[i] = 32'sd1;
        for (int j = 0; j < 64; j++)
            weights[i][j] = 32'sd1;
    end
    for (int k = 0; k < 64; k++)
      input_x[k] = 32'sd1;
end

// Instantiate dense layer cores.
genvar n;
generate
    for (n = 0; n < 128; n++) begin : neuron_gen
        dense_layer_core neuron_core_inst (
            .clk           (clk_main_a0),
            .rst_n         (rst_main_n),
            .start         (start),
            .input_x       (input_x),
            .weights       (weights[n]),
            .bias          (biases[n]),
            .neuron_output (output_y[n]),
            .done          (done[n])
        );
    end
endgenerate

//---------------------------------------------------------------------
// User Timing and Measurement Signals
//---------------------------------------------------------------------
logic [63:0] start_time;
logic [63:0] end_time;
logic measurement_started, measurement_finished;
wire all_done = &done;

always_ff @(posedge clk_main_a0 or negedge rst_main_n) begin
    if (!rst_main_n) begin
        start_time          <= 0;
        end_time            <= 0;
        measurement_started <= 0;
        measurement_finished<= 0;
    end else begin
        if (!measurement_started && start) begin
            measurement_started <= 1;
            start_time <= sh_cl_glcount0; // sh_cl_glcount0 is provided by the shell (from cl_ports.vh)
        end
        if (measurement_started && all_done && !measurement_finished) begin
            measurement_finished <= 1;
            end_time <= sh_cl_glcount0;
        end
    end
end

//=============================================================================
// GLOBALS
//=============================================================================

  always_comb begin
     cl_sh_flr_done    = 'b1;
     cl_sh_status0     = 'b0;
     cl_sh_status1     = 'b0;
     cl_sh_status2     = 'b0;
     cl_sh_id0         = `CL_SH_ID0;
     cl_sh_id1         = `CL_SH_ID1;
     cl_sh_status_vled = 'b0;
     cl_sh_dma_wr_full = 'b0;
     cl_sh_dma_rd_full = 'b0;
  end


//=============================================================================
// PCIM
//=============================================================================

  // Cause Protocol Violations
  always_comb begin
    cl_sh_pcim_awaddr  = 'b0;
    cl_sh_pcim_awsize  = 'b0;
    cl_sh_pcim_awburst = 'b0;
    cl_sh_pcim_awvalid = 'b0;

    cl_sh_pcim_wdata   = 'b0;
    cl_sh_pcim_wstrb   = 'b0;
    cl_sh_pcim_wlast   = 'b0;
    cl_sh_pcim_wvalid  = 'b0;

    cl_sh_pcim_araddr  = 'b0;
    cl_sh_pcim_arsize  = 'b0;
    cl_sh_pcim_arburst = 'b0;
    cl_sh_pcim_arvalid = 'b0;
  end

  // Remaining CL Output Ports
  always_comb begin
    cl_sh_pcim_awid    = 'b0;
    cl_sh_pcim_awlen   = 'b0;
    cl_sh_pcim_awcache = 'b0;
    cl_sh_pcim_awlock  = 'b0;
    cl_sh_pcim_awprot  = 'b0;
    cl_sh_pcim_awqos   = 'b0;
    cl_sh_pcim_awuser  = 'b0;

    cl_sh_pcim_wid     = 'b0;
    cl_sh_pcim_wuser   = 'b0;

    cl_sh_pcim_arid    = 'b0;
    cl_sh_pcim_arlen   = 'b0;
    cl_sh_pcim_arcache = 'b0;
    cl_sh_pcim_arlock  = 'b0;
    cl_sh_pcim_arprot  = 'b0;
    cl_sh_pcim_arqos   = 'b0;
    cl_sh_pcim_aruser  = 'b0;

    cl_sh_pcim_rready  = 'b0;
  end

//=============================================================================
// PCIS
//=============================================================================

  // Cause Protocol Violations
  always_comb begin
    cl_sh_dma_pcis_bresp   = 'b0;
    cl_sh_dma_pcis_rresp   = 'b0;
    cl_sh_dma_pcis_rvalid  = 'b0;
  end

  // Remaining CL Output Ports
  always_comb begin
    cl_sh_dma_pcis_awready = 'b0;

    cl_sh_dma_pcis_wready  = 'b0;

    cl_sh_dma_pcis_bid     = 'b0;
    cl_sh_dma_pcis_bvalid  = 'b0;

    cl_sh_dma_pcis_arready  = 'b0;

    cl_sh_dma_pcis_rid     = 'b0;
    cl_sh_dma_pcis_rdata   = 'b0;
    cl_sh_dma_pcis_rlast   = 'b0;
    cl_sh_dma_pcis_ruser   = 'b0;
  end

//=============================================================================
// OCL
//=============================================================================

dense_layer_axil_slave #(
  .ADDR_WIDTH(32)
) bar0_axi_inst (
  .ocl_awaddr     (ocl_cl_awaddr),
  .ocl_awvalid    (ocl_cl_awvalid),
  .ocl_awready    (cl_ocl_awready),

  .ocl_wdata      (ocl_cl_wdata),
  .ocl_wstrb      (ocl_cl_wstrb),
  .ocl_wvalid     (ocl_cl_wvalid),
  .ocl_wready     (cl_ocl_wready),

  .ocl_bresp      (cl_ocl_bresp),
  .ocl_bvalid     (cl_ocl_bvalid),
  .ocl_bready     (ocl_cl_bready),

  .ocl_araddr     (ocl_cl_araddr),
  .ocl_arvalid    (ocl_cl_arvalid),
  .ocl_arready    (cl_ocl_arready),

  .ocl_rdata      (cl_ocl_rdata),
  .ocl_rresp      (cl_ocl_rresp),
  .ocl_rvalid     (cl_ocl_rvalid),
  .ocl_rready     (ocl_cl_rready),

  .clk            (clk_main_a0),
  .rst_n          (rst_main_n),

  // Connect user signals that the slave must read/write
  .output_y0       (output_y[0]),
  .debug_counter   (debug_counter_local),
  .start_time      (start_time),
  .end_time        (end_time),
  .all_done        (all_done),
  .start           (start),
  .debug_rst_local (debug_rst_local)
);

//=============================================================================
// SDA
//=============================================================================

  // Cause Protocol Violations
  always_comb begin
    cl_sda_bresp   = 'b0;
    cl_sda_rresp   = 'b0;
    cl_sda_rvalid  = 'b0;
  end

  // Remaining CL Output Ports
  always_comb begin
    cl_sda_awready = 'b0;
    cl_sda_wready  = 'b0;

    cl_sda_bvalid = 'b0;

    cl_sda_arready = 'b0;

    cl_sda_rdata   = 'b0;
  end

//=============================================================================
// SH_DDR
//=============================================================================

  logic         tie_zero      = '0;
  logic [ 15:0] tie_zero_id   = '0;
  logic [ 63:0] tie_zero_addr = '0;
  logic [  7:0] tie_zero_len  = '0;
  logic [511:0] tie_zero_data = '0;
  logic [ 63:0] tie_zero_strb = '0;

   sh_ddr
     #(
       .DDR_PRESENT (EN_DDR)
       )
   SH_DDR
     (
      .clk                       (clk_main_a0 ),
      .rst_n                     (rst_main_n  ),
      .stat_clk                  (clk_main_a0 ),
      .stat_rst_n                (rst_main_n  ),
      .CLK_DIMM_DP               (CLK_DIMM_DP ),
      .CLK_DIMM_DN               (CLK_DIMM_DN ),
      .M_ACT_N                   (M_ACT_N     ),
      .M_MA                      (M_MA        ),
      .M_BA                      (M_BA        ),
      .M_BG                      (M_BG        ),
      .M_CKE                     (M_CKE       ),
      .M_ODT                     (M_ODT       ),
      .M_CS_N                    (M_CS_N      ),
      .M_CLK_DN                  (M_CLK_DN    ),
      .M_CLK_DP                  (M_CLK_DP    ),
      .M_PAR                     (M_PAR       ),
      .M_DQ                      (M_DQ        ),
      .M_ECC                     (M_ECC       ),
      .M_DQS_DP                  (M_DQS_DP    ),
      .M_DQS_DN                  (M_DQS_DN    ),
      .cl_RST_DIMM_N             (RST_DIMM_N  ),
      .cl_sh_ddr_axi_awid        (tie_zero_id                  ),
      .cl_sh_ddr_axi_awaddr      (tie_zero_addr                ),
      .cl_sh_ddr_axi_awlen       (tie_zero_len                 ),
      .cl_sh_ddr_axi_awsize      (3'd6                         ),
      .cl_sh_ddr_axi_awvalid     (tie_zero                     ),
      .cl_sh_ddr_axi_awburst     (2'b01                        ),
      .cl_sh_ddr_axi_awuser      (            ),
      .cl_sh_ddr_axi_awready     (            ),
      .cl_sh_ddr_axi_wdata       (tie_zero_data                ),
      .cl_sh_ddr_axi_wstrb       (tie_zero_strb                ),
      .cl_sh_ddr_axi_wlast       (tie_zero                     ),
      .cl_sh_ddr_axi_wvalid      (tie_zero                     ),
      .cl_sh_ddr_axi_wready      (            ),
      .cl_sh_ddr_axi_bid         (            ),
      .cl_sh_ddr_axi_bresp       (            ),
      .cl_sh_ddr_axi_bvalid      (            ),
      .cl_sh_ddr_axi_bready      (tie_zero                     ),
      .cl_sh_ddr_axi_arid        (tie_zero_id                  ),
      .cl_sh_ddr_axi_araddr      (tie_zero_addr                ),
      .cl_sh_ddr_axi_arlen       (tie_zero_len                 ),
      .cl_sh_ddr_axi_arsize      (3'd6                         ),
      .cl_sh_ddr_axi_arvalid     (tie_zero                     ),
      .cl_sh_ddr_axi_arburst     (2'b01                        ),
      .cl_sh_ddr_axi_aruser      (            ),
      .cl_sh_ddr_axi_rready      (tie_zero                     ),
      .sh_ddr_stat_bus_addr      (8'd0                         ),
      .sh_ddr_stat_bus_wdata     (32'd0                        ),
      .sh_ddr_stat_bus_wr        (1'd0                         ),
      .sh_ddr_stat_bus_rd        (1'd0                         ),
      .cl_sh_ddr_axi_rid         (            ),
      .cl_sh_ddr_axi_rdata       (            ),
      .cl_sh_ddr_axi_rresp       (            ),
      .cl_sh_ddr_axi_rlast       (            ),
      .cl_sh_ddr_axi_rvalid      (            ),
      .sh_ddr_stat_bus_ack       (            ),
      .sh_ddr_stat_bus_rdata     (            ),
      .ddr_sh_stat_int           (            ),
      .sh_cl_ddr_is_ready        (            )
      );

  always_comb begin
    cl_sh_ddr_stat_ack   = 1'd1;
    cl_sh_ddr_stat_rdata = 'b0;
    cl_sh_ddr_stat_int   = 'b0;
  end

//=============================================================================
// USER-DEFIEND INTERRUPTS
//=============================================================================

  always_comb begin
    cl_sh_apppf_irq_req = 'b0;
  end

//=============================================================================
// VIRTUAL JTAG
//=============================================================================

  always_comb begin
    tdo = 'b0;
  end

//=============================================================================
// HBM MONITOR IO
//=============================================================================

  always_comb begin
    hbm_apb_paddr_1   = 'b0;
    hbm_apb_pprot_1   = 'b0;
    hbm_apb_psel_1    = 'b0;
    hbm_apb_penable_1 = 'b0;
    hbm_apb_pwrite_1  = 'b0;
    hbm_apb_pwdata_1  = 'b0;
    hbm_apb_pstrb_1   = 'b0;
    hbm_apb_pready_1  = 'b0;
    hbm_apb_prdata_1  = 'b0;
    hbm_apb_pslverr_1 = 'b0;

    hbm_apb_paddr_0   = 'b0;
    hbm_apb_pprot_0   = 'b0;
    hbm_apb_psel_0    = 'b0;
    hbm_apb_penable_0 = 'b0;
    hbm_apb_pwrite_0  = 'b0;
    hbm_apb_pwdata_0  = 'b0;
    hbm_apb_pstrb_0   = 'b0;
    hbm_apb_pready_0  = 'b0;
    hbm_apb_prdata_0  = 'b0;
    hbm_apb_pslverr_0 = 'b0;
  end

//=============================================================================
// C2C IO
//=============================================================================

  always_comb begin
    PCIE_EP_TXP    = 'b0;
    PCIE_EP_TXN    = 'b0;

    PCIE_RP_PERSTN = 'b0;
    PCIE_RP_TXP    = 'b0;
    PCIE_RP_TXN    = 'b0;
  end

endmodule // dense_layer
