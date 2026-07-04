`timescale 1ns/1ps
module register_file #(
    parameter NUM_WARPS = 4,
    parameter NUM_THREADS = 32,
    parameter NUM_REGS_PER_TH = 32,
    parameter DATA_WIDTH = 32
) ( 
    input logic clk,
    input logic rst_n,
    
    input logic [$clog2(NUM_WARPS)-1:0] read_warp,        
    input logic [$clog2(NUM_REGS_PER_TH)-1:0] regA,
    input logic [$clog2(NUM_REGS_PER_TH)-1:0] regB,
    output logic [DATA_WIDTH-1:0] read_data_a [NUM_THREADS-1:0],
    output logic [DATA_WIDTH-1:0] read_data_b [NUM_THREADS-1:0],
   
    input logic write_en, 
    input logic [DATA_WIDTH-1:0] write_data [NUM_THREADS-1:0],
    input logic [NUM_THREADS-1:0] write_mask, // For branch divergence
    input logic [$clog2(NUM_WARPS)-1:0] write_warp,
    input logic [$clog2(NUM_REGS_PER_TH)-1:0] write_reg
);

logic [DATA_WIDTH-1:0] reg_file [NUM_THREADS-1:0][NUM_WARPS-1:0][NUM_REGS_PER_TH-1:0];

// integer init_t, init_w, init_r;
// initial begin
//     for (init_t = 0; init_t < NUM_THREADS; init_t = init_t + 1)
//         for (init_w = 0; init_w < NUM_WARPS; init_w = init_w + 1)
//             for (init_r = 0; init_r < NUM_REGS_PER_TH; init_r = init_r + 1)
//                 reg_file[init_t][init_w][init_r] = {DATA_WIDTH{1'b0}};
// end

 
// Write Data
integer t,w,r;
integer i;
always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n) 
            begin
                for (t = 0; t < NUM_THREADS; t = t + 1) 
                    for (w = 0; w < NUM_WARPS; w = w + 1)
                        for (r = 0; r < NUM_REGS_PER_TH; r = r + 1)
                            reg_file[t][w][r] <=  {DATA_WIDTH{1'b0}};  
            end        
        else if (write_en)
            begin
                for (i = 0; i < NUM_THREADS; i = i + 1)
                    begin
                        if (write_mask[i])
                            reg_file[i][write_warp][write_reg] <= write_data[i];
                    end
            end
    end

// Read Data
// In a CPU, we would have instructions from the same thread run after another meaning we can have RAW hazard meaning it should read after write but the dependent instruction is unable to read updated value and reads old value
// In a GPU, warp will go through the ALU, which has a 2-cycle latency, so, warp 0 executes an instruction in 4 cycles. Remember, all threads in a warp execute the same instruction. Thus, the warp moves to the next instruction after 4 cycles making it impossible to create a RAW hazard, assuming that the scheduler would do latency hiding through warp switching (which is present in GPUs) and schedule the next warp to read from the register file, making our 4 warps come in handy.
integer th;
always_comb
    begin 
        begin
            for (th = 0; th < NUM_THREADS; th = th + 1)
                begin
                    read_data_a[th] = reg_file[th][read_warp][regA];
                    read_data_b[th] = reg_file[th][read_warp][regB];
                end
        end 
    end
endmodule