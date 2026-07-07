module shared_mem #(
    parameter NUM_BANKS    = 32,   
    parameter BANK_DEPTH   = 256,  
    // Each bank has 256 words
    // 256 words x 32-bits = 1024 bits per bank
    // To address each word, I would need 8-bits (2^8 = 256)
    // To address each bank, I need 5-bits
    // 256 words x 32 bits/word x 32 banks = 2^18 = 262,144 bits of Shared Memory / 8192 words of Shared Memory
    parameter DATA_WIDTH   = 32,
    parameter NUM_THREADS  = 32
) (
    input logic clk,
    input logic rst_n,
    input logic [NUM_BANKS-1:0] write_en,

    input logic [NUM_THREADS-1:0] thread_mask,  
    input logic [NUM_THREADS-1:0] thread_write,  // 1=write 0=read

    input logic [NUM_THREADS-1:0][$clog2(NUM_BANKS)-1:0] th_bank_addr, // 5-bit
    input logic [NUM_THREADS-1:0][$clog2(BANK_DEPTH)-1:0] th_word_addr, // 8-bit
    input logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] thread_wdata,  // write data

    output logic [NUM_THREADS-1:0][DATA_WIDTH-1:0] thread_rdata,  // readdata
    output logic [NUM_THREADS-1:0] thread_stall,  // conflict detection

    output logic [NUM_BANKS-1:0] conflict_out   // which banks conflicted
);


logic [DATA_WIDTH-1:0] banked_memory [NUM_BANKS-1:0][BANK_DEPTH-1:0];

logic [NUM_THREADS-1:0] thread_wins;

integer b, t, i, j;
integer count;
integer winner;
logic [$clog2(BANK_DEPTH)-1:0] first_row; 
logic all_same_row;
logic any_write;

always @(*) begin
    thread_stall = '0;
    conflict_out = '0;
    thread_wins  = '0;

    for (b = 0; b < NUM_BANKS; b = b + 1) begin
        count        = 0;
        first_row    = 0;
        all_same_row = 1;
        any_write    = 0;
        winner       = 0;

        // Scan all threads targeting bank b
        for (t = 0; t < NUM_THREADS; t = t + 1) begin
            if (thread_mask[t] && (th_bank_addr[t] == b)) begin
                if (count == 0) begin
                    first_row = th_word_addr[t];  // reference row
                    winner    = t;                // first thread wins by default
                end
                if (th_word_addr[t] != first_row) 
                    all_same_row = 0;
                if (thread_write[t])              
                    any_write = 1;
                count = count + 1;
            end
        end

        if (count == 0) 
            begin
                // Idle 
            end 
        else if (count == 1) 
            begin
                // Single request — serve it, no conflict
                thread_wins[winner] = 1;
            end 
        else if (count > 1 && all_same_row && !any_write) begin
            // Broadcast — all readers, same address — no conflict
            for (t = 0; t < NUM_THREADS; t = t + 1)
                if (thread_mask[t] && (th_bank_addr[t] == b))
                    thread_wins[t] = 1;

        end else begin
            // Conflict — winner goes, rest stall
            thread_wins[winner]  = 1;
            conflict_out[b]      = 1;
            for (t = 0; t < NUM_THREADS; t = t + 1)
                if (thread_mask[t] && (th_bank_addr[t] == b) && (t != winner))
                    thread_stall[t] = 1;
        end
    end
end

always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) begin
            for (i = 0; i < NUM_BANKS; i = i + 1)
                for (j = 0; j < BANK_DEPTH; j = j + 1)
                    banked_memory[i][j] <= {DATA_WIDTH{1'b0}};
        end else begin
            for (t = 0; t < NUM_THREADS; t = t + 1)
                // Only write if thread won arbitration and is a write op
                if (thread_wins[t] && thread_write[t])
                    banked_memory[th_bank_addr[t]][th_word_addr[t]] <= thread_wdata[t];
        end
    end

always @(*) 
    begin
        for (t = 0; t < NUM_THREADS; t = t + 1) begin
            if (thread_mask[t] && thread_wins[t] && !thread_write[t])
                thread_rdata[t] = banked_memory[th_bank_addr[t]][th_word_addr[t]];
            else
                thread_rdata[t] = {DATA_WIDTH{1'b0}};
        end
    end

endmodule
// genvar b;
// generate
// for (b = 0; b < NUM_BANKS; b = b + 1) begin : bank_gen
//     always_ff @(posedge clk) begin
//         if (!rst_n)
//             begin
//                 for (int j = 0; j < BANK_DEPTH; j++)
//                     banked_memory[b][j] <= {DATA_WIDTH{1'b0}};
//             end
//         else 
//             if (write_en)
//                 begin
//                     for (int t = 0; t < NUM_THREADS; t++)
//                         if (write_mask[t])
//                             banked_memory[th_bank_addr[t]][th_word_addr[t]] <= thread_wdata[t];                        
//                 end
//     end

//     always_comb 
//         begin
//             for (int t = 0; t < NUM_THREADS; t++)
//                 thread_rdata[t] = banked_memory[th_bank_addr[t]][th_word_addr[t]];        
//         end
// end
// endgenerate

// always_ff @( posedge clk or negedge rst_n) 
//     begin
//         if (!rst_n)
//             begin
//                 for (int i = 0; i < NUM_BANKS; i++)
//                     for (int j = 0; j < BANK_DEPTH; j++)
//                         banked_memory[i][j] <= {DATA_WIDTH{1'b0}};
//             end
//         else 
//             begin
//                 if (write_en)
//                     begin
//                         for (int t = 0; t < NUM_THREADS; t++)
//                             if (write_mask[t])
//                                 banked_memory[th_bank_addr[t]][th_word_addr[t]] <= thread_wdata[t];                        
//                     end
//             end
//     end 

// always_comb 
//     begin
//         for (int t = 0; t < NUM_THREADS; t++)
//             thread_rdata[t] = banked_memory[th_bank_addr[t]][th_word_addr[t]];        
//     end