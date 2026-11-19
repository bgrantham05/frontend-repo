// predict the next PC for two instructions using the same tables
module frontend_branch_predictor #(
    parameter int LOCAL_PC_BITS = 6,
    parameter int LOCAL_HISTORY_BITS = 4,
    parameter int GLOBAL_HISTORY_BITS = 6,
    parameter int CHOOSER_BITS = 6,
    parameter int BTB_BITS = 4
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [1:0][31:0] lookup_pc_i,
    output logic [1:0] predicted_taken_o,
    output logic [1:0][31:0] predicted_next_pc_o,
    output logic [1:0] btb_hit_o,
    output logic [1:0][LOCAL_HISTORY_BITS-1:0] local_index_o,
    output logic [1:0][GLOBAL_HISTORY_BITS-1:0] global_index_o,
    output logic [1:0] local_taken_o,
    output logic [1:0] global_taken_o,

    // use the saved lookup info and the actual branch result
    input  logic resolve_valid_i,
    input  logic [31:0] resolve_pc_i,
    input  logic resolve_taken_i,
    input  logic [31:0] resolve_target_i,
    input  logic [LOCAL_HISTORY_BITS-1:0] resolve_local_index_i,
    input  logic [GLOBAL_HISTORY_BITS-1:0] resolve_global_index_i,
    input  logic resolve_local_taken_i,
    input  logic resolve_global_taken_i
);
    localparam int BTB_TAG_BITS = 30 - BTB_BITS;

    // P-share keeps history by PC, G-share shares one history
    logic [LOCAL_HISTORY_BITS-1:0] local_history_q [0:(1 << LOCAL_PC_BITS)-1];
    logic [GLOBAL_HISTORY_BITS-1:0] global_history_q; // recent results from all branches
    logic [1:0] local_counter_q [0:(1 << LOCAL_HISTORY_BITS)-1];
    logic [1:0] global_counter_q [0:(1 << GLOBAL_HISTORY_BITS)-1];
    // high bit means taken for prediction, or use G-share for the chooser
    logic [1:0] chooser_q [0:(1 << CHOOSER_BITS)-1];

    // use the upper PC bits to tell branches at the same BTB slot apart
    typedef struct packed {
        logic valid; // this slot has a saved target
        logic [BTB_TAG_BITS-1:0] tag;
        logic [31:0] target; // where this branch goes if taken
    } btb_entry_t;

    btb_entry_t btb_q [0:(1 << BTB_BITS)-1];

    function automatic logic [1:0] train_counter(
        input logic [1:0] counter,
        input logic increment
    );
        if (increment) // move toward taken or toward G-share
            return counter == 2'b11 ? counter : counter + 2'b01;
        return counter == 2'b00 ? counter : counter - 2'b01;
    endfunction

    logic [LOCAL_PC_BITS-1:0] resolve_local_pc_index;
    logic [CHOOSER_BITS-1:0] resolve_chooser_index;
    logic [BTB_BITS-1:0] resolve_btb_index;
    assign resolve_local_pc_index = resolve_pc_i[2 +: LOCAL_PC_BITS];
    assign resolve_chooser_index = resolve_pc_i[2 +: CHOOSER_BITS];
    assign resolve_btb_index = resolve_pc_i[2 +: BTB_BITS];

    for (genvar lane = 0; lane < 2; lane++) begin : gen_lookup
        logic [31:0] pc;
        btb_entry_t btb_entry;
        logic selected_taken;
        assign pc = lookup_pc_i[lane]; // address to predict for this lane
        // skip the bottom two bits of the PC
        assign local_index_o[lane] = local_history_q[pc[2 +: LOCAL_PC_BITS]];
        assign global_index_o[lane] = pc[2 +: GLOBAL_HISTORY_BITS] ^ global_history_q;
        assign local_taken_o[lane] = local_counter_q[local_index_o[lane]][1];
        assign global_taken_o[lane] = global_counter_q[global_index_o[lane]][1];
        assign selected_taken = chooser_q[pc[2 +: CHOOSER_BITS]][1]
                              ? global_taken_o[lane] : local_taken_o[lane];
        assign btb_entry = btb_q[pc[2 +: BTB_BITS]];
        assign btb_hit_o[lane] = rst_ni && btb_entry.valid &&
                                 btb_entry.tag == pc[31:BTB_BITS+2];
        // go to PC + 4 if we don't have a matching target
        assign predicted_taken_o[lane] = selected_taken && btb_hit_o[lane];
        assign predicted_next_pc_o[lane] = predicted_taken_o[lane]
                                         ? btb_entry.target : pc + 32'd4;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            global_history_q <= '0; // forget past branch results
            for (int i = 0; i < (1 << LOCAL_PC_BITS); i++)
                local_history_q[i] <= '0;
            for (int i = 0; i < (1 << LOCAL_HISTORY_BITS); i++)
                local_counter_q[i] <= 2'b01; // start by guessing not taken
            for (int i = 0; i < (1 << GLOBAL_HISTORY_BITS); i++)
                global_counter_q[i] <= 2'b01;
            for (int i = 0; i < (1 << CHOOSER_BITS); i++)
                chooser_q[i] <= 2'b01; // start by favoring the local guess
            for (int i = 0; i < (1 << BTB_BITS); i++)
                btb_q[i] <= '0; // start with no saved targets
        end else if (resolve_valid_i) begin // learn from the actual result
            local_counter_q[resolve_local_index_i] <=
                train_counter(local_counter_q[resolve_local_index_i], resolve_taken_i);
            global_counter_q[resolve_global_index_i] <=
                train_counter(global_counter_q[resolve_global_index_i], resolve_taken_i);
            // train the chooser only when the predictors disagree
            if (resolve_local_taken_i != resolve_global_taken_i)
                chooser_q[resolve_chooser_index] <=
                    train_counter(chooser_q[resolve_chooser_index],
                                  resolve_global_taken_i == resolve_taken_i);

            // add the result to the current history, train using the old lookup index
            local_history_q[resolve_local_pc_index] <=
                (local_history_q[resolve_local_pc_index] << 1) | LOCAL_HISTORY_BITS'(resolve_taken_i);
            global_history_q <= (global_history_q << 1) | GLOBAL_HISTORY_BITS'(resolve_taken_i);
            // save or update the target when the branch is taken
            if (resolve_taken_i) begin
                btb_q[resolve_btb_index] <= {1'b1, resolve_pc_i[31:BTB_BITS+2], resolve_target_i};
            end
        end
    end
endmodule
