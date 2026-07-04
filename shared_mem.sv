module tb_shared_mem;

localparam NUM_BANKS    = 32;  
localparam BANK_DEPTH   = 256;
localparam DATA_WIDTH   = 32;
localparam NUM_THREADS  = 32;

logic clk;
logic rst_n;

logic [NUM_THREADS-1:0] thread_mask;  
logic [NUM_THREADS-1:0] thread_write;  // 1=write 0=read

logic [NUM_THREADS-1:0][$clog2(NUM_BANKS)-1:0] th_bank_addr; // 5-bit
logic [NUM_THREADS-1:0][$clog2(BANK_DEPTH)-1:0] th_word_addr; // 8-bit
logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] thread_wdata;  // write data

logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] thread_rdata;  // readdata
logic [NUM_THREADS-1:0] thread_stall;  // conflict detection

logic [NUM_BANKS-1:0] conflict_out;   // which banks conflicted

integer i, t;

shared_mem #(
    .NUM_BANKS(NUM_BANKS),
    .BANK_DEPTH(BANK_DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_THREADS(NUM_THREADS)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .write_en(write_en),
    .thread_mask(thread_mask),
    .thread_write(thread_write),
    .th_bank_addr(th_bank_addr),
    .th_word_addr(th_word_addr),
    .thread_wdata(thread_wdata),
    .thread_rdata(thread_rdata),
    .thread_stall(thread_stall),
    .conflict_out(conflict_out)
);

initial clk = 1'b0;
always #5 clk = ~clk;

initial begin
    $dumpfile("shared_mem.vcd");
    $dumpvars(0, tb_shared_mem);
end

initial 
    begin 
        rst_n = 1'b0;
        @ (posedge clk); #1;

        rst_n = 1'b1;
        @ (posedge clk); #1;
        
        for (i = 0; i < NUM_THREADS; i++)
            begin
                thread_mask[i] = 1'b1;
                thread_write[i] = 1'b1;
                th_bank_addr[i] = i % NUM_BANKS;
                th_word_addr[i] = i % BANK_DEPTH;
                thread_wdata[i] = i;
            end
        repeat(2) @ (posedge clk); #1;

        thread_write = '0;
        repeat(2) @ (posedge clk); #1;
        
        for (i = 0; i < NUM_THREADS; i++)
            begin
                if (thread_rdata[i] !== i)
                    $display("Thread %0d: Expected %0d, got %0d", i, i, thread_rdata[i]);
                else 
                    $display("Thread %0d: Read correct value %0d", i, thread_rdata[i]);
            end

        for (i = 0; i < NUM_THREADS; i++) begin
            thread_mask[i]    = (i > 29) ? 1'b1 : 1'b0;  // only threads 0 and 1 active
            thread_write[i]   = 1'b0;
            th_bank_addr[i]   = 0;                        // both hit bank 0
            th_word_addr[i]   = i;                        // different rows → conflict
        end
        @(posedge clk); #1;
        $display("Conflict test — stall[30]=%b stall[31]=%b conflict_out[0]=%b", thread_stall[30], thread_stall[31], conflict_out[0]);

        for (i = 0; i < NUM_THREADS; i++) begin
            thread_mask[i]    = (i < 2) ? 1'b1 : 1'b0;
            thread_write[i]   = 1'b0;
            th_bank_addr[i]   = 0;
            th_word_addr[i]   = 0;                        // same row → broadcast
        end
        @(posedge clk); #1;
        $display("Broadcast test — stall[0]=%b stall[1]=%b conflict_out[0]=%b",
                thread_stall[0], thread_stall[1], conflict_out[0]);
        $finish;    
    end

endmodule