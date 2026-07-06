// Instruction Format
// 31:28  | 27:23 | 22:18 | 17:13 |    12   | 11:0
// opcode |   rd  | srcA  | srcB  | imm_sel | imm
`timescale 1ns/1ps

module instruction_decoder (
    input  logic [31:0] instruction,
    
    output logic [3:0]  opcode,
    output logic [4:0]  rd_addr,
    output logic [4:0]  rs1_addr,
    output logic [4:0]  rs2_addr,
    output logic        imm_sel,
    output logic [31:0] immediate,
    output logic is_mem_op
);

    always @(*) begin
        opcode   = instruction[31:28];
        rd_addr  = instruction[27:23];
        rs1_addr = instruction[22:18];
        rs2_addr = instruction[17:13];
        imm_sel  = instruction[12];
        is_mem_op = (instruction[31:28] == 4'h8) || (instruction[31:28] == 4'h9); 

        immediate = {{20{instruction[11]}}, instruction[11:0]}; // Sign extension to 32-bits
    end

endmodule