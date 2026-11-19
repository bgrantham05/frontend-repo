// types for ROM addresses, instruction pairs, and errors


package instruction_memory_pkg;

    import rv32_ooo_pkg::*;

    // one byte address returns two 32-bit instructions
    typedef logic [XLEN-1:0] imem_address_t;
    typedef logic [63:0] imem_data_t; // two 32-bit instructions

    // bit 0 is the low word's error, bit 1 is the high word's error
    typedef logic [1:0] imem_error_t;

endpackage
