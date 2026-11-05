module frontend_fetch (
    input logic clk_i,
    input logic rst_ni,
    
    // control flow redirect (backend or decode)
    input logic redirect_req_i, // 1 when a branch, jump, or recovery requires a redirect
    input logic [31:0] redirect_pc_i, // pc for the redirect request
    
    // downstream backpressure 
    input logic downstream_ready_i, // 1 when downstream D or I can take instructions
    
    // instr mem for synchronous 1-cycle ROM
    instruction_memory_if.frontend imem, // fetch 2
    
    // downstream instr out
    output logic fetch_valid0_o, 
    output logic [31:0] fetch_pc0_o, 
    output logic [31:0] fetch_inst0_o, 
    output logic fetch_valid1_o, 
    output logic [31:0] fetch_pc1_o,
    output logic [31:0] fetch_inst1_o 
);

    import rv32_ooo_pkg::*; 
    import instruction_memory_pkg::*;

    // fetch 1 START
    logic [31:0] pc_f1_q; 
    logic [31:0] next_pc_f1; 
    logic stall_f1;

    // 1st fetch stalls if the downstream backend is not ready to accept instructions
    assign stall_f1 = ~downstream_ready_i; 

    // next pc, redirect takes priority, else advance to the next aligned 8-bytes
    // next pc using 8-byte aligned chunks to fetch 2 instructions
    assign next_pc_f1 = redirect_req_i ? redirect_pc_i : ({pc_f1_q[31:3], 3'b000} + 32'd8);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pc_f1_q <= RESET_PC;
        end else if (redirect_req_i) begin // if redirect request
            pc_f1_q <= redirect_pc_i; 
        end else if (!stall_f1) begin // pipeline free?
            pc_f1_q <= next_pc_f1;
        end
        // stall = keep pc
    end

    // drive ROM addr
    assign imem.address = {pc_f1_q[31:3], 3'b000}; // ROM interface uses a single word aligned byte addr
    assign imem.read_enable = ~stall_f1 | redirect_req_i; // read en high unless stalled

    // fetch 2 START
    logic [31:0] pc_f2_q;
    logic        valid_f2_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pc_f2_q <= 32'd0; // clear tracking pc
            valid_f2_q <= 1'b0; // invalidate 2nd fetch (if happen?)
        end else if (redirect_req_i) begin // redirect invalidate current inflight instruction read?
            valid_f2_q <= 1'b0; // flush, clear valid bit, drop aborted instr
        end else if (!stall_f1) begin
            pc_f2_q <= pc_f1_q; // pass the 1st fetch pc to 2nd fetch stage to match ROM timing
            valid_f2_q <= 1'b1; // mark 2nd fetch valid since actively fetching new instrs
        end
    end

    // downstream
    assign fetch_valid0_o = valid_f2_q & ~redirect_req_i & (pc_f2_q[2] == 1'b0) & ~imem.error[0]; // pc must align 
    assign fetch_valid1_o = valid_f2_q & ~redirect_req_i & ~imem.error[1];

    // lower 4 bytes
    assign fetch_pc0_o = {pc_f2_q[31:3], 3'b000};

    // upper 4 bytes (pc+4)
    assign fetch_pc1_o = {pc_f2_q[31:3], 3'b100};

    // lower 32 bits of fetched data: 64-bit ROM bus -> slot 0
    assign fetch_inst0_o = imem.data[31:0];

    // upper 32 bits of fetched data: 64-bit ROM bus -> slot 1
    assign fetch_inst1_o = imem.data[63:32];

endmodule