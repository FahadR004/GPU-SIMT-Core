module simt_alu #(
    NUM_LANES = 16,
    DATA_WIDTH = 32
) (
    input logic clk, rst_n,
    input logic [3:0] opcode,
    input logic [NUM_LANES-1:0] lane_mask,
    input logic [NUM_LANES-1:0] [DATA_WIDTH-1:0] src_a, // 2D packed array which is not present in Verilog // [15:0] [31:0] src_a
    input logic [NUM_LANES-1:0] [DATA_WIDTH-1:0] src_b,
    output logic [NUM_LANES-1:0] [DATA_WIDTH-1:0] result,
    output logic valid_out,
    
    output logic is_mem_op,
    output logic is_store
);

// OP_CODE
localparam OP_ADD = 4'h0;    // 0000
localparam OP_SUB = 4'h1;    // 0001
localparam OP_MUL = 4'h2;    // 0010
localparam OP_AND = 4'h3;    // 0011
localparam OP_OR = 4'h4;     // 0100
localparam OP_XOR = 4'h5;    // 0101
localparam OP_SLT = 4'h6;    // 0110
localparam OP_SRL = 4'h7;    // 0111
localparam OP_LOAD = 4'h8;   // 1000
localparam OP_STORE = 4'h9 ; // 1001

// Pipeline Stage 1
logic [3:0] opcode_r;
logic [NUM_LANES-1:0] mask_r;
logic [NUM_LANES-1:0][DATA_WIDTH-1:0] src_a_r;
logic [NUM_LANES-1:0][DATA_WIDTH-1:0] src_b_r;
logic valid_r;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) 
        begin
        opcode_r <= 4'h0;
        mask_r <= {NUM_LANES{1'b0}};
        src_a_r <= {NUM_LANES*DATA_WIDTH{1'b0}};
        src_b_r <= {NUM_LANES*DATA_WIDTH{1'b0}};
        valid_r <= 1'b0;
        end 
    else 
        begin
            opcode_r <= opcode;
            mask_r <= lane_mask;
            src_a_r <= src_a;
            src_b_r <= src_b;
            valid_r <= 1'b1;
        end
end


// ── Stage-2: One ALU per Lane (generate block) ─────────
// 'generate for' replicates this logic NUM_LANES times.
// Synthesis creates 32 independent ALU instances.
genvar i;
generate
    for (i = 0; i < NUM_LANES; i = i + 1) begin : lane_gen
        logic [DATA_WIDTH-1:0] lane_out; // Combinational result for lane i. Every hardware has it's own copy  
        always_comb // Runs whenever mask_r, opcode_r, src_a_r[i] or src_b_r[i] changes
            begin
                if (!mask_r[i]) 
                    begin
                        lane_out = {DATA_WIDTH{1'b0}}; // Inactive lane outputs zero
                    end 
                else 
                    begin
                        case (opcode_r)
                            OP_ADD : lane_out = src_a_r[i] + src_b_r[i];
                            OP_SUB : lane_out = src_a_r[i] - src_b_r[i];
                            OP_MUL : lane_out = src_a_r[i] * src_b_r[i];
                            OP_AND : lane_out = src_a_r[i] & src_b_r[i];
                            OP_OR : lane_out = src_a_r[i] | src_b_r[i];
                            OP_XOR : lane_out = src_a_r[i] ^ src_b_r[i];
                            OP_SLT : lane_out = ($signed(src_a_r[i]) < $signed(src_b_r[i])) ? 32'd1 : 32'd0;
                            // Note: Icarus Verilog will give warning for the following line of code. You can ignore it. It will work on commercial software.
                            OP_SRL : lane_out = src_a_r[i] >> src_b_r[i][4:0]; // We are only looking at the last five bits of b to check the shift amount. We only need 5 bits to shift a 32-bit value. More than that would just give you zero.
                            // In load-store, we calculate the address where the operand is stored (load)/ where to write the data in the memory (store)
                            OP_LOAD  : lane_out = src_a_r[i] + src_b_r[i]; // src_a + immediate value
                            OP_STORE : lane_out = src_a_r[i] + src_b_r[i]; // src_a + immediate value
                            default: lane_out = {DATA_WIDTH{1'b0}};
                        endcase
                    end
            end
 
        // Register the lane output (Stage-2 register = output pipeline)
        always_ff @(posedge clk or negedge rst_n)  // Each copy has it's own flipflop
            begin
                if (!rst_n) result[i] <= {DATA_WIDTH{1'b0}};
                else result[i] <= lane_out;
            end
    end
endgenerate

// valid_out follows valid_r by 1 cycle (matches result latency)
always_ff @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
            begin
                valid_out  <= 1'b0;
                is_mem_op  <= 1'b0;
                is_store   <= 1'b0;
            end 
        else 
            begin
                valid_out  <= valid_r;
                is_mem_op  <= (opcode_r == OP_LOAD) || (opcode_r == OP_STORE);
                is_store   <= (opcode_r == OP_STORE);
            end
    end

endmodule