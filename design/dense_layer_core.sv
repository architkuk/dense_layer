module dense_layer_core (
    input logic clk,
    input logic rst_n,
    input logic signed [31:0] input_x [0:63],
    input logic signed [31:0] weights [0:63],
    input logic signed [31:0] bias,
    output logic signed [31:0] neuron_output,
    output logic done
);

// Intermediate product array
logic signed [63:0] products [0:63];
logic signed [63:0] accumulator;

// Compute products in parallel using combinational logic
genvar i;
generate
    for (i = 0; i < 64; i++) begin : multiply
        always_comb begin
            products[i] = input_x[i] * weights[i];
        end
    end
endgenerate

// Sum the products and bias in parallel (tree-like adder structure)
always_comb begin
    accumulator = bias;
    for (int j = 0; j < 64; j++) begin
        accumulator += products[j];
    end
end

// Register outputs
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        neuron_output <= 32'd0;
        done <= 1'b0;
    end else begin
        neuron_output <= accumulator[31:0];
        done <= 1'b1;
    end
end

endmodule
