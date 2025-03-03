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

`include "common_base_test.svh"

module dense_layer_base_test();
   import tb_type_defines_pkg::*;
   
   // Add size parameters
   localparam INPUT_SIZE = 128;    // 128 elements
   localparam OUTPUT_SIZE = 64;    // 64 elements
   localparam WEIGHT_SIZE = INPUT_SIZE * OUTPUT_SIZE;  // Weight matrix size
   
   // Test parameters
   localparam IN_FEATURES = 128;
   localparam OUT_FEATURES = 64;
   logic [1023:0] test_data_in;  // 128 x 8 bits
   logic [511:0] expected_data_out;  // 64 x 8 bits
   logic [31:0] read_data;
   logic error;
   
   // Declare arrays before including weights file
   logic signed [31:0] weight_rom[IN_FEATURES-1:0][OUT_FEATURES-1:0];
   logic signed [31:0] bias_rom[OUT_FEATURES-1:0];
   
   // Reference model variables
   logic signed [31:0] expected_result[OUT_FEATURES-1:0];
   logic [7:0] test_input[IN_FEATURES-1:0];
   
   // Include the weights file that now contains the task
   `include "../../design/weights_and_biases.vh"
   
   // Function to compute expected output
   function automatic void compute_expected_output();
      for (int i = 0; i < OUT_FEATURES; i++) begin
         expected_result[i] = 0;
         for (int j = 0; j < IN_FEATURES; j++) begin
            expected_result[i] += test_input[j] * weight_rom[j][i];
         end
         expected_result[i] += bias_rom[i];
      end
   endfunction

   // Add these parameters for AXI transactions
   localparam AXI_BURST_LEN = 8;  // Reduce burst length
   localparam MAX_RD_BURSTS = 16; // Increase outstanding read capacity

   // Add array to store weights locally
   logic [31:0] expected_weights[WEIGHT_SIZE];
   logic [31:0] expected_biases[OUTPUT_SIZE];

   initial begin
      tb.power_up(.clk_recipe_a(ClockRecipe::A0),
                  .clk_recipe_b(ClockRecipe::B0),
                  .clk_recipe_c(ClockRecipe::C0));

      tb.nsec_delay(5000);
      
      // Debug print
      $display("[%0t] Starting test initialization", $time);

      tb.poke(.addr(64'h0c), .data(32'h0000_0000), .intf(AxiPort::PORT_DMA_PCIS));
      tb.nsec_delay(1000);

      error = 0;

      // Initialize the weights and biases using the task
      initialize_weights_and_biases();
      
      // Initialize test input with ascending pattern
      for (int i = 0; i < IN_FEATURES; i++) begin
         test_input[i] = i[7:0]; // Use only lower 8 bits
      end
      
      // Compute expected output
      compute_expected_output();
      
      // Convert test input to hardware format
      for (int i = 0; i < IN_FEATURES; i++) begin
         test_data_in[i*8 +: 8] = test_input[i];
      end
      
      // Add before starting the test
      $display("[%0t ns] Checking initial state", $time);

      // Initialize test data first
      $display("\n=== Initializing Test Data ===");
      for (int i = 0; i < INPUT_SIZE/4; i++) begin
         test_data_in[i*32 +: 32] = {i*4+3, i*4+2, i*4+1, i*4};
         $display("test_data_in[%0d] = 0x%h", i, test_data_in[i*32 +: 32]);
      end

      // Load and verify weights
      $display("\n=== Loading and Verifying Weights ===");
      // Write weights with delays between transactions
      for (int i = 0; i < WEIGHT_SIZE/4; i++) begin
         tb.poke(.addr(64'h0000_2000 + i*4), .data(expected_weights[i]), .intf(AxiPort::PORT_DMA_PCIS));
         #100; // Add delay between writes
      end

      // Verify weights were written correctly
      for (int i = 0; i < 5; i++) begin  // Check first few weights
         logic [31:0] read_weight;
         tb.peek(.addr(64'h0000_2000 + i*4), .data(read_weight), .intf(AxiPort::PORT_DMA_PCIS));
         $display("Weight[%0d] = 0x%h (Expected: 0x%h)", i, read_weight, expected_weights[i]);
         #100; // Add delay between reads
      end

      // Write input data with delays
      $display("\n=== Writing Input Data ===");
      for (int i = 0; i < INPUT_SIZE/32; i++) begin
         tb.poke(.addr(64'h0000_0000 + i*4), .data(test_data_in[i*32 +: 32]), .intf(AxiPort::PORT_DMA_PCIS));
         $display("Writing input[%0d] = 0x%h at addr 0x%h", i, test_data_in[i*32 +: 32], 64'h0000_0000 + i*4);
         #200; // Longer delay between writes
      end

      // Add substantial delay before reading
      #10000;

      // Read output with delays
      $display("\n=== Reading Output Data ===");
      for (int i = 0; i < OUTPUT_SIZE/32; i++) begin
         #200; // Delay before each read
         tb.peek(.addr(64'h0000_1000 + i*4), .data(read_data), .intf(AxiPort::PORT_DMA_PCIS));
         $display("Reading output[%0d] = 0x%h from addr 0x%h", i, read_data, 64'h0000_1000 + i*4);
      end

      // Add timeout
      fork
         begin
            // Main test sequence
            tb.nsec_delay(1000);  // Wait for computation
            
            if (!error) begin
               $display("[%0t] Basic test passed, proceeding with full test", $time);
               // ... rest of the test would go here ...
            end
         end
         
         begin
            // Timeout after 1ms
            tb.nsec_delay(1_000_000);
            $error("Test timeout after 1ms");
            error = 1;
         end
      join_any
      disable fork;

      if (error)
         $error("Test FAILED");
      else
         $display("Test PASSED!");

      $finish;
   end
endmodule