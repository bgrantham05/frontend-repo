// Shared types for the synchronous instruction ROM interface.


package instruction_memory_pkg;

    // Import Packages
    import rv32_ooo_pkg::*;

    // ----- One Address, Two Consecutive Instructions -----
    typedef logic [XLEN-1:0] imem_address_t;
    typedef logic [63:0] imem_data_t;

    // One Error Bit for Each Returned Instruction
    typedef logic [1:0] imem_error_t;

endpackage
