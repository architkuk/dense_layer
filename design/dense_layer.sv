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
      parameter EN_HBM = 0,
      parameter IN_FEATURES = 128,
      parameter OUT_FEATURES = 64
    )
    (
      `include "cl_ports.vh"
    );

`include "cl_id_defines.vh" // CL ID defines required for all examples
`include "dense_layer_defines.vh"


//=============================================================================
// GLOBALS
//=============================================================================

  // Add signals for dense_layer_core
  logic [1023:0] core_data_in;
  logic core_data_in_valid;
  logic [511:0] core_data_out;
  logic core_data_out_valid;

  // Instantiate dense_layer_core
  dense_layer_core #(
    .IN_FEATURES(IN_FEATURES),
    .OUT_FEATURES(OUT_FEATURES)
  ) dense_layer_core_inst (
    .clk(clk_main_a0),
    .rst(!rst_main_n),
    .data_in(core_data_in),
    .data_in_valid(core_data_in_valid),
    .data_out(core_data_out),
    .data_out_valid(core_data_out_valid)
  );

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

  // Internal memory and registers
  logic [31:0] internal_mem [0:1023];
  logic [9:0]  addr_reg;
  logic [7:0]  arlen_reg;

  // Output registers
  logic        pcis_awready_reg;
  logic        pcis_wready_reg;
  logic        pcis_bvalid_reg;
  logic [1:0]  pcis_bresp_reg;
  logic        pcis_arready_reg;
  logic        pcis_rvalid_reg;
  logic [511:0] pcis_rdata_reg;
  logic [1:0]  pcis_rresp_reg;

  // AXI-Lite slave interface state
  typedef enum logic [1:0] {
    IDLE,
    WRITE_DATA,
    WRITE_RESP,
    READ_DATA
  } axi_state_t;
  
  axi_state_t curr_state;

  // Single source of truth for AXI signals
  always_ff @(posedge clk_main_a0) begin
    if (!rst_main_n) begin
      curr_state <= IDLE;
      addr_reg <= '0;
      arlen_reg <= '0;
      
      // Initialize output registers
      pcis_awready_reg <= 1'b1;
      pcis_wready_reg  <= 1'b1;
      pcis_bvalid_reg  <= 1'b0;
      pcis_bresp_reg   <= 2'b00;
      pcis_arready_reg <= 1'b1;
      pcis_rvalid_reg  <= 1'b0;
      pcis_rdata_reg   <= '0;
      pcis_rresp_reg   <= 2'b00;
    end else begin
      case (curr_state)
        IDLE: begin
          pcis_awready_reg <= 1'b1;
          pcis_wready_reg  <= 1'b1;
          pcis_arready_reg <= 1'b1;
          pcis_bvalid_reg  <= 1'b0;
          pcis_rvalid_reg  <= 1'b0;
          
          if (sh_cl_dma_pcis_awvalid && pcis_awready_reg) begin
            addr_reg <= sh_cl_dma_pcis_awaddr[11:2];
            pcis_awready_reg <= 1'b0;
            curr_state <= WRITE_DATA;
          end else if (sh_cl_dma_pcis_arvalid && pcis_arready_reg) begin
            addr_reg <= sh_cl_dma_pcis_araddr[11:2];
            arlen_reg <= sh_cl_dma_pcis_arlen;
            pcis_arready_reg <= 1'b0;
            curr_state <= READ_DATA;
          end
        end

        WRITE_DATA: begin
          if (sh_cl_dma_pcis_wvalid && pcis_wready_reg) begin
            if (addr_reg < IN_FEATURES * OUT_FEATURES) begin
                // Write to weight memory
                dense_layer_core_inst.weight_rom[addr_reg / OUT_FEATURES][addr_reg % OUT_FEATURES] <= sh_cl_dma_pcis_wdata[31:0];
            end else if (addr_reg < (IN_FEATURES * OUT_FEATURES + OUT_FEATURES)) begin
                // Write to bias memory
                dense_layer_core_inst.bias_rom[addr_reg - (IN_FEATURES * OUT_FEATURES)] <= sh_cl_dma_pcis_wdata[31:0];
            end else begin
                // Write to input/output memory
                internal_mem[addr_reg] <= sh_cl_dma_pcis_wdata[31:0];
            end
            pcis_wready_reg <= 1'b0;
            pcis_bvalid_reg <= 1'b1;
            pcis_bresp_reg <= 2'b00;
            curr_state <= WRITE_RESP;
          end
        end

        WRITE_RESP: begin
          if (sh_cl_dma_pcis_bready && pcis_bvalid_reg) begin
            pcis_bvalid_reg <= 1'b0;
            curr_state <= IDLE;
          end
        end

        READ_DATA: begin
          pcis_rvalid_reg <= 1'b1;
          pcis_rresp_reg <= 2'b00;
          pcis_rdata_reg <= {480'b0, internal_mem[addr_reg]};
          
          if (sh_cl_dma_pcis_rready && pcis_rvalid_reg) begin
            if (arlen_reg == 0) begin
              pcis_rvalid_reg <= 1'b0;
              curr_state <= IDLE;
            end else begin
              arlen_reg <= arlen_reg - 1;
              addr_reg <= addr_reg + 1;
            end
          end
        end

        default: begin
          curr_state <= IDLE;
        end
      endcase
    end
  end

  // Connect output registers to interface signals
  assign cl_sh_dma_pcis_awready = pcis_awready_reg;
  assign cl_sh_dma_pcis_wready  = pcis_wready_reg;
  assign cl_sh_dma_pcis_bvalid  = pcis_bvalid_reg;
  assign cl_sh_dma_pcis_bresp   = pcis_bresp_reg;
  assign cl_sh_dma_pcis_arready = pcis_arready_reg;
  assign cl_sh_dma_pcis_rvalid  = pcis_rvalid_reg;
  assign cl_sh_dma_pcis_rdata   = pcis_rdata_reg;
  assign cl_sh_dma_pcis_rresp   = pcis_rresp_reg;

  // PCIe signals
  assign PCIE_EP_TXP = '0;
  assign PCIE_EP_TXN = '0;
  assign PCIE_RP_PERSTN = '0;
  assign PCIE_RP_TXP = '0;
  assign PCIE_RP_TXN = '0;

  // Tie off unused interfaces
  assign cl_ocl_tx_q = '0;
  assign cl_ocl_xaction_id = '0;
  assign cl_sh_ddr_awid = '0;
  assign cl_sh_ddr_awaddr = '0;
  assign cl_sh_ddr_awlen = '0;
  assign cl_sh_ddr_awsize = '0;
  assign cl_sh_ddr_awburst = '0;
  assign cl_sh_ddr_awvalid = '0;
  assign cl_sh_ddr_wid = '0;
  assign cl_sh_ddr_wdata = '0;
  assign cl_sh_ddr_wstrb = '0;
  assign cl_sh_ddr_wlast = '0;
  assign cl_sh_ddr_wvalid = '0;
  assign cl_sh_ddr_bready = '0;
  assign cl_sh_ddr_arid = '0;
  assign cl_sh_ddr_araddr = '0;
  assign cl_sh_ddr_arlen = '0;
  assign cl_sh_ddr_arsize = '0;
  assign cl_sh_ddr_arburst = '0;
  assign cl_sh_ddr_arvalid = '0;
  assign cl_sh_ddr_rready = '0;

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
    cl_sh_dma_pcis_bid     = 'b0;
    cl_sh_dma_pcis_bvalid  = 'b0;

    cl_sh_dma_pcis_rid     = 'b0;
    cl_sh_dma_pcis_rdata   = 'b0;
    cl_sh_dma_pcis_rlast   = 'b0;
    cl_sh_dma_pcis_ruser   = 'b0;
  end

//=============================================================================
// OCL
//=============================================================================

  // Cause Protocol Violations
  always_comb begin
    cl_ocl_bresp   = 'b0;
    cl_ocl_rresp   = 'b0;
    cl_ocl_rvalid  = 'b0;
  end

  // Remaining CL Output Ports
  always_comb begin
    cl_ocl_awready = 'b0;
    cl_ocl_wready  = 'b0;

    cl_ocl_bvalid = 'b0;

    cl_ocl_arready = 'b0;

    cl_ocl_rdata   = 'b0;
  end

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

   sh_ddr
     #(
       .DDR_PRESENT (EN_DDR)
       )
   SH_DDR
     (
      .clk                       (clk_main_a0 ),
      .rst_n                     (            ),
      .stat_clk                  (clk_main_a0 ),
      .stat_rst_n                (            ),
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
      .cl_sh_ddr_axi_awid        (            ),
      .cl_sh_ddr_axi_awaddr      (            ),
      .cl_sh_ddr_axi_awlen       (            ),
      .cl_sh_ddr_axi_awsize      (            ),
      .cl_sh_ddr_axi_awvalid     (            ),
      .cl_sh_ddr_axi_awburst     (            ),
      .cl_sh_ddr_axi_awuser      (            ),
      .cl_sh_ddr_axi_awready     (            ),
      .cl_sh_ddr_axi_wdata       (            ),
      .cl_sh_ddr_axi_wstrb       (            ),
      .cl_sh_ddr_axi_wlast       (            ),
      .cl_sh_ddr_axi_wvalid      (            ),
      .cl_sh_ddr_axi_wready      (            ),
      .cl_sh_ddr_axi_bid         (            ),
      .cl_sh_ddr_axi_bresp       (            ),
      .cl_sh_ddr_axi_bvalid      (            ),
      .cl_sh_ddr_axi_bready      (            ),
      .cl_sh_ddr_axi_arid        (            ),
      .cl_sh_ddr_axi_araddr      (            ),
      .cl_sh_ddr_axi_arlen       (            ),
      .cl_sh_ddr_axi_arsize      (            ),
      .cl_sh_ddr_axi_arvalid     (            ),
      .cl_sh_ddr_axi_arburst     (            ),
      .cl_sh_ddr_axi_aruser      (            ),
      .cl_sh_ddr_axi_arready     (            ),
      .cl_sh_ddr_axi_rid         (            ),
      .cl_sh_ddr_axi_rdata       (            ),
      .cl_sh_ddr_axi_rresp       (            ),
      .cl_sh_ddr_axi_rlast       (            ),
      .cl_sh_ddr_axi_rvalid      (            ),
      .cl_sh_ddr_axi_rready      (            ),
      .sh_ddr_stat_bus_addr      (            ),
      .sh_ddr_stat_bus_wdata     (            ),
      .sh_ddr_stat_bus_wr        (            ),
      .sh_ddr_stat_bus_rd        (            ),
      .sh_ddr_stat_bus_ack       (            ),
      .sh_ddr_stat_bus_rdata     (            ),
      .ddr_sh_stat_int           (            ),
      .sh_cl_ddr_is_ready        (            )
      );

  always_comb begin
    cl_sh_ddr_stat_ack   = 'b0;
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

endmodule // dense_layer
