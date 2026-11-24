// hold up to four instructions in order, even when the next stage stalls
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
    // slot 0 holds the oldest instruction, count_q tells us how many are valid
    fetch_slot_t slots_q [0:3], slots_d [0:3];
    logic [2:0] count_q, count_d; // how many are stored now and after the edge
    int unsigned pop_count, push_count, remaining;

    always_comb begin
        output_count_o = '0; // offer nothing by default
        output_lane0_o = '0;
        output_lane1_o = '0;
        if (rst_ni && !flush_i) begin
            output_count_o = (count_q >= 2) ? 2'd2 : lane_count_t'(count_q);
            if (count_q != 0) output_lane0_o = slots_q[0]; // send the oldest first
            if (count_q >= 2) output_lane1_o = slots_q[1]; // send the next one if present
        end
    end

    always_comb begin
        // remove only the oldest instructions the next stage accepted
        pop_count = int'(output_accept_count_i);
        if (pop_count > int'(output_count_o)) pop_count = int'(output_count_o);
        remaining = int'(count_q) - pop_count; // leave unaccepted instructions in place for now
        // check for two free slots after removing accepted instructions
        input_ready_o = rst_ni && !flush_i && (remaining <= 2);
        push_count = 0; // take nothing unless there is room
        if (input_ready_o && input_count_i <= 2)
            push_count = int'(input_count_i);

        // shift the remaining instructions forward, then add new ones at the end
        for (int i = 0; i < 4; i++) begin
            slots_d[i] = '0;
            if (i < remaining) slots_d[i] = slots_q[i + pop_count]; // move older survivors to the front
        end
        if (push_count >= 1) slots_d[remaining] = input_lane0_i;
        if (push_count == 2) slots_d[remaining + 1] = input_lane1_i;
        count_d = 3'(remaining + push_count); // count the instructions for next cycle
    end
    // clear the queue on reset or flush before moving any instructions
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            count_q <= '0;
            for (int i = 0; i < 4; i++) slots_q[i] <= '0;
        end else if (flush_i) begin // discard the wrong-path instructions
            count_q <= '0;
            for (int i = 0; i < 4; i++) slots_q[i] <= '0;
        end else begin
            count_q <= count_d; // save the updated queue size
            for (int i = 0; i < 4; i++) slots_q[i] <= slots_d[i];
        end
    end
    // check that the counts stay in range
`ifdef ENABLE_PROTOCOL_ASSERTIONS
    always_ff @(posedge clk_i) if (rst_ni && !flush_i) begin
        assert (input_count_i <= 2);
        assert (output_accept_count_i <= output_count_o);
        assert (count_q <= 4);
    end
`endif
endmodule
