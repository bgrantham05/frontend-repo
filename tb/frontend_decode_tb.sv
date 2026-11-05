`timescale 1ns/1ps
// Directed checks for both decoder lanes
module frontend_decode_tb;
    // Shared types and test stimulus
    import rv32_ooo_pkg::*;
    logic [31:0] instruction = 0;
    logic fetch_error = 0;
    decoded_uop_t d, d1;
    // Connect variable lane zero and fixed lane one
    frontend_decode_pair dut (
        .instruction0_i(instruction), .instruction1_i(32'h00500113),
        .pc0_i(32'h100), .pc1_i(32'h104),
        .predicted_next_pc0_i(32'h200), .predicted_next_pc1_i(32'h108),
        .fetch_error0_i(fetch_error), .fetch_error1_i(1'b0),
        .decoded0_o(d), .decoded1_o(d1)
    );

    // Stop on a failed or unknown condition
    task automatic check(input logic condition, input string message);
        if (condition !== 1'b1) $fatal(1, "%s instruction=%h", message, instruction);
    endtask
    // Apply an instruction and verify preserved metadata
    task automatic drive(input logic [31:0] word);
        instruction = word;
        #1;
        check(d.pc == 32'h100 && d.predicted_next_pc == 32'h200 &&
              d.instruction == word, "metadata");
        check(!d1.illegal && d1.rd == 2 && d1.immediate == 5 &&
              d1.pc == 32'h104, "lane independence");
    endtask
    // Verify illegal instructions cannot request side effects
    task automatic invalid(input logic [31:0] word);
        drive(word);
        check(d.illegal && d.uop_class == UOP_INVALID && !d.writes_rd &&
              !d.uses_rs1 && !d.uses_rs2 && d.mem_cmd == MEM_NONE &&
              d.csr_cmd == CSR_NONE && d.branch_op == BR_NONE, "illegal side effects");
    endtask
    // Expected base ALU operations
    function automatic alu_op_e expected_alu(input int f);
        case (f)
            0: return ALU_ADD;
            1: return ALU_SLL;
            2: return ALU_SLT;
            3: return ALU_SLTU;
            4: return ALU_XOR;
            5: return ALU_SRL;
            6: return ALU_OR;
            default: return ALU_AND;
        endcase
    endfunction
    // Expected conditional branch comparisons
    function automatic branch_op_e expected_branch(input int f);
        case (f)
            0: return BR_BEQ;
            1: return BR_BNE;
            4: return BR_BLT;
            5: return BR_BGE;
            6: return BR_BLTU;
            default: return BR_BGEU;
        endcase
    endfunction

    // Run directed instruction tests
    initial begin
        // Every base register ALU operation, plus SUB/SRA variants.
        for (int f = 0; f < 8; f++) begin
            drive({7'b0, 5'd3, 5'd2, 3'(f), 5'd1, 7'b0110011});
            check(!d.illegal && d.alu_op == expected_alu(f) && d.uses_rs1 &&
                  d.uses_rs2 && d.writes_rd && d.rs1 == 2 && d.rs2 == 3 &&
                  d.rd == 1 && d.operand_b_sel == OPB_RS2, "register ALU");
            // All nonshift immediate ALU operations use signed I immediates.
            if (f != 1 && f != 5) begin
                drive({12'hfff, 5'd2, 3'(f), 5'd1, 7'b0010011});
                check(!d.illegal && d.alu_op == expected_alu(f) &&
                      d.immediate == 32'hffffffff && !d.uses_rs2 &&
                      d.operand_b_sel == OPB_IMM, "immediate ALU");
            end
        end
        // Subtraction and register arithmetic shift
        drive(32'h403100b3); check(d.alu_op == ALU_SUB && !d.illegal, "SUB");
        drive(32'h403150b3); check(d.alu_op == ALU_SRA && !d.illegal, "SRA");
        // Immediate shifts at the maximum shift amount
        drive(32'h01f11093); check(d.alu_op == ALU_SLL && d.immediate == 31 && !d.illegal, "SLLI");
        drive(32'h01f15093); check(d.alu_op == ALU_SRL && d.immediate == 31 && !d.illegal, "SRLI");
        drive(32'h41f15093); check(d.alu_op == ALU_SRA && d.immediate == 31 && !d.illegal, "SRAI");
        // Unsupported multiply and reserved shift encodings
        invalid(32'h023100b3); // MUL, outside RV32I
        invalid(32'h403110b3); // Reserved SLL funct7
        invalid(32'h02011093); // Reserved SLLI high immediate
        invalid(32'h02015093); // Reserved right shift

        // Legal and reserved memory and branch variants
        for (int f = 0; f < 8; f++) begin
            // Load widths and signedness
            if (f == 0 || f == 1 || f == 2 || f == 4 || f == 5) begin
                drive({12'hffc, 5'd2, 3'(f), 5'd1, 7'b0000011});
                check(!d.illegal && d.mem_cmd == MEM_LOAD && d.writes_rd &&
                      d.immediate == 32'hfffffffc && d.load_unsigned == (f >= 4) &&
                      d.mem_size == mem_size_e'(f % 4), "load");
            end else invalid({12'b0, 5'd2, 3'(f), 5'd1, 7'b0000011});
            // Store widths and split negative offsets
            if (f < 3) begin
                drive({7'h7f, 5'd3, 5'd2, 3'(f), 5'h1c, 7'b0100011});
                check(!d.illegal && d.mem_cmd == MEM_STORE && !d.writes_rd &&
                      d.uses_rs2 && d.immediate == 32'hfffffffc &&
                      d.mem_size == mem_size_e'(f), "store");
            end else invalid({7'b0, 5'd3, 5'd2, 3'(f), 5'b0, 7'b0100011});
            // Branch comparisons and split negative offsets
            if (f != 2 && f != 3) begin
                // Branch offset -4, split across B-immediate fields.
                drive({7'h7f, 5'd3, 5'd2, 3'(f), 5'h1d, 7'b1100011});
                check(!d.illegal && d.branch_op == expected_branch(f) &&
                      d.immediate == 32'hfffffffc && !d.writes_rd &&
                      d.uses_rs1 && d.uses_rs2, "branch");
            end else invalid({17'b0, 3'(f), 5'b0, 7'b1100011});
        end
        // Direct and indirect jump offsets
        drive(32'hffdff0ef); check(!d.illegal && d.branch_op == BR_JAL &&
            d.immediate == 32'hfffffffc && !d.uses_rs1 &&
            d.operand_b_sel == OPB_FOUR, "JAL");
        drive(32'hffc100e7); check(!d.illegal && d.branch_op == BR_JALR &&
            d.immediate == 32'hfffffffc && d.uses_rs1, "JALR");
        invalid(32'h000110e7);
        // Upper-immediate values and operand selection
        drive(32'habcde0b7); check(!d.illegal && d.immediate == 32'habcde000 &&
            d.operand_a_sel == OPA_ZERO && !d.uses_rs1, "LUI");
        drive(32'habcde097); check(!d.illegal && d.operand_a_sel == OPA_PC &&
            d.immediate == 32'habcde000, "AUIPC");
        // All six CSR operation forms
        for (int f = 1; f < 8; f++) if (f != 4) begin
            drive({12'h7c0, 5'd3, 3'(f), 5'd1, 7'b1110011});
            check(!d.illegal && d.uop_class == UOP_CSR && d.writes_rd &&
                  d.csr_address == 12'h7c0 && d.csr_immediate == 3 &&
                  d.csr_uses_immediate == (f >= 4) && d.uses_rs1 == (f < 4) &&
                  d.csr_cmd == csr_cmd_e'(f % 4), "CSR");
        end
        // x0 suppresses register writes while retaining load behavior
        drive(32'h00000013); check(!d.illegal && !d.writes_rd, "x0/NOP");
        drive(32'h00002003); check(!d.illegal && !d.writes_rd &&
            d.mem_cmd == MEM_LOAD, "load x0 still accesses memory");
        // Unresolved system operations and unknown encodings
        invalid(32'h00000073); // ECALL unresolved
        invalid(32'h00100073); // EBREAK unresolved
        invalid(32'h0000000f); // FENCE unresolved
        invalid(32'hffffffff);
        // Fetch faults suppress execution without changing encoding legality
        fetch_error = 1;
        drive(32'h00100093);
        check(d.fetch_error && !d.illegal && !d.writes_rd &&
              d.uop_class == UOP_INVALID, "fetch fault suppression");
        // Report successful completion
        $display("PASS: frontend_decode_tb");
        $finish;
    end
endmodule
