package rv32_ooo_pkg;

    // -------------------------------------------------------------------------
    // Parameters shared by every team.
    //
    // Keeping these in one package prevents each block from silently choosing a
    // different tag width.  The first version intentionally fixes the sizes.
    // Parameterization can be a later exercise after the interfaces are stable.
    // -------------------------------------------------------------------------
    localparam int unsigned XLEN            = 32;

    // Architectural and Physical Register Numbers
    localparam int unsigned ARCH_REG_COUNT  = 32;
    localparam int unsigned ARCH_REG_W      = 5;
    localparam int unsigned PHYS_REG_COUNT  = 64;
    localparam int unsigned PHYS_REG_W      = $clog2(PHYS_REG_COUNT);

    // ROB Capacity and Tag Width
    localparam int unsigned ROB_ENTRY_COUNT = 16;
    localparam int unsigned ROB_INDEX_W     = $clog2(ROB_ENTRY_COUNT);
    localparam int unsigned ROB_GEN_W       = 2;
    localparam int unsigned ROB_TAG_W       = ROB_GEN_W + ROB_INDEX_W;

    // Reset Fetch Address
    localparam logic [XLEN-1:0] RESET_PC = 32'h0000_0000;

    // Register Number Types
    typedef logic [ARCH_REG_W-1:0] arch_reg_t;
    typedef logic [PHYS_REG_W-1:0] phys_reg_t;

    // Occupancy of the free-register pool: 0 through PHYS_REG_COUNT-ARCH_REG_COUNT.
    typedef logic [$clog2(PHYS_REG_COUNT-ARCH_REG_COUNT+1)-1:0] free_count_t;

    // Counts on a two-wide ordered interface are encoded as 0, 1, or 2.
    typedef logic [1:0] lane_count_t;


    // A generation accompanies the circular ROB index.  A response must match
    // both fields; matching only the index risks accepting a stale response after
    // that ROB slot has been reused.
    typedef struct packed {
        logic [ROB_GEN_W-1:0]   generation;
        logic [ROB_INDEX_W-1:0] index;
    } rob_tag_t;


    // ----- ALLLL of these is to simplify the decode -----
    typedef enum logic [2:0] {
        UOP_INVALID,
        UOP_ALU,
        UOP_BRANCH,
        UOP_JUMP,
        UOP_LOAD,
        UOP_STORE,
        UOP_CSR
    } uop_class_e;

    // ALU Operation
    typedef enum logic [3:0] {
        ALU_ADD,
        ALU_SUB,
        ALU_SLL,
        ALU_SLT,
        ALU_SLTU,
        ALU_XOR,
        ALU_SRL,
        ALU_SRA,
        ALU_OR,
        ALU_AND,
        ALU_PASS_A,
        ALU_PASS_B
    } alu_op_e;

    // ALU Operand Mux Selections
    typedef enum logic [1:0] {
        OPA_ZERO,
        OPA_RS1,
        OPA_PC
    } operand_a_sel_e;

    typedef enum logic [1:0] {
        OPB_ZERO,
        OPB_RS2,
        OPB_IMM,
        OPB_FOUR
    } operand_b_sel_e;

    // Branch Comparison or Jump Type
    typedef enum logic [3:0] {
        BR_NONE,
        BR_BEQ,
        BR_BNE,
        BR_BLT,
        BR_BGE,
        BR_BLTU,
        BR_BGEU,
        BR_JAL,
        BR_JALR
    } branch_op_e;

    // Memory Command and Access Size
    typedef enum logic [1:0] {
        MEM_NONE,
        MEM_LOAD,
        MEM_STORE
    } mem_cmd_e;

    typedef enum logic [1:0] {
        MEM_BYTE,
        MEM_HALF,
        MEM_WORD
    } mem_size_e;

    // CSR Read/Write, Set, or Clear Command
    typedef enum logic [2:0] {
        CSR_NONE,
        CSR_RW,
        CSR_RS,
        CSR_RC
    } csr_cmd_e;


    // Decode expresses intent rather than implementation.  For example, the
    // backend does not need to decode opcode bits again to discover whether an
    // immediate or rs2 should feed the ALU.
    typedef struct packed {
        // Fetch Metadata
        logic [XLEN-1:0]  pc;
        logic [31:0]      instruction;
        logic [XLEN-1:0]  predicted_next_pc;

        // Architectural Register Operands and Destination
        arch_reg_t        rs1;
        arch_reg_t        rs2;
        arch_reg_t        rd;
        logic             uses_rs1;
        logic             uses_rs2;
        logic             writes_rd;

        // Execution Unit and Operation Selection
        uop_class_e       uop_class;
        alu_op_e          alu_op;
        operand_a_sel_e   operand_a_sel;
        operand_b_sel_e   operand_b_sel;
        branch_op_e       branch_op;

        // Load/Store Controls
        mem_cmd_e         mem_cmd;
        mem_size_e        mem_size;
        logic             load_unsigned;

        // CSR Controls
        csr_cmd_e         csr_cmd;
        logic             csr_uses_immediate;
        logic [11:0]      csr_address;
        logic [4:0]       csr_immediate;

        // Immediate Value and Decode/Fetch Errors
        logic [XLEN-1:0]  immediate;
        logic             illegal;
        logic             fetch_error;
    } decoded_uop_t;


    // ----- ALL of these survive the movement from FRONTEND -> BACKEND -----
    typedef struct packed {
        decoded_uop_t decoded;
        rob_tag_t     rob_tag;
        phys_reg_t    psrc1;
        phys_reg_t    psrc2;
        phys_reg_t    pdst;
        logic         has_destination;

        // With one unresolved branch, a single bit is sufficient.  The branch
        // instruction itself has zero here; only younger instructions have one.
        logic         under_unresolved_branch;
    } renamed_uop_t;

    // Ordered Two-Wide Dispatch Bundle
    typedef struct packed {
        renamed_uop_t lane0;
        renamed_uop_t lane1;
    } renamed_bundle_t;


    // ----- This is just a useful function -----
    function automatic logic is_control_flow(input decoded_uop_t uop);
        is_control_flow = (uop.branch_op != BR_NONE);
    endfunction


    // ----- THIS IS FOR THE BACKEND EXECUTION AND SURVIVES TILL THE ROB -----
    // A completion always marks its ROB entry done.  writeback_valid separately
    // says whether the physical register file must be updated.
    typedef struct packed {
        rob_tag_t        rob_tag;
        logic            writeback_valid;
        phys_reg_t       writeback_pdst;
        logic [XLEN-1:0] value;
        logic            under_unresolved_branch;
    } execution_result_t;


    // ----- ALLLLLLL OF THESE ARE TO HANDLE THE ROB STUFF -----
    typedef logic [ROB_TAG_W-1:0] rob_tag_flat_t;

    typedef struct packed {
        rob_tag_t        rob_tag;
        decoded_uop_t    decoded;
        phys_reg_t       pdst;
        phys_reg_t       old_pdst;
        logic            has_destination;
        logic [XLEN-1:0] value;
    } rob_retire_data_t;

    // Pack Generation and Index into One Number
    function automatic rob_tag_flat_t flatten_rob_tag(input rob_tag_t tag);
        flatten_rob_tag = {tag.generation, tag.index};
    endfunction

    // ROB tags form a small modulo sequence.  Since no more than
    // ROB_ENTRY_COUNT tags may be live, modular subtraction is unambiguous.
    function automatic rob_tag_t increment_rob_tag(
        input rob_tag_t tag,
        input lane_count_t amount
    );
        rob_tag_flat_t flat;
        begin
            flat = flatten_rob_tag(tag) + ROB_TAG_W'(amount);
            increment_rob_tag = rob_tag_t'(flat);
        end
    endfunction

    // Modular Distance Used to Compare Instruction Ages
    function automatic rob_tag_flat_t rob_tag_distance(
        input rob_tag_t newer,
        input rob_tag_t older
    );
        rob_tag_distance = flatten_rob_tag(newer) - flatten_rob_tag(older);
    endfunction

endpackage
