`timescale 1ns/1ps

module tb_instruction_decoder;

    logic [31:0] instruction;
    logic [3:0]  opcode;
    logic [4:0]  rd_addr, rs1_addr, rs2_addr;
    logic imm_sel;
    logic [31:0] immediate;
    logic is_mem_op;


    integer pass_count, fail_count;

    instruction_decoder dut (
        .instruction(instruction),
        .opcode(opcode),
        .rd_addr(rd_addr),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .imm_sel(imm_sel),
        .immediate(immediate),
        .is_mem_op(is_mem_op)
    );

    initial begin
        $dumpfile("instruction_decoder.vcd");
        $dumpvars(0, tb_instruction_decoder);
    end

    task automatic check(
        input logic [31:0] test_instr,
        input logic [3:0]  exp_opcode,
        input logic [4:0]  exp_rd, exp_rs1, exp_rs2,
        input logic        exp_imm_sel,
        input logic [31:0] exp_immediate,
        input logic exp_is_mem_op,
        input logic [63:0] test_name  // label for display
    );
        begin
            instruction = test_instr;
            #1; 
            if (opcode   !== exp_opcode   ||
                rd_addr  !== exp_rd       ||
                rs1_addr !== exp_rs1      ||
                rs2_addr !== exp_rs2      ||
                imm_sel  !== exp_imm_sel  ||
                is_mem_op !== exp_is_mem_op ||
                (exp_imm_sel && immediate !== exp_immediate)) begin
                $display("FAIL [%s]", test_name);
                $display("  instruction    = %b", test_instr);
                $display("  opcode   got=%0d exp=%0d", opcode,   exp_opcode);
                $display("  rd       got=%0d exp=%0d", rd_addr,  exp_rd);
                $display("  rs1      got=%0d exp=%0d", rs1_addr, exp_rs1);
                $display("  rs2      got=%0d exp=%0d", rs2_addr, exp_rs2);
                $display("  imm_sel  got=%0d exp=%0d", imm_sel,  exp_imm_sel);
                if (exp_imm_sel)
                    $display("  imm      got=%0d exp=%0d", immediate, exp_immediate);
                $display("  is_mem_op got=%0d exp=%0d", is_mem_op, exp_is_mem_op);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS [%s]", test_name);
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        // Test 1: ADD r3 = r1 + r2 (reg-reg)
        // opcode=ADD(0) rd=3 rs1=1 rs2=2 imm_sel=0 imm=0
        // 0000 | 00011 | 00001 | 00010 | 0 | 000000000000
        check(
            32'b0000_00011_00001_00010_0_000000000000,
            4'h0, 5'd3, 5'd1, 5'd2, 1'b0, 32'd0, 1'b0,
            "ADD r3,r1,r2"
        );

        // Test 2: SUB r5 = r4 - r7 (reg-reg)
        // opcode=SUB(1) rd=5 rs1=4 rs2=7 imm_sel=0
        check(
            32'b0001_00101_00100_00111_0_000000000000,
            4'h1, 5'd5, 5'd4, 5'd7, 1'b0, 32'd0, 1'b0,
            "SUB r5,r4,r7"
        );

        // Test 3: ADD r2 = r1 + 15 (immediate, positive)
        // opcode=ADD(0) rd=2 rs1=1 rs2=x imm_sel=1 imm=15
        check(
            32'b0000_00010_00001_00000_1_000000001111,
            4'h0, 5'd2, 5'd1, 5'd0, 1'b1, 32'd15, 1'b0,
            "ADD r2,r1, 15"
        );

        // Test 4: ADD r2 = r1 + (-1) (immediate, negative, sign extend)
        // imm = 12'b1111_1111_1111 = -1 → sign extended = 32'hFFFF_FFFF
        check(
            32'b0000_00010_00001_00000_1_111111111111,
            4'h0, 5'd2, 5'd1, 5'd0, 1'b1, 32'hFFFF_FFFF, 1'b0,
            "ADD r2,r1, -1"
        );

        // Test 5: AND r0 = r0 & r0 (all-zero fields)
        check(
            32'b0011_00000_00000_00000_0_000000000000,
            4'h3, 5'd0, 5'd0, 5'd0, 1'b0, 32'd0, 1'b0,
            "AND r0,r0,r0"
        );

        // Test 6: SLT r31 = r31 < r31 (max register addresses)
        check(
            32'b0110_11111_11111_11111_0_000000000000,
            4'h6, 5'd31, 5'd31, 5'd31, 1'b0, 32'd0, 1'b0,
            "SLT r31,r31,r31"
        );

        // Test 7: LOAD r1 = mem[r2 + 8]
        // opcode=LOAD(8) rd=1 rs1=2 rs2=x imm_sel=1 imm=8
        check(
            32'b1000_00001_00010_00000_1_000000001000,
            4'h8, 5'd1, 5'd2, 5'd0, 1'b1, 32'd8, 1'b1,
            "LOAD r1, 8(r2)"
        );

        // Test 8: LOAD r5 = mem[r3 + (-4)] (negative offset)
        check(
            32'b1000_00101_00011_00000_1_111111111100,
            4'h8, 5'd5, 5'd3, 5'd0, 1'b1, 32'hFFFF_FFFC, 1'b1,
            "LOAD r5, -4(r3)"
        );

        // Test 9: STORE mem[r2 + 8] = r4
        // opcode=STORE(9) rd=unused rs1=2 rs2=4 imm_sel=1 imm=8
        check(
            32'b1001_00000_00010_00100_1_000000001000,
            4'h9, 5'd0, 5'd2, 5'd4, 1'b1, 32'd8, 1'b1,
            "STORE r4, 8(r2)"
        );

        // Test 10: STORE mem[r6 + 0] = r7 (zero offset)
        check(
            32'b1001_00000_00110_00111_1_000000000000,
            4'h9, 5'd0, 5'd6, 5'd7, 1'b1, 32'd0, 1'b1,
            "STORE r7, 0(r6)"
        );

        $display("Results: %0d passed, %0d failed", pass_count, fail_count);
        $finish;
    end

endmodule