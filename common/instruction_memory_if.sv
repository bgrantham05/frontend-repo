// Fixed one-cycle synchronous instruction-ROM contract.
// On an enabled ROM clock edge, sample address and update both words/errors.
// Disabled edges HOLD the previous output. ROM and frontend use the same clock.


interface instruction_memory_if;

    // Import Packages
    import instruction_memory_pkg::*;

    // From Fetch - word-aligned byte address, not necessarily eight-byte aligned
    imem_address_t address;
    logic read_enable;

    // From ROM - low word is at address, high word is at address+4
    imem_data_t data;

    // error[n] marks an invalid, misaligned, or out-of-range word in lane n
    imem_error_t error;


    // ----- Frontend Side -----
    // No ready/valid handshake or epoch: read_enable controls the synchronous read.
    modport frontend (
        output address,
               read_enable,

        input data,
              error
    );


    // ----- Instruction ROM Side -----
    modport memory (
        input address,
              read_enable,

        output data,
               error
    );

endinterface
