module dense_layer_axil_slave #(
  parameter ADDR_WIDTH = 32
)
(
  //----------------------------------------------------------------------------
  // AXI-Lite Slave Interface to BAR0
  //----------------------------------------------------------------------------
  input  logic [ADDR_WIDTH-1:0] ocl_awaddr,
  input  logic                  ocl_awvalid,
  output logic                  ocl_awready,

  input  logic [31:0]           ocl_wdata,
  input  logic [3:0]            ocl_wstrb,
  input  logic                  ocl_wvalid,
  output logic                  ocl_wready,

  output logic [1:0]            ocl_bresp,
  output logic                  ocl_bvalid,
  input  logic                  ocl_bready,

  input  logic [ADDR_WIDTH-1:0] ocl_araddr,
  input  logic                  ocl_arvalid,
  output logic                  ocl_arready,

  output logic [31:0]           ocl_rdata,
  output logic [1:0]            ocl_rresp,
  output logic                  ocl_rvalid,
  input  logic                  ocl_rready,

  //----------------------------------------------------------------------------
  // Clock/Reset
  //----------------------------------------------------------------------------
  input  logic                  clk,
  input  logic                  rst_n,

  //----------------------------------------------------------------------------
  // User Signals That We Expose or Control
  //----------------------------------------------------------------------------
  input  logic signed [31:0]  output_y0,
  input  logic [31:0]         debug_counter,
  input  logic [63:0]         start_time,
  input  logic [63:0]         end_time,
  input  logic                all_done,

  output logic                start,
  output logic                debug_rst_local
);


  //--------------------------------------------------------------------------
  //  AXI-Lite Address Map
  //--------------------------------------------------------------------------
  localparam REG_START           = 32'h0000_0000;
  localparam REG_DEBUG_RST_LOCAL = 32'h0000_0004;
  localparam REG_DEBUG_COUNTER   = 32'h0000_0008;
  localparam REG_OUTPUT_Y0       = 32'h0000_000C;
  localparam REG_START_TIME_L    = 32'h0000_0010;
  localparam REG_START_TIME_H    = 32'h0000_0014;
  localparam REG_END_TIME_L      = 32'h0000_0018;
  localparam REG_END_TIME_H      = 32'h0000_001C;
  localparam REG_ALL_DONE        = 32'h0000_0020;

  // R/W user registers
  logic reg_start;
  logic reg_debug_rst;

  //------------------------------------------------------------------------------
  // Write Address/Write Data (Two-Phase)
  //------------------------------------------------------------------------------

  // States for the write FSM
  typedef enum logic [1:0] {
    W_IDLE       = 2'd0,
    W_WAIT_DATA  = 2'd1,
    W_RESP       = 2'd2
  } wstate_e;

  wstate_e wstate, wstate_n;
  logic [ADDR_WIDTH-1:0] awaddr_reg;

  // Output signals
  logic awready_r;
  logic wready_r;
  logic bvalid_r;

  // Next-state logic
  always_comb begin
    wstate_n   = wstate;          // default no-change
    awready_r  = 1'b0;
    wready_r   = 1'b0;
    bvalid_r   = (wstate == W_RESP);

    case(wstate)
      W_IDLE: begin
        // Wait for AWVALID
        awready_r = 1'b1;
        if (ocl_awvalid) begin
          // Latch address
          wstate_n    = W_WAIT_DATA;
        end
      end

      W_WAIT_DATA: begin
        // Wait for WVALID
        wready_r = 1'b1;
        if (ocl_wvalid) begin
          // We can store the data into local registers here
          wstate_n = W_RESP;
        end
      end

      W_RESP: begin
        // BVALID is asserted
        if (ocl_bready) begin
          wstate_n = W_IDLE;
        end
      end
    endcase
  end

  // Write FSM sequential
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      wstate     <= W_IDLE;
      awaddr_reg <= '0;
    end else begin
      wstate <= wstate_n;
      // Latch address in W_IDLE if AWVALID is seen
      if ((wstate == W_IDLE) && ocl_awvalid && awready_r) begin
        awaddr_reg <= ocl_awaddr;
      end

      // Actually update local user registers if in W_WAIT_DATA and WVALID
      if ((wstate == W_WAIT_DATA) && ocl_wvalid && wready_r) begin
        case (awaddr_reg)
          REG_START: begin
            if(ocl_wstrb[0])
              reg_start <= ocl_wdata[0];
          end
          REG_DEBUG_RST_LOCAL: begin
            if(ocl_wstrb[0])
              reg_debug_rst <= ocl_wdata[0];
          end
          // others are read-only
        endcase
      end
    end
  end

  // Assign outputs
  assign ocl_awready = awready_r;
  assign ocl_wready  = wready_r;
  assign ocl_bresp   = 2'b00;   // always OKAY
  assign ocl_bvalid  = bvalid_r;

  // Connect to user logic
  assign start           = reg_start;
  assign debug_rst_local = reg_debug_rst;

  //------------------------------------------------------------------------------
  // Read Channel (AR -> R)
  //------------------------------------------------------------------------------
  typedef enum logic [1:0] {
    R_IDLE = 2'd0,
    R_DATA = 2'd1
  } rstate_e;

  rstate_e rstate, rstate_n;
  logic [ADDR_WIDTH-1:0] araddr_reg;
  logic rvalid_r;
  logic arready_r;

  always_comb begin
    rstate_n  = rstate;
    arready_r = 1'b0;
    rvalid_r  = (rstate == R_DATA);

    case(rstate)
      R_IDLE: begin
        arready_r = 1'b1; // accept AR
        if (ocl_arvalid) begin
          rstate_n = R_DATA;
        end
      end

      R_DATA: begin
        // RVALID=1
        if (ocl_rready) begin
          rstate_n = R_IDLE;
        end
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      rstate    <= R_IDLE;
      araddr_reg <= '0;
    end else begin
      rstate <= rstate_n;
      // Latch address on AR handshake
      if ((rstate == R_IDLE) && ocl_arvalid && arready_r) begin
        araddr_reg <= ocl_araddr;
      end
    end
  end

  assign ocl_arready = arready_r;
  assign ocl_rvalid  = rvalid_r;
  assign ocl_rresp   = 2'b00; // OKAY

  // Read Data MUX
  logic [31:0] read_data;
  always_comb begin
    unique case (araddr_reg)
      REG_START:            read_data = {31'b0, reg_start};
      REG_DEBUG_RST_LOCAL:  read_data = {31'b0, reg_debug_rst};
      REG_DEBUG_COUNTER:    read_data = debug_counter;
      REG_OUTPUT_Y0:        read_data = output_y0;
      REG_START_TIME_L:     read_data = start_time[31:0];
      REG_START_TIME_H:     read_data = start_time[63:32];
      REG_END_TIME_L:       read_data = end_time[31:0];
      REG_END_TIME_H:       read_data = end_time[63:32];
      REG_ALL_DONE:         read_data = {31'b0, all_done};
      default:              read_data = 32'hDEAD_BEEF;
    endcase
  end

  assign ocl_rdata = read_data;

endmodule
