`include "common_base_test.svh"

module dense_layer_base_test();
   import tb_type_defines_pkg::*;

   logic clk_main_a0;
   logic rst_main_n;
   logic signed [31:0] input_x [0:63];
   logic signed [31:0] weights [0:127][0:63];
   logic signed [31:0] biases [0:127];
   logic signed [31:0] output_y [0:127];

   // Explicit clock generation aligned with AWS HDK framework
   initial clk_main_a0 = 0;
   always #2.5ns clk_main_a0 = ~clk_main_a0;  // 200 MHz clock (5ns period)

   // Initialize input vector to ones for testing
   initial begin
      for (int k = 0; k < 64; k++)
         input_x[k] = 32'sd1;
   end

   initial begin
      $readmemh("/home/ubuntu/src/project_data/aws-fpga/hdk/cl/examples/dense_layer/data/weights.hex", weights);
      $readmemh("/home/ubuntu/src/project_data/aws-fpga/hdk/cl/examples/dense_layer/data/biases.hex", biases);
      $display("Weights and biases loaded successfully.");
   end

   // Instantiate multiple dense_layer_core modules in parallel
   genvar n;
   generate
      for (n = 0; n < 128; n++) begin : neuron_gen
         dense_layer_core neuron_core_inst (
            .clk(clk_main_a0),
            .rst_n(rst_main_n),
            .input_x(input_x),
            .weights(weights[n]),
            .bias(biases[n]),
            .neuron_output(output_y[n])
         );
      end
   endgenerate

   initial begin
      $display("Simulation current working directory:");
      $system("pwd");

      // Call power-up to handle initial setup (resets, etc.)
      tb.power_up(.clk_recipe_a(ClockRecipe::A0),
                  .clk_recipe_b(ClockRecipe::B0),
                  .clk_recipe_c(ClockRecipe::C0));

      // Manually control reset
      rst_main_n = 0;
      #100ns;
      rst_main_n = 1;

      // Wait sufficient cycles for computation
      #500ns;

      // Print each of the 128 outputs clearly
      for (int i = 0; i < 128; i++) begin
         $display("dense_layer output_y[%0d]: %d (binary: %b)", i, output_y[i], output_y[i]);
      end

      // Complete simulation
      tb.power_down();

      report_pass_fail_status();
      $finish;
   end
endmodule
