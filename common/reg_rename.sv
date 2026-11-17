module frontend_reg_rename (
    input logic clk_i,
    input logic rst_ni,

    input rv32_ooo_pkg::lane_count_t decoded_count_i,
    input rv32_ooo_pkg::decoded_uop_t decoded_lane0_i,
    input rv32_ooo_pkg::decoded_uop_t decoded_lane1_i,

    // The caller limits this prefix for ROB space, checkpoint space, and recovery.
    input rv32_ooo_pkg::lane_count_t admission_count_i,
    input rv32_ooo_pkg::rob_tag_t rob_tail_tag_i,
    input logic older_branch_pending_i,
    input rv32_ooo_pkg::lane_count_t dispatch_accept_count_i,

    output rv32_ooo_pkg::lane_count_t dispatch_count_o,
    output rv32_ooo_pkg::renamed_bundle_t dispatch_bundle_o,
    output rv32_ooo_pkg::phys_reg_t old_pdst_lane0_o,
    output rv32_ooo_pkg::phys_reg_t old_pdst_lane1_o,

    // Return the previous mapping of a retiring instruction with a destination.
    input logic reclaim_valid_i,
    input rv32_ooo_pkg::phys_reg_t reclaim_pdst_i,
    output rv32_ooo_pkg::free_count_t free_count_o
);
    import rv32_ooo_pkg::*;

    localparam int FREE_DEPTH = PHYS_REG_COUNT - ARCH_REG_COUNT;
    typedef logic [$clog2(FREE_DEPTH)-1:0] free_ptr_t;

    phys_reg_t rat_q [0:ARCH_REG_COUNT-1];
    phys_reg_t free_q [0:FREE_DEPTH-1];
    free_ptr_t head_q, tail_q;
    free_count_t free_count_q;
    lane_count_t accepted_count, allocation_count;

    function automatic logic has_destination(input decoded_uop_t uop);
        return uop.writes_rd && uop.rd != 0 && !uop.illegal && !uop.fetch_error;
    endfunction

    function automatic phys_reg_t lane1_mapping(input arch_reg_t reg_id);
        if (dispatch_bundle_o.lane0.has_destination && reg_id == decoded_lane0_i.rd)
            return dispatch_bundle_o.lane0.pdst;
        return rat_q[reg_id];
    endfunction

    assign free_count_o = free_count_q;
    assign accepted_count = dispatch_accept_count_i <= dispatch_count_o
                          ? dispatch_accept_count_i : dispatch_count_o;

    always_comb begin
        dispatch_count_o = 0;
        dispatch_bundle_o = '0;
        old_pdst_lane0_o = '0;
        old_pdst_lane1_o = '0;

        if (rst_ni && decoded_count_i >= 1 && admission_count_i >= 1 &&
            (!has_destination(decoded_lane0_i) || free_count_q >= 1)) begin
            dispatch_count_o = 1;
            dispatch_bundle_o.lane0.decoded = decoded_lane0_i;
            dispatch_bundle_o.lane0.rob_tag = rob_tail_tag_i;
            dispatch_bundle_o.lane0.psrc1 = decoded_lane0_i.uses_rs1 ? rat_q[decoded_lane0_i.rs1] : '0;
            dispatch_bundle_o.lane0.psrc2 = decoded_lane0_i.uses_rs2 ? rat_q[decoded_lane0_i.rs2] : '0;
            dispatch_bundle_o.lane0.under_unresolved_branch = older_branch_pending_i;
            dispatch_bundle_o.lane0.has_destination = has_destination(decoded_lane0_i);
            if (dispatch_bundle_o.lane0.has_destination) begin
                dispatch_bundle_o.lane0.pdst = free_q[head_q];
                old_pdst_lane0_o = rat_q[decoded_lane0_i.rd];
            end

            if (decoded_count_i >= 2 && admission_count_i >= 2 &&
                (!has_destination(decoded_lane1_i) ||
                 free_count_q > free_count_t'(dispatch_bundle_o.lane0.has_destination))) begin
                dispatch_count_o = 2;
                dispatch_bundle_o.lane1.decoded = decoded_lane1_i;
                dispatch_bundle_o.lane1.rob_tag = increment_rob_tag(rob_tail_tag_i, 2'd1);
                dispatch_bundle_o.lane1.psrc1 = decoded_lane1_i.uses_rs1
                                             ? lane1_mapping(decoded_lane1_i.rs1) : '0;
                dispatch_bundle_o.lane1.psrc2 = decoded_lane1_i.uses_rs2
                                             ? lane1_mapping(decoded_lane1_i.rs2) : '0;
                dispatch_bundle_o.lane1.under_unresolved_branch =
                    older_branch_pending_i || is_control_flow(decoded_lane0_i);
                dispatch_bundle_o.lane1.has_destination = has_destination(decoded_lane1_i);
                if (dispatch_bundle_o.lane1.has_destination) begin
                    dispatch_bundle_o.lane1.pdst =
                        free_q[head_q + free_ptr_t'(dispatch_bundle_o.lane0.has_destination)];
                    old_pdst_lane1_o = lane1_mapping(decoded_lane1_i.rd);
                end
            end
        end
    end

    assign allocation_count =
        lane_count_t'(accepted_count >= 1 && dispatch_bundle_o.lane0.has_destination) +
        lane_count_t'(accepted_count >= 2 && dispatch_bundle_o.lane1.has_destination);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < ARCH_REG_COUNT; i++)
                rat_q[i] <= phys_reg_t'(i);
            for (int i = 0; i < FREE_DEPTH; i++)
                free_q[i] <= phys_reg_t'(ARCH_REG_COUNT + i);
            head_q <= '0;
            tail_q <= '0;
            free_count_q <= free_count_t'(FREE_DEPTH);
        end else begin
            // Lane 1 wins a same-cycle WAW because it is younger.
            if (accepted_count >= 1 && dispatch_bundle_o.lane0.has_destination)
                rat_q[decoded_lane0_i.rd] <= dispatch_bundle_o.lane0.pdst;
            if (accepted_count >= 2 && dispatch_bundle_o.lane1.has_destination)
                rat_q[decoded_lane1_i.rd] <= dispatch_bundle_o.lane1.pdst;

            head_q <= head_q + free_ptr_t'(allocation_count);
            if (reclaim_valid_i) begin
                free_q[tail_q] <= reclaim_pdst_i;
                tail_q <= tail_q + 1'b1;
            end
            free_count_q <= free_count_q - free_count_t'(allocation_count)
                                          + free_count_t'(reclaim_valid_i);
        end
    end

`ifdef ENABLE_PROTOCOL_ASSERTIONS
    always_ff @(posedge clk_i) if (rst_ni) begin
        assert (decoded_count_i <= 2 && admission_count_i <= 2);
        assert (dispatch_accept_count_i <= dispatch_count_o);
        assert (free_count_q <= free_count_t'(FREE_DEPTH));
        if (reclaim_valid_i) begin
            assert (reclaim_pdst_i != 0);
            assert (free_count_q < free_count_t'(FREE_DEPTH));
        end
    end
`endif
endmodule
