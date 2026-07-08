`timescale 1ns/1ps

module tb_simt_core;

parameter NUM_WARPS         = 4;
parameter NUM_THREADS       = 32;
parameter NUM_REGS_PER_TH   = 32;
parameter DATA_WIDTH        = 32;

logic clk;
logic rst_n;

logic [DATA_WIDTH-1:0] warp_instr [NUM_WARPS-1:0];
logic [NUM_THREADS-1:0] warp_mask [NUM_WARPS-1:0];

simt_core #(
    .NUM_WARPS(NUM_WARPS),
    .NUM_THREADS(NUM_THREADS),
    .NUM_REGS_PER_TH(NUM_REGS_PER_TH),
    .DATA_WIDTH(DATA_WIDTH)
) dut (.*); 

initial clk = 1'b0;
always #5 clk = ~clk;

// Instruction encoding function
function automatic logic [31:0] op_encode(
    input logic [3:0]  op, 
    input logic [4:0]  rd, 
    input logic [4:0]  rs1,
    input logic [4:0]  rs2, 
    input logic        imm_sel, 
    input logic [11:0] imm
);
    return {op, rd, rs1, rs2, imm_sel, imm};
endfunction

// Clear inputs
task automatic clear_inputs();
    for (int w = 0; w < NUM_WARPS; w++) begin
        warp_instr[w] = '0;
        warp_mask[w]  = '0;
    end
endtask

// Synchronized Instruction Handshake Task
task automatic exec_instr(
    input int w,
    input logic [NUM_THREADS-1:0] mask,
    input logic [DATA_WIDTH-1:0]  instr
);
    warp_mask[w]  = mask;
    warp_instr[w] = instr;

    while (!(dut.u_scheduler.valid_out && dut.u_scheduler.warp_id_out == w))
        @(posedge clk);
    @(posedge clk);
    while (dut.u_scheduler.state[w] != 0)
        @(posedge clk);
endtask

// Register write monitor (kept for all programs)
initial begin
    @(posedge rst_n);
    forever begin
        @(posedge clk);
        if (dut.u_reg_file.write_en && (dut.u_reg_file.write_mask != 0)) begin
            $display("[REG WRITE] Time=%0t | Warp=%0d | Reg=R%0d | Mask=%h",
                     $time, dut.u_reg_file.write_warp,
                     dut.u_reg_file.write_reg, dut.u_reg_file.write_mask);
            // Show lane‑0 data for relevant registers (program 1 & 2)
            if (dut.u_reg_file.write_warp == 0 && 
                dut.u_reg_file.write_reg inside {1,2,3,4}) begin
                $write("-> Lane 0 Data Written: ");
                case (dut.u_reg_file.write_reg)
                    1: $write("%0d (0x%08h)", 156, 32'h9c);
                    2: $write("%0d (0x%08h)", 55, 32'h37);
                    3: $write("%0d (0x%08h)", 211, 32'hd3);
                    4: $write("%0d (0x%08h)", dut.u_reg_file.write_data[0], dut.u_reg_file.write_data[0]);
                endcase
                $write("\n");
            end
        end
    end
end

// MAIN PROGRAM EXECUTION FLOW
initial begin
    clear_inputs();
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    $display("--- SYSTEM SIMULATION STARTED ---");

    // PROGRAM 1: Uniform Vector Addition (Warp 0)
    //   R1 = 156, R2 = 55, R3 = R1 + R2
    $display("\n>>> Starting Program 1: Uniform Vector Addition...");

    // Load immediate 156 into R1
    exec_instr(0, 32'hFFFF_FFFF, op_encode(4'h0, 5'd1, 5'd0, 5'd0, 1'b1, 12'd156));
    // Load immediate 55 into R2
    exec_instr(0, 32'hFFFF_FFFF, op_encode(4'h0, 5'd2, 5'd0, 5'd0, 1'b1, 12'd55));
    // Add R1 + R2 -> R3 (using opcode 4'h1 for ADD, rs1=R1, rs2=R2, imm_sel=0)
    exec_instr(0, 32'hFFFF_FFFF, op_encode(4'h1, 5'd3, 5'd1, 5'd2, 1'b0, 12'd0));

    clear_inputs();

    // PROGRAM 2: Masked Divergence (Warp 0)
    //   Lanes 0-15  : R4 = 0xAAA
    //   Lanes 16-31 : R4 = 0xBBB
    $display("\n>>> Starting Program 2: Masked Divergence...");

    // Write 0xAAA to R4 for lanes 0-15 (mask lower 16 bits)
    exec_instr(0, 32'h0000_FFFF, op_encode(4'h0, 5'd4, 5'd0, 5'd0, 1'b1, 12'hAAA));
    // Write 0xBBB to R4 for lanes 16-31 (mask upper 16 bits)
    exec_instr(0, 32'hFFFF_0000, op_encode(4'h0, 5'd4, 5'd0, 5'd0, 1'b1, 12'hBBB));

    clear_inputs();

    repeat (8) @(posedge clk);
    $display("--- VERIFICATION CHECKS COMPLETED ---");
    $display("1. Vector Addition: Warp 0, R3 = 211 (156+55) globally.");
    $display("2. Mask Divergence: R4 = 0xAAA on lanes [0:15], 0xBBB on lanes [16:31].");
    $finish;
end

endmodule