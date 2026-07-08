`timescale 1ns/1ps

module simt_core #(
parameter NUM_WARPS         = 4,
parameter NUM_THREADS       = 32,
parameter NUM_REGS_PER_TH   = 32,
parameter DATA_WIDTH        = 32
) (
input logic clk,
input logic rst_n,

// Instruction Interface (from Fetch Unit / I-Cache)
input  logic [DATA_WIDTH-1:0] warp_instr [NUM_WARPS-1:0],
input  logic [NUM_THREADS-1:0] warp_mask [NUM_WARPS-1:0]
);


// Scheduler Outputs
logic [DATA_WIDTH-1:0]         sched_instr;
logic [NUM_THREADS-1:0]        sched_active_mask;
logic [$clog2(NUM_WARPS)-1:0]  sched_warp_id;
logic                          sched_valid;

// Decoder Outputs
logic [3:0]             dec_opcode;
logic [4:0]             dec_rd_addr;
logic [4:0]             dec_rs1_addr;
logic [4:0]             dec_rs2_addr;
logic                   dec_imm_sel;
logic [DATA_WIDTH-1:0]  dec_immediate;
logic                   dec_is_mem_op;

// Shared Memory Interface Wires 
logic [NUM_THREADS-1:0]                         thread_stall;
logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]         mem_addr;
logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]         mem_wdata;
logic [NUM_THREADS-1:0]                         mem_write_en;
logic [NUM_THREADS-1:0][DATA_WIDTH-1:0]         mem_rdata;

// Address split for shared_mem's banked addressing
logic [NUM_THREADS-1:0][$clog2(32)-1:0]         sm_bank_addr;
logic [NUM_THREADS-1:0][$clog2(256)-1:0]        sm_word_addr;
logic [NUM_THREADS-1:0]                         sm_thread_mask;
logic [NUM_THREADS-1:0]                         sm_thread_write;
logic [31:0]                                    sm_conflict_out;

// Register File Outputs
logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] rf_read_data_a;
logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] rf_read_data_b;

// Unpacked outputs
logic [DATA_WIDTH-1:0] rf_read_data_a_unpacked [NUM_THREADS-1:0];
logic [DATA_WIDTH-1:0] rf_read_data_b_unpacked [NUM_THREADS-1:0];
logic [DATA_WIDTH-1:0] write_data_unpacked     [NUM_THREADS-1:0];

// ALU Input Muxes
logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] alu_src_b;

// ALU Outputs
logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] alu_result;
logic                          alu_valid_out;
logic                          alu_is_mem_op;
logic                          alu_is_store;

// Pipeline Registers to align RF reads with ALU Writeback
logic [$clog2(NUM_WARPS)-1:0]  wb_warp_id_r1,  wb_warp_id_r2;
logic [4:0]                    wb_rd_addr_r1,  wb_rd_addr_r2;
logic [NUM_THREADS-1:0]        wb_mask_r1,     wb_mask_r2;
logic                          wb_en_r1,       wb_en_r2;
logic                          wb_is_load_r1,  wb_is_load_r2;

logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] wb_store_data_r1;
logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] wb_store_data_r2;
logic [NUM_THREADS-1:0] wb_final_write_mask;
logic [NUM_THREADS-1:0] thread_stall_captured;

// Warp Scheduler Instance
warp_scheduler #(
    .NUM_WARPS(NUM_WARPS),
    .NUM_THREADS(NUM_THREADS),
    .DATA_WIDTH(DATA_WIDTH)
) u_scheduler (
    .clk(clk),
    .rst_n(rst_n),
    .is_mem_op(dec_is_mem_op), // Feedback from instruction decoder
    .warp_instr(warp_instr),
    .warp_mask(warp_mask),
    .thread_stall(thread_stall_captured),
    .instr_out(sched_instr),
    .active_mask_out(sched_active_mask),
    .warp_id_out(sched_warp_id),
    .valid_out(sched_valid)
);

// Instruction Decoder Instance
instruction_decoder u_decoder (
    .instruction(sched_instr),
    .opcode(dec_opcode),
    .rd_addr(dec_rd_addr),
    .rs1_addr(dec_rs1_addr),
    .rs2_addr(dec_rs2_addr),
    .imm_sel(dec_imm_sel),
    .immediate(dec_immediate),
    .is_mem_op(dec_is_mem_op)
);

// Register File Instance (Read Stage)
register_file #(
    .NUM_WARPS(NUM_WARPS),
    .NUM_THREADS(NUM_THREADS),
    .NUM_REGS_PER_TH(NUM_REGS_PER_TH),
    .DATA_WIDTH(DATA_WIDTH)
) u_reg_file (
    .clk(clk),
    .rst_n(rst_n),
    // Read ports (Combinational)
    .read_warp(sched_warp_id),
    .regA(dec_rs1_addr),
    .regB(dec_rs2_addr),
    .read_data_a(rf_read_data_a_unpacked),
    .read_data_b(rf_read_data_b_unpacked),
    .write_en(wb_en_r2),
    .write_data(write_data_unpacked), // Writeback from ALU or Load from Memory    // Write ports (Sequential Writeback Stage)
    .write_mask(wb_final_write_mask),
    .write_warp(wb_warp_id_r2),
    .write_reg(wb_rd_addr_r2)
);

always_comb begin
    for (int t = 0; t < NUM_THREADS; t++) begin
        // Pack the outputs coming OUT of the register file for the ALU
        rf_read_data_a[t] = rf_read_data_a_unpacked[t];
        rf_read_data_b[t] = rf_read_data_b_unpacked[t];

        // Unpack the system bus data going INTO the register file
        write_data_unpacked[t] = wb_is_load_r2 ? mem_rdata[t] : alu_result[t];
    end
end

// ALU Input Muxes (Immediate vs RegB selection)
always_comb begin
    for (int t = 0; t < NUM_THREADS; t++) begin
        alu_src_b[t] = dec_imm_sel ? dec_immediate : rf_read_data_b[t];
    end
end

// SIMT ALU Instance (Execution Stage)
simt_alu #(
    .NUM_LANES(NUM_THREADS),
    .DATA_WIDTH(DATA_WIDTH)
) u_simt_alu (
    .clk(clk),
    .rst_n(rst_n),
    .opcode(dec_opcode),
    .lane_mask(sched_active_mask),
    .src_a(rf_read_data_a),
    .src_b(alu_src_b),
    .result(alu_result),
    .valid_out(alu_valid_out),
    .is_mem_op(alu_is_mem_op),
    .is_store(alu_is_store)
);

// Shared (Banked) Memory Instance (Memory Stage) 
shared_mem #(
    .NUM_BANKS(32),
    .BANK_DEPTH(256),
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_THREADS(NUM_THREADS)
) u_shared_mem (
    .clk(clk),
    .rst_n(rst_n),
    .write_en('0),               // unused 
    .thread_mask(sm_thread_mask),
    .thread_write(sm_thread_write),
    .th_bank_addr(sm_bank_addr),
    .th_word_addr(sm_word_addr),
    .thread_wdata(mem_wdata),
    .thread_rdata(mem_rdata),
    .thread_stall(thread_stall),
    .conflict_out(sm_conflict_out)
);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        thread_stall_captured <= '0;
    end else begin
        // If an active memory operation is actively targeting the banks, 
        // capture their stall vectors. Otherwise, clear it so the scheduler 
        // can wake back up and retry/replay the narrowed lane mask.
        thread_stall_captured <= (|sm_thread_mask) ? thread_stall : '0;
    end
end
// Memory Output Control Logic
always_comb begin
    for (int t = 0; t < NUM_THREADS; t++) begin
        // Address generated by ALU stage (src_a + immediate)
        mem_addr[t]  = alu_result[t];

        mem_wdata[t] = wb_store_data_r2[t];

        mem_write_en[t] = (alu_valid_out && alu_is_store && wb_mask_r2[t]);
    end
end

always_comb begin
    wb_final_write_mask = wb_mask_r2;
end

always_comb begin
    for (int t = 0; t < NUM_THREADS; t++) begin
        sm_bank_addr[t]  = mem_addr[t][$clog2(32)-1:0];
        sm_word_addr[t]  = mem_addr[t][$clog2(32)+$clog2(256)-1 : $clog2(32)];
        sm_thread_mask[t]  = wb_mask_r2[t] & alu_valid_out & alu_is_mem_op;
        sm_thread_write[t] = mem_write_en[t];
    end
end

// Pipeline Control Registers (latency matching for Writeback)
// Matches the 2-cycle latency pipeline inside your SIMT ALU design
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wb_warp_id_r1 <= '0;    wb_warp_id_r2 <= '0;
        wb_rd_addr_r1 <= '0;    wb_rd_addr_r2 <= '0;
        wb_mask_r1    <= '0;    wb_mask_r2    <= '0;
        wb_en_r1      <= '0;    wb_en_r2      <= '0;
        wb_is_load_r1 <= '0;    wb_is_load_r2 <= '0;
       wb_store_data_r1 <= '0; 
	wb_store_data_r2 <= '0;
    end else begin
        // Pipeline Stage 1 (Aligns with ALU internal Stage 1)
        wb_warp_id_r1 <= sched_warp_id;
        wb_rd_addr_r1 <= dec_rd_addr;
        wb_mask_r1    <= sched_active_mask;
        wb_en_r1      <= sched_valid && (dec_opcode != 4'h9); // Don't write back register on STORE commands
        wb_is_load_r1 <= (dec_opcode == 4'h8); // Check if load command
        wb_store_data_r1 <= rf_read_data_b;    

        // Pipeline Stage 2 (Aligns with ALU output result generation)
        wb_warp_id_r2 <= wb_warp_id_r1;
        wb_rd_addr_r2 <= wb_rd_addr_r1;
        wb_mask_r2    <= wb_mask_r1;
        wb_en_r2      <= wb_en_r1 && alu_valid_out;
        wb_is_load_r2 <= wb_is_load_r1;
        wb_store_data_r2 <= wb_store_data_r1; // FIX #3: carry store operand to writeback stage
    end
end

endmodule

