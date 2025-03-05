module dense_layer_core (
    input logic clk,
    input logic rst_n,
    input logic signed [31:0] input_x [0:63],
    input logic signed [31:0] weights [0:63],
    input logic signed [31:0] bias,
    output logic signed [31:0] neuron_output
);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        neuron_output <= 32'd0;
    end else begin
        neuron_output <= bias;
        for (int i = 0; i < 64; i++) begin
            neuron_output <= neuron_output + weights[i] * input_x[i];
        end
    end
end

endmodule
