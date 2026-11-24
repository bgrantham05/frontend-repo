module frontend (
    input logic clk_i,
    input logic rst_ni,
    instruction_memory_if.frontend imem,
    frontend_backend_if.frontend backend,
    backend_memory_if.dispatch memory,

    // External ROB and branch admission control.
    input rv32_ooo_pkg::lane_count_t rob_admission_count_i,
    input rv32_ooo_pkg::rob_tag_t rob_tail_tag_i,
    input rv32_ooo_pkg::rob_tag_t rob_head_tag_i,
    input logic older_branch_pending_i,
    input logic retire_valid_i,
    input rv32_ooo_pkg::rob_tag_t retire_tag_i,
    input logic reclaim_valid_i,
    input rv32_ooo_pkg::phys_reg_t reclaim_pdst_i,
    output rv32_ooo_pkg::lane_count_t rob_allocate_count_o,
    output rv32_ooo_pkg::renamed_bundle_t rob_allocate_bundle_o,
    output rv32_ooo_pkg::phys_reg_t old_pdst_lane0_o,
    output rv32_ooo_pkg::phys_reg_t old_pdst_lane1_o
);
    import rv32_ooo_pkg::*;
    import frontend_local_pkg::*;

    logic redirect, fetch_ready, fetch_valid0, fetch_valid1;
    logic [31:0] fetch_pc0, fetch_pc1;
    lane_count_t queued_count, offered_count, accepted_count;
    fetch_slot_t fetched0, fetched1, queued0, queued1;
    decoded_uop_t decoded0, decoded1;
    renamed_bundle_t offered_bundle;

    assign redirect = backend.branch_resolve_valid && backend.branch_mispredict;
    assign backend.dispatch_count = offered_count;
    assign backend.dispatch_bundle = offered_bundle;
    assign backend.dispatch_accept_count = accepted_count;
    assign backend.rob_head_tag = rob_head_tag_i;
    assign backend.retire_valid = retire_valid_i;
    assign backend.retire_tag = retire_tag_i;
    assign rob_allocate_count_o = accepted_count;
    assign rob_allocate_bundle_o = offered_bundle;

    frontend_fetch fetch (
        .clk_i(clk_i), .rst_ni(rst_ni), .imem(imem),
        .redirect_req_i(redirect), .redirect_pc_i(backend.branch_result_pc),
        .downstream_ready_i(fetch_ready),
        .fetch_valid0_o(fetch_valid0), .fetch_valid1_o(fetch_valid1),
        .fetch_pc0_o(fetch_pc0), .fetch_pc1_o(fetch_pc1),
        .fetch_inst0_o(fetched0.instruction), .fetch_inst1_o(fetched1.instruction),
        .fetch_error0_o(fetched0.fetch_error), .fetch_error1_o(fetched1.fetch_error)
    );
    // The fetch stage currently requests sequential PCs.
    assign fetched0.pc = fetch_pc0;
    assign fetched1.pc = fetch_pc1;
    assign fetched0.predicted_next_pc = fetch_pc0 + 32'd4;
    assign fetched1.predicted_next_pc = fetch_pc1 + 32'd4;

    frontend_ready_buffer queue (
        .clk_i(clk_i), .rst_ni(rst_ni), .flush_i(redirect),
        .input_count_i(lane_count_t'(fetch_valid0) + lane_count_t'(fetch_valid1)),
        .input_lane0_i(fetched0), .input_lane1_i(fetched1),
        .input_ready_o(fetch_ready), .output_count_o(queued_count),
        .output_lane0_o(queued0), .output_lane1_o(queued1),
        .output_accept_count_i(accepted_count)
    );

    frontend_decode_pair decode (
        .instruction0_i(queued0.instruction), .instruction1_i(queued1.instruction),
        .pc0_i(queued0.pc), .pc1_i(queued1.pc),
        .predicted_next_pc0_i(queued0.predicted_next_pc),
        .predicted_next_pc1_i(queued1.predicted_next_pc),
        .fetch_error0_i(queued0.fetch_error), .fetch_error1_i(queued1.fetch_error),
        .decoded0_o(decoded0), .decoded1_o(decoded1)
    );

    frontend_reg_rename rename (
        .clk_i(clk_i), .rst_ni(rst_ni), .decoded_count_i(queued_count),
        .decoded_lane0_i(decoded0), .decoded_lane1_i(decoded1),
        .admission_count_i(rob_admission_count_i), .rob_tail_tag_i(rob_tail_tag_i),
        .older_branch_pending_i(older_branch_pending_i),
        .dispatch_accept_count_i(accepted_count),
        .dispatch_count_o(offered_count), .dispatch_bundle_o(offered_bundle),
        .old_pdst_lane0_o(old_pdst_lane0_o), .old_pdst_lane1_o(old_pdst_lane1_o),
        .reclaim_valid_i(reclaim_valid_i), .reclaim_pdst_i(reclaim_pdst_i), .free_count_o()
    );

    frontend_memory_dispatch dispatch (
        .rst_ni(rst_ni), .branch_resolve_valid_i(backend.branch_resolve_valid),
        .dispatch_count_i(offered_count), .dispatch_bundle_i(offered_bundle),
        .backend_accept_count_i(backend.dispatch_capacity),
        .dispatch_accept_count_o(accepted_count), .memory(memory)
    );
endmodule
