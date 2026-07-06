module warp_scheduler #(
    parameter NUM_WARPS   = 4,
    parameter NUM_THREADS = 32,
    parameter DATA_WIDTH  = 32
) (
    input logic clk,
    input logic rst_n,
    input logic is_mem_op,

    input  logic [DATA_WIDTH-1:0] warp_instr [NUM_WARPS-1:0],
    input  logic [NUM_THREADS-1:0] warp_mask [NUM_WARPS-1:0],

    input  logic [NUM_THREADS-1:0] thread_stall, // from shared memory

    output logic [31:0] instr_out,
    output logic [NUM_THREADS-1:0] active_mask_out,
    output logic [$clog2(NUM_WARPS)-1:0] warp_id_out,
    output logic valid_out
); 

logic [1:0] pipe_age [NUM_WARPS-1:0];
logic [NUM_THREADS-1:0] stall_mask [NUM_WARPS-1:0];


typedef enum logic [1:0] {
    READY, RUNNING, WAITING, STALLED
} warp_state_t;

warp_state_t state [NUM_WARPS-1:0];
logic [$clog2(NUM_WARPS)-1:0] selected_warp;
logic is_mem_op_r [NUM_WARPS-1:0];  // register to hold the memory operation status of each warp
integer w, warp_found;

// For Round Robin 
logic [$clog2(NUM_WARPS)-1:0] rr_ptr; 
logic [$clog2(NUM_WARPS)-1:0] current_idx;

// The warp scheduler performs state managements on the warps.

// Initally, it sets all warps to ready upon reset. Then, it selects the first ready warp and sets it to running. While the warp is running, the next warp is selected. The running warp will stay in running state for 2 cycles (to account for pipeline latency). After that, if the instruction is a memory operation, it will go to waiting state to check for stalls. If there are stalls, it will go to stalled state and wait until all threads are un-stalled. If there are no stalls, it will go back to ready state. If the instruction is not a memory operation, it will go back to ready state after 2 cycles of running.

// Selection of warp (Combinational)
always @(*) // /always_comb. Used @(*) for icarus verilog
    begin
        selected_warp = '0;
        warp_found = 0;
        for (w = 0; w < NUM_WARPS; w++) begin
            if (!warp_found) begin
                current_idx = (rr_ptr + w >= NUM_WARPS) ? (rr_ptr + w - NUM_WARPS) : (rr_ptr + w);
                if (state[current_idx] == READY ||
                    (state[current_idx] == STALLED && !(|thread_stall))) begin // Meaning the stalled warp which no longer has any stalled threads can be selected to run 
                    selected_warp = current_idx;
                    warp_found = 1;
                end
            end
        end
    end


// Output assignment (Combinational)
always @(*) // /always_comb. Used @(*) for icarus verilog
    begin
        warp_id_out = selected_warp;
        instr_out = warp_instr[selected_warp];
        valid_out = warp_found;

        if (state[selected_warp] == STALLED)
            active_mask_out = stall_mask[selected_warp];
        else
            active_mask_out = warp_mask[selected_warp];
    end

// State updation logic (Sequential)
always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n) 
        begin
            rr_ptr <= '0;
            for (w = 0; w < NUM_WARPS; w++) begin
                state[w]       <= READY;
                pipe_age[w]    <= 2'b00;
                stall_mask[w] <= '0;
                is_mem_op_r[w] <= 1'b0;
            end
        end 
    else 
        begin
            if (warp_found) begin
                rr_ptr <= (selected_warp == NUM_WARPS-1) ? '0 : selected_warp + 1;
            end
            for (w = 0; w < NUM_WARPS; w++) 
                case (state[w])
                    READY:
                        begin
                            if (selected_warp == w && warp_found)
                                begin
                                    state[w] <= RUNNING;
                                    pipe_age[w] <= 2'b00; 
                                    is_mem_op_r[w] <= is_mem_op;
                                end
                        end   
                    RUNNING:
                        begin
                            if (pipe_age[w] == 2'd2)    
                                begin
                                    pipe_age[w] <= 2'b00;
                                    if (is_mem_op_r[w]) // we use the saved signal, not the current live signal
                                        state[w] <= WAITING;  // go check for stalls in waiting state
                                    else
                                        state[w] <= READY;    // arithmetic does not need to wait for memory
                                end 
                            else 
                                begin
                                    pipe_age[w] <= pipe_age[w] + 1;
                                end
                        end
                    WAITING: 
                        begin
                            if (|thread_stall) // Reduction OR operator. If any thread is stalled, go to STALLED state
                                begin
                                    stall_mask[w] <= thread_stall;
                                    state[w] <= STALLED;
                                end 
                            else 
                                begin
                                    state[w] <= READY;
                                end
                        end                
                    STALLED: 
                        begin
                            if (!(|thread_stall)) // Reduction OR operator. If no thread is stalled, go to READY state
                                begin
                                    if (selected_warp == w && warp_found) 
                                        begin
                                            state[w]    <= RUNNING;
                                            pipe_age[w] <= 2'b00;   // fresh run for the replayed lanes
                                        end
                                    // else: stays STALLED this cycle, waiting its turn in round robin
                                end 
                            else 
                                begin
                                    stall_mask[w] <= thread_stall;
                                end
                        end
                    default: state[w] <= READY;
                endcase
        end
    end


endmodule