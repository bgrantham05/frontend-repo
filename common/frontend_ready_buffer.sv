// four entry ordered instruction queue, registered output (no empty bypass).
module frontend_ready_buffer (
    input logic clk_i,
    input logic rst_ni,
    input logic flush_i,
    input rv32_ooo_pkg::lane_count_t input_count_i,
    input frontend_local_pkg::fetch_slot_t input_lane0_i,
    input frontend_local_pkg::fetch_slot_t input_lane1_i,
    output logic input_ready_o,
    output rv32_ooo_pkg::lane_count_t output_count_o,
    output frontend_local_pkg::fetch_slot_t output_lane0_o,
    output frontend_local_pkg::fetch_slot_t output_lane1_o,
    input rv32_ooo_pkg::lane_count_t output_accept_count_i
);
    import rv32_ooo_pkg::*;
    import frontend_local_pkg::*;
    fetch_slot_t slots_q [0:3], slots_d [0:3];
    logic [2:0] count_q, count_d;
    int unsigned pop_count, push_count, remaining;

    always_comb begin
        output_count_o = '0;
        output_lane0_o = '0;
        output_lane1_o = '0;
        if (rst_ni && !flush_i) begin
            output_count_o = (count_q >= 2) ? 2'd2 : lane_count_t'(count_q);
            if (count_q != 0) output_lane0_o = slots_q[0];
            if (count_q >= 2) output_lane1_o = slots_q[1];
        end

        // compute how many entries to pop and push
        pop_count = int'(output_accept_count_i);
        if (pop_count > int'(output_count_o)) pop_count = int'(output_count_o);
        remaining = int'(count_q) - pop_count;
        // if the buffer is not full, we can accept new entries
        input_ready_o = rst_ni && !flush_i && (remaining <= 2);
        push_count = 0;
        if (input_ready_o && input_count_i <= 2)
            push_count = int'(input_count_i);

        for (int i = 0; i < 4; i++) begin
            slots_d[i] = '0;
            if (i < remaining) slots_d[i] = slots_q[i + pop_count];
        end
        if (push_count >= 1) slots_d[remaining] = input_lane0_i;
        if (push_count == 2) slots_d[remaining + 1] = input_lane1_i;
        count_d = 3'(remaining + push_count);
    end
    // sequential logic to update the buffer state
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            count_q <= '0;
            for (int i = 0; i < 4; i++) slots_q[i] <= '0;
        end else if (flush_i) begin
            count_q <= '0;
            for (int i = 0; i < 4; i++) slots_q[i] <= '0;
        end else begin
            count_q <= count_d;
            for (int i = 0; i < 4; i++) slots_q[i] <= slots_d[i];
        end
    end
// assertions
`ifdef ENABLE_PROTOCOL_ASSERTIONS
    always_ff @(posedge clk_i) if (rst_ni && !flush_i) begin
        assert (input_count_i <= 2);
        assert (output_accept_count_i <= output_count_o);
        assert (count_q <= 4);
    end
`endif
endmodule
