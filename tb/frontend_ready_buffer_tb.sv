`timescale 1ns/1ps
module frontend_ready_buffer_tb;
    import rv32_ooo_pkg::*;
    import frontend_local_pkg::*;
    logic clk = 0;
    always #5 clk = !clk;
    logic rst_n = 0, flush = 0, ready;
    lane_count_t input_count = 0, output_count, accept_count = 0;
    fetch_slot_t in0, in1, out0, out1;
    fetch_slot_t expected[$];
    fetch_slot_t discarded;
    int serial = 0;
    frontend_ready_buffer dut (
        .clk_i(clk), .rst_ni(rst_n), .flush_i(flush),
        .input_count_i(input_count), .input_lane0_i(in0), .input_lane1_i(in1),
        .input_ready_o(ready), .output_count_o(output_count),
        .output_lane0_o(out0), .output_lane1_o(out1),
        .output_accept_count_i(accept_count)
    );

    function automatic fetch_slot_t packet(input int n);
        fetch_slot_t p;
        p.pc = 32'(n * 4);
        p.instruction = 32'h80000000 ^ 32'(n);
        p.predicted_next_pc = 32'(n * 4 + 4);
        p.fetch_error = (n % 3 == 0);
        return p;
    endfunction

    task automatic check_output;
        int wanted;
        wanted = (!rst_n || flush) ? 0 : ((expected.size() >= 2) ? 2 : expected.size());
        if (int'(output_count) != wanted) $fatal(1, "Output count mismatch");
        if (wanted >= 1 && out0 !== expected[0]) $fatal(1, "Head/metadata mismatch");
        if (wanted == 2 && out1 !== expected[1]) $fatal(1, "Lane 1/metadata mismatch");
        if ((!rst_n || flush) && ready) $fatal(1, "Ready during reset/flush");
    endtask

    task automatic cycle(input int offered, input int accepted, input bit do_flush);
        bit should_ready;
        @(negedge clk);
        flush = do_flush;
        input_count = lane_count_t'(offered);
        accept_count = lane_count_t'(accepted);
        in0 = packet(serial);
        in1 = packet(serial + 1);
        #1;
        check_output();
        if (!do_flush) begin
            if (accepted > int'(output_count)) $fatal(1, "Invalid test acceptance");
            should_ready = (expected.size() - accepted <= 2);
            if (ready !== should_ready) $fatal(1, "Capacity reservation mismatch");
        end
        @(posedge clk);
        if (do_flush) expected.delete();
        else begin
            repeat (accepted) discarded = expected.pop_front();
            if (ready) begin
                if (offered >= 1) expected.push_back(in0);
                if (offered == 2) expected.push_back(in1);
                serial += offered;
            end
        end
        #1;
        check_output();
    endtask

    initial begin
        in0 = '0; in1 = '0;
        @(posedge clk); #1; check_output();
        @(negedge clk); rst_n = 1;
        cycle(2, 0, 0); // Empty -> two entries.
        cycle(2, 0, 0); // Full four-entry queue.
        repeat (4) cycle(2, 0, 0); // Full stall, no overwrite.
        cycle(2, 1, 0); // Only one free slot: reject whole incoming bundle.
        cycle(2, 1, 0); // Compact survivor and append two new entries.
        cycle(2, 2, 0); // Full simultaneous dequeue/enqueue.
        cycle(0, 1, 0);
        cycle(0, 2, 0);
        cycle(1, 1, 0); // Replace final entry with a single valid lane.
        cycle(2, 0, 1); // Flush while stalled and input offered.
        cycle(1, 0, 0);
        cycle(2, 1, 1); // Flush wins over apparent acceptance/replacement.
        cycle(0, 0, 0);
        repeat (300) begin
            cycle($urandom_range(0, 2),
                  $urandom_range(0, (expected.size() >= 2) ? 2 : expected.size()),
                  ($urandom_range(0, 19) == 0));
        end
        while (expected.size() != 0)
            cycle(0, (expected.size() >= 2) ? 2 : 1, 0);
        cycle(2, 0, 0);
        @(negedge clk); rst_n = 0; expected.delete();
        #1; check_output();
        @(posedge clk); #1; check_output();
        @(negedge clk); rst_n = 1; accept_count = 0; input_count = 0;
        cycle(1, 0, 0);
        cycle(0, 1, 0);
        $display("PASS: frontend_ready_buffer_tb");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "Timeout");
    end
endmodule
