`timescale 1ns/1ps
module frontend_reg_rename_tb;
    import rv32_ooo_pkg::*;
    logic clk = 0;
    always #5 clk = !clk;

    logic rst_n = 0, reclaim = 0;
    lane_count_t decoded_count = 0, admission = 2, accept = 0, offered;
    decoded_uop_t lane0, lane1;
    rob_tag_t tail_tag = rob_tag_t'(15);
    renamed_bundle_t bundle;
    phys_reg_t old0, old1, returned_pdst;
    free_count_t free_count;

    frontend_reg_rename dut (
        .clk_i(clk), .rst_ni(rst_n), .decoded_count_i(decoded_count),
        .decoded_lane0_i(lane0), .decoded_lane1_i(lane1),
        .admission_count_i(admission), .rob_tail_tag_i(tail_tag),
        .older_branch_pending_i(1'b0), .dispatch_accept_count_i(accept),
        .dispatch_count_o(offered), .dispatch_bundle_o(bundle),
        .old_pdst_lane0_o(old0), .old_pdst_lane1_o(old1),
        .reclaim_valid_i(reclaim), .reclaim_pdst_i(returned_pdst), .free_count_o(free_count)
    );

    function automatic decoded_uop_t writing(input arch_reg_t rd, rs1, rs2);
        decoded_uop_t uop = '0;
        uop.rd = rd;
        uop.rs1 = rs1;
        uop.rs2 = rs2;
        uop.writes_rd = 1;
        uop.uses_rs1 = 1;
        uop.uses_rs2 = 1;
        return uop;
    endfunction

    task automatic advance(input lane_count_t count, input bit give_back = 0,
                           input phys_reg_t returned = 0);
        accept = count;
        reclaim = give_back;
        returned_pdst = returned;
        @(posedge clk);
        #1;
        accept = 0;
        reclaim = 0;
    endtask

    initial begin
        @(negedge clk);
        rst_n = 1;
        lane0 = writing(5, 5, 0);
        lane1 = writing(5, 5, 5);
        decoded_count = 2;
        #1;
        if (offered !== 2 || free_count !== 32 ||
            bundle.lane0.psrc1 !== 5 || bundle.lane0.psrc2 !== 0 ||
            bundle.lane0.pdst !== 32 || old0 !== 5 ||
            bundle.lane1.psrc1 !== 32 || bundle.lane1.psrc2 !== 32 ||
            bundle.lane1.pdst !== 33 || old1 !== 32 ||
            flatten_rob_tag(bundle.lane1.rob_tag) !== 16)
            $fatal(1, "Reset mapping, lane forwarding, or tag rollover is incorrect");
        advance(0);
        if (free_count !== 32 || bundle.lane0.pdst !== 32)
            $fatal(1, "A stalled offer must not allocate");

        advance(1);
        lane0 = lane1;
        decoded_count = 1;
        #1;
        if (free_count !== 31 || bundle.lane0.psrc1 !== 32 || bundle.lane0.pdst !== 33)
            $fatal(1, "Partial acceptance must update only lane 0");

        lane1 = writing(5, 5, 0);
        decoded_count = 2;
        #1;
        advance(2, 1, 5);
        if (free_count !== 30 || bundle.lane0.psrc1 !== 34)
            $fatal(1, "Dual WAW and concurrent reclamation are incorrect");

        decoded_count = 1;
        for (int i = 35; i < 64; i++) begin
            #1;
            if (offered !== 1 || bundle.lane0.pdst !== phys_reg_t'(i))
                $fatal(1, "Unexpected free-list allocation");
            advance(1);
        end
        if (free_count !== 1 || bundle.lane0.pdst !== 5)
            $fatal(1, "Reclaimed register missing after FIFO wrap");
        advance(1);
        if (free_count !== 0 || offered !== 0)
            $fatal(1, "Empty free list must stall a destination write");

        lane0 = writing(0, 0, 0);
        decoded_count = 2;
        #1;
        if (offered !== 1 || bundle.lane0.has_destination || bundle.lane0.psrc1 !== 0)
            $fatal(1, "x0 must dispatch without consuming a physical register");
        advance(1, 1, 32);
        if (free_count !== 1 || offered !== 2 || bundle.lane1.pdst !== 32)
            $fatal(1, "Reclamation must unblock the next destination instruction");

        admission = 0;
        #1;
        if (offered !== 0)
            $fatal(1, "External admission limit must suppress dispatch");
        $display("frontend_reg_rename_tb passed");
        $finish;
    end
endmodule
