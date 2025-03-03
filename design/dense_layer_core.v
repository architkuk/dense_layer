module dense_layer_core
    #(
      parameter IN_FEATURES = 128,
      parameter OUT_FEATURES = 64
    )
    (
    input clk,
    input rst,
    input [1023:0] data_in,  // Flattened: 128 x 8 bits = 1024 bits
    input data_in_valid,
    output reg [511:0] data_out,  // Flattened: 64 x 8 bits = 512 bits
    output reg data_out_valid
);

localparam INTEGER_SCALE = 65536;

// Change logic declarations to reg/wire
reg [31:0] weight_rom [0:IN_FEATURES-1][0:OUT_FEATURES-1];
reg [31:0] bias_rom [0:OUT_FEATURES-1];
reg [31:0] activation [0:OUT_FEATURES-1];
reg [31:0] input_vector [0:IN_FEATURES-1];
reg calculation_done;

`include "weights_and_biases.vh"

// Input stage with named block
always @(posedge clk) begin : input_stage
    integer i;
    if (rst) begin
        calculation_done <= 0;
        for (i = 0; i < IN_FEATURES; i = i + 1) begin
            input_vector[i] <= 0;
        end
    end else if (data_in_valid) begin
        for (i = 0; i < IN_FEATURES; i = i + 1) begin
            input_vector[i] <= data_in[i*8 +: 8];
        end
        calculation_done <= 1;
    end
end

// Computation stage with named block
always @(*) begin : compute_stage
    integer i, j;
    for (i = 0; i < OUT_FEATURES; i = i + 1) begin
        activation[i] = bias_rom[i];
        for (j = 0; j < IN_FEATURES; j = j + 1) begin
            activation[i] = activation[i] + (weight_rom[j][i] * input_vector[j]);
        end
    end
end

// Output stage with named block
always @(posedge clk) begin : output_stage
    integer i;
    if (rst) begin
        data_out_valid <= 0;
        for (i = 0; i < OUT_FEATURES; i = i + 1) begin
            data_out[i*8 +: 8] <= 0;
        end
    end else begin
        data_out_valid <= calculation_done;
        if (calculation_done) begin
            for (i = 0; i < OUT_FEATURES; i = i + 1) begin
                data_out[i*8 +: 8] <= activation[i] / INTEGER_SCALE;
            end
        end
    end
end

endmodule
