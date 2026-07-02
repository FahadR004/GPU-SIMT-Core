// Code your testbench here
// or browse Examples
`timescale 1ns/1ps

module tb_register_file;

parameter NUM_WARPS       = 4;
parameter NUM_THREADS     = 32;
parameter NUM_REGS_PER_TH = 32;
parameter DATA_WIDTH      = 32;

logic clk;
logic rst_n;

logic [$clog2(NUM_WARPS)-1:0] read_warp;        
logic [$clog2(NUM_REGS_PER_TH)-1:0] regA;
logic [$clog2(NUM_REGS_PER_TH)-1:0] regB;
logic [DATA_WIDTH-1:0] read_data_a [NUM_THREADS-1:0];
logic [DATA_WIDTH-1:0] read_data_b [NUM_THREADS-1:0];

logic write_en; 
logic [DATA_WIDTH-1:0] write_data [NUM_THREADS-1:0];
logic [NUM_THREADS-1:0] write_mask; 
logic [$clog2(NUM_WARPS)-1:0] write_warp;
logic [$clog2(NUM_REGS_PER_TH)-1:0] write_reg;
    
integer t, i;

register_file #(
    .NUM_WARPS(NUM_WARPS),
    .NUM_THREADS(NUM_THREADS),
    .NUM_REGS_PER_TH(NUM_REGS_PER_TH),
    .DATA_WIDTH(DATA_WIDTH)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    
    .read_warp(read_warp),
    .regA(regA),
    .regB(regB),
    .read_data_a(read_data_a), // Output
    .read_data_b(read_data_b), // Output
    
    .write_en(write_en),
    .write_data(write_data),
    .write_mask(write_mask),
    .write_warp(write_warp),
    .write_reg(write_reg)
);

initial clk = 1'b0;
always #5 clk = ~clk;

initial begin
    $dumpfile("register_file.vcd");
    $dumpvars(0, tb_register_file);
end

task automatic write_reg_file(
    input logic write_en_,
    input logic [$clog2(NUM_WARPS)-1:0] write_warp_,
    input logic [$clog2(NUM_REGS_PER_TH)-1:0] write_reg_,
    input logic [NUM_THREADS-1:0] write_mask_
);
    begin
        @(negedge clk);
        write_en = write_en_;
        write_warp = write_warp_;
        write_reg = write_reg_;
        write_mask = write_mask_;
        for (i = 0; i < NUM_THREADS; i = i + 1)
            begin
                write_data[i] = i;
            end
            
        @(posedge clk);
        #1;
        
    end
    endtask
initial 
    begin
        rst_n      = 1'b0;
        write_en   = 1'b0;
        write_warp = '0;
        write_reg  = '0;
        write_mask = '0;
        read_warp  = '0;
        regA       = '0;
        regB       = '0;

        repeat (2) @(posedge clk); 

        rst_n = 1'b1;
        @(posedge clk);#1;

        // Check reset worked ? should all print 0
        read_warp = 2'b00;
        regA = 5'b00000;
        for (t = 0; t < NUM_THREADS; t = t + 1)
            $display("POST-RESET Thread %0d regA=%0d", t, read_data_a[t]);

        write_reg_file(1'b1, 2'b00, 5'b00010, {NUM_THREADS{1'b1}});
        write_reg_file(1'b1, 2'b00, 5'b00011, 32'h5555_5555);

        write_en = 1'b0;
        read_warp = 2'b00; 
        regA = 5'b00010;
        regB = 5'b00011;
        
        @(posedge clk); #1;

        for (t = 0; t < NUM_THREADS; t = t + 1)
            $display("Warp %d, Thread %d: RegA= %d, RegB= %d", read_warp, t, read_data_a[t], read_data_b[t]);

        @(posedge clk);

        $finish;
    end
    

endmodule