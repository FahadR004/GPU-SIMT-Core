module tb_warp_scheduler;

localparam NUM_WARPS   = 4;
localparam NUM_THREADS = 32;
localparam DATA_WIDTH  = 32;

logic clk;
logic rst_n;
logic is_mem_op;

logic [DATA_WIDTH-1:0] warp_instr [NUM_WARPS-1:0];
logic [NUM_THREADS-1:0] warp_mask [NUM_WARPS-1:0]; // 4 elements (as many as the no. of warps) having 32-bits representing all threads in a warp

logic [NUM_THREADS-1:0] thread_stall; // from shared memory

logic [31:0] instr_out;
logic [NUM_THREADS-1:0] active_mask_out;
logic [$clog2(NUM_WARPS)-1:0] warp_id_out;
logic valid_out;

warp_scheduler #(
   .NUM_WARPS(NUM_WARPS),
   .NUM_THREADS(NUM_THREADS),
   .DATA_WIDTH(DATA_WIDTH)
) dut (
   .clk(clk),
   .rst_n(rst_n),
   .is_mem_op(is_mem_op),
   .warp_instr(warp_instr),
   .warp_mask(warp_mask),
   .thread_stall(thread_stall),
   .instr_out(instr_out),
   .active_mask_out(active_mask_out),
   .warp_id_out(warp_id_out),
   .valid_out(valid_out)
);

initial clk = 1'b0;
always #5 clk = ~clk;

initial begin
    $dumpfile("warp_scheduler.vcd");
    $dumpvars(0, tb_warp_scheduler);
end


// task automatic warp_init_instruction(
//     input logic [DATA_WIDTH-1:0] instr,
//     input logic [NUM_THREADS-1:0] mask,
//     input logic  warp_id
// ); 
//     begin
        
//     end
// endtask

// Since, instr_out is also updated combinationnally
assign is_mem_op = (instr_out[31:28] == 4'h8) || (instr_out[31:28] == 4'h9);

initial 
    begin 
        rst_n = 0; 
        thread_stall = '0;
        // Initializiting at the start of simulation, so that warp scheduler doesn't run with garbage values.
        warp_instr[0] = 32'b0000_00011_00001_00010_0_000000000000; // ADD
        warp_instr[1] = 32'b0001_00101_00100_00111_0_000000000000; // SUB
        warp_instr[2] = 32'b0110_11111_11111_11111_0_000000000000; // SLT
        warp_instr[3] = 32'b1000_00001_00010_00000_1_000000001000; // LOAD

        warp_mask[0] = 32'hFFFFFFFF; // All threads active
        warp_mask[1] = 32'h55555555; // Alternating threads active (01010..)
        warp_mask[2] = 32'hFFFFFFFF; // All threads active
        warp_mask[3] = 32'hAAAAAAAA; // Alternating threads active (10101..)
        @ (posedge clk); #1;

        rst_n = 1;
        @ (posedge clk); #1;

        $display(" Scenario 1: Round Robin");
        repeat(12) begin
            @(posedge clk); #1;
            $display("Cycle: warp_id=%0d valid=%0b instr=%h active_mask=%h",
                    warp_id_out, valid_out, instr_out, active_mask_out);
        end

        // Scenario 2: Memory op, no conflict 
        // Warp 3 is LOAD — when it issues, is_mem_op fires automatically via assign
        // Watch it go RUNNING → WAITING → READY
        $display("Scenario 2: Memory op, no conflict");
        thread_stall = '0;
        repeat(8) begin
            @(posedge clk); #1;
            $display("warp_id=%0d valid=%0b is_mem_op=%0b",
                    warp_id_out, valid_out, is_mem_op);
        end

        //  Scenario 3: Memory op with bank conflict 
        $display("Scenario 3: Bank conflict");
         while (warp_id_out !== 2'd3 || !valid_out) begin
            @(posedge clk); 
          end
        #1; 

      $display("Warp 3 is issued! Waiting out its pipeline latency");
        // Wait 3 clock cycles while Warp 3 is in the RUNNING state
        repeat(3) begin
          @(posedge clk); #1;
        end

        // Warp 3 is now entering WAITING state. Apply the stall
        $display("Injecting bank conflict stall on WAITING state");
        thread_stall = 32'h0000_00F0; 

        // Track it sitting in the STALLED state
        repeat (4) begin
          @(posedge clk); #1;
          $display("warp_id=%0d active_mask=%h stall=%h state[3]=%0d",
                   warp_id_out, active_mask_out, thread_stall, dut.state[3]);
        end

        // Resolve conflict and watch it recover
        $display(">>> Resolving conflict...");
        thread_stall = '0;

        repeat(6) begin
          @(posedge clk); #1;
          $display("warp_id=%0d active_mask=%h state[3]=%0d",
                   warp_id_out, active_mask_out, dut.state[3]);
        end
        // Resolve conflict
        thread_stall = '0;
        
        repeat(6) begin
            @(posedge clk); #1;
            $display("warp_id=%0d active_mask=%h",
                    warp_id_out, active_mask_out);
        end

        #10;

        $finish;    
    end

endmodule