// sizes and types shared by the processor stages
package rv32_ooo_pkg;

    // keep these sizes the same across teams
    localparam int unsigned XLEN            = 32;

    // architectural and physical register counts and widths
    localparam int unsigned ARCH_REG_COUNT  = 32;
    localparam int unsigned ARCH_REG_W      = 5;
    localparam int unsigned PHYS_REG_COUNT  = 64;
    localparam int unsigned PHYS_REG_W      = $clog2(PHYS_REG_COUNT);

    // ROB size and tag widths
    localparam int unsigned ROB_ENTRY_COUNT = 16;
    localparam int unsigned ROB_INDEX_W     = $clog2(ROB_ENTRY_COUNT);
    localparam int unsigned ROB_GEN_W       = 2;
    localparam int unsigned ROB_TAG_W       = ROB_GEN_W + ROB_INDEX_W;

    // PC to start from on reset
    localparam logic [XLEN-1:0] RESET_PC = 32'h0000_0000;

    // register number types
    typedef logic [ARCH_REG_W-1:0] arch_reg_t;
    typedef logic [PHYS_REG_W-1:0] phys_reg_t;

    // count how many physical registers are free
    typedef logic [$clog2(PHYS_REG_COUNT-ARCH_REG_COUNT+1)-1:0] free_count_t;

    // send or accept 0, 1, or 2 lanes
    typedef logic [1:0] lane_count_t;


    // check both tag fields so an old result can't match a reused slot
    typedef struct packed {
        logic [ROB_GEN_W-1:0]   generation; // which pass through the slot
        logic [ROB_INDEX_W-1:0] index; // which ROB slot
    } rob_tag_t;


    // instruction types and execution controls
    typedef enum logic [2:0] {
        UOP_INVALID,
        UOP_ALU,
        UOP_BRANCH,
        UOP_JUMP,
        UOP_LOAD,
        UOP_STORE,
        UOP_CSR
    } uop_class_e;

    // ALU operations
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

    // where the ALU operands come from
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

    // branch comparisons and jump types
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

    // load or store, and how many bytes
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

    // CSR write, set, and clear operations
    typedef enum logic [2:0] {
        CSR_NONE,
        CSR_RW,
        CSR_RS,
        CSR_RC
    } csr_cmd_e;


    // decode tells the backend which operands and controls to use
    typedef struct packed {
        // values passed through from fetch
        logic [XLEN-1:0]  pc;
        logic [31:0]      instruction;
        logic [XLEN-1:0]  predicted_next_pc;

        // which registers the instruction reads or writes
        arch_reg_t        rs1;
        arch_reg_t        rs2;
        arch_reg_t        rd;
        logic             uses_rs1;
        logic             uses_rs2;
        logic             writes_rd; // instruction writes a result

        // operation and operand choices
        uop_class_e       uop_class;
        alu_op_e          alu_op;
        operand_a_sel_e   operand_a_sel;
        operand_b_sel_e   operand_b_sel;
        branch_op_e       branch_op;

        // load and store controls
        mem_cmd_e         mem_cmd;
        mem_size_e        mem_size;
        logic             load_unsigned;

        // CSR operation and source
        csr_cmd_e         csr_cmd;
        logic             csr_uses_immediate;
        logic [11:0]      csr_address;
        logic [4:0]       csr_immediate;

        // immediate value and error flags
        logic [XLEN-1:0]  immediate;
        logic             illegal;
        logic             fetch_error;
    } decoded_uop_t;


    // renamed instruction sent to the backend
    typedef struct packed {
        decoded_uop_t decoded;
        rob_tag_t     rob_tag;
        phys_reg_t    psrc1;
        phys_reg_t    psrc2;
        phys_reg_t    pdst;
        logic         has_destination;

        // with one unresolved branch, this bit marks the instructions younger than it
        logic         under_unresolved_branch;
    } renamed_uop_t;

    // lane 0 is older than lane 1
    typedef struct packed {
        renamed_uop_t lane0;
        renamed_uop_t lane1;
    } renamed_bundle_t;


    // branches and jumps have a branch op other than BR_NONE
    function automatic logic is_control_flow(input decoded_uop_t uop);
        is_control_flow = (uop.branch_op != BR_NONE);
    endfunction


    // completion marks the ROB entry done, writeback_valid controls the register write
    typedef struct packed {
        rob_tag_t        rob_tag;
        logic            writeback_valid;
        phys_reg_t       writeback_pdst;
        logic [XLEN-1:0] value;
        logic            under_unresolved_branch;
    } execution_result_t;


    // info the ROB keeps until retirement
    typedef logic [ROB_TAG_W-1:0] rob_tag_flat_t;

    typedef struct packed {
        rob_tag_t        rob_tag;
        decoded_uop_t    decoded;
        phys_reg_t       pdst;
        phys_reg_t       old_pdst; // register to free when this retires
        logic            has_destination;
        logic [XLEN-1:0] value;
    } rob_retire_data_t;

    // put the generation and index into one number
    function automatic rob_tag_flat_t flatten_rob_tag(input rob_tag_t tag);
        flatten_rob_tag = {tag.generation, tag.index};
    endfunction

    // subtract tags with wraparound to compare ages within the live ROB
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

    // get the distance from the older tag to the newer tag
    function automatic rob_tag_flat_t rob_tag_distance(
        input rob_tag_t newer,
        input rob_tag_t older
    );
        rob_tag_distance = flatten_rob_tag(newer) - flatten_rob_tag(older);
    endfunction

endpackage
