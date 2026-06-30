`timescale 1ns/1ps

module simt_alu_tb;

localparam NUM_LANES   = 16;
localparam DATA_WIDTH  = 32;

logic clk, rst_n;
logic [3:0] opcode;
logic [NUM_LANES-1:0] lane_mask;
logic [NUM_LANES-1:0][DATA_WIDTH-1:0] src_a, src_b, result;
logic valid_out;

simt_alu #(.NUM_LANES(NUM_LANES), .DATA_WIDTH(DATA_WIDTH)) dut (
    .clk(clk), .rst_n(rst_n), .opcode(opcode),
    .lane_mask(lane_mask), .src_a(src_a), .src_b(src_b),
    .result(result), .valid_out(valid_out)
);

initial clk = 1'b0;
always #5 clk = ~clk;

initial begin
    $dumpfile("simt_alu.vcd");
    $dumpvars(0, simt_alu_tb);
end

int pass_count = 0;
int fail_count = 0;


task automatic run_test(string name, logic [3:0] op, // automatic means that every time task is called, it will have new independent local variables for each call
                         logic [DATA_WIDTH-1:0] a,
                         logic [DATA_WIDTH-1:0] b,
                         logic [DATA_WIDTH-1:0] expected);
    int j; // Every task call has it's own j
    begin
        opcode    = op;
        lane_mask = {NUM_LANES{1'b1}};   // all lanes active
        for (j = 0; j < NUM_LANES; j++) begin
            src_a[j] = a; // This is essentially like assigning values one by one in a normal testbench
            src_b[j] = b;
        end
        repeat(2) @(posedge clk);        // Wait for 2-cycle pipeline latency. Then, check result
        for (j = 0; j < NUM_LANES; j++) begin
            if (result[j] === expected) begin
                pass_count++;
            end else begin
                fail_count++;
                $display(" FAIL [%s] lane[%0d]: got %0d, expected %0d",
                          name, j, result[j], expected);
            end
        end
        $display(" %s: a=%0d b=%0d -> result=%0d (expected %0d) %s",
                  name, a, b, result[0], expected,
                  (result[0] === expected) ? "PASS" : "FAIL");
    end
endtask

initial begin
    rst_n     = 1'b0;
    opcode    = 4'h0;
    lane_mask = '0;
    src_a     = '0;
    src_b     = '0;
    repeat(3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    run_test("ADD", 4'h0, 32'd7,  32'd3,  32'd10);
    run_test("SUB", 4'h1, 32'd7,  32'd3,  32'd4);
    run_test("MUL", 4'h2, 32'd7,  32'd3,  32'd21);
    run_test("AND", 4'h3, 32'hF0, 32'h0F, 32'h00);
    run_test("OR",  4'h4, 32'hF0, 32'h0F, 32'hFF);
    run_test("XOR", 4'h5, 32'hFF, 32'h0F, 32'hF0);
    run_test("SLT_true",  4'h6, 32'd5, 32'd10, 32'd1);
    run_test("SLT_false", 4'h6, 32'd10, 32'd5, 32'd0);
    run_test("SLT_neg",   4'h6, -32'sd1, 32'd1, 32'd1); // -1 < 1
    run_test("SRL", 4'h7, 32'h00000010, 32'd2, 32'h00000004); // 16>>2=4

    // Divergence test with alternate masks
    $display("\n Divergence test with alternate masks");
    opcode    = 4'h0; // ADD
    lane_mask = {(NUM_LANES/2){2'b01}}; // Essentially, 16x (01) -> 0101010101....
    for (int j = 0; j < NUM_LANES; j++) begin
        src_a[j] = j + 1;
        src_b[j] = j + 1;
    end
    repeat(2) @(posedge clk);
    for (int j = 0; j < NUM_LANES; j++) begin
        // Never perform an inline initialization (e.g., logic a = b;) inside loops, tasks, or functions unless the parent block is explicitly marked automatic. Always separate declaration from assignment to keep things safe.
        // INCORRECT unless you use automatic logic...
        // logic expect_active = lane_mask[j]; // Like lane_mask[0] -> 0, lane_mask[1] -> 1 , lane_mask[2] -> 0
        // logic [DATA_WIDTH-1:0] expected = expect_active ? (2*(j+1)) : 0;
        logic expect_active;
    	logic [DATA_WIDTH-1:0] expected;
    
      expect_active = lane_mask[j]; // Like lane_mask[0] -> 0, lane_mask[1] -> 1 , lane_mask[2] -> 0
    expected = expect_active ? (2*(j+1)) : 0;

      $display("%b %d %0b %0d", expected, expect_active, lane_mask[j], j);
        if (result[j] === expected) pass_count++;
        else begin
            fail_count++;
            $display(" FAIL divergence lane[%0d]: got %0d, expected %0d (mask=%0b)",
                      j, result[j], expected, expect_active);
        end
    end

    $display("\n=== SUMMARY: %0d PASS, %0d FAIL ===", pass_count, fail_count);
    $finish;
end

endmodule