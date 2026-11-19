// read two instruction words on the ROM clock edge
// sample the address when read_enable is high
// hold the last result when read_enable is low


interface instruction_memory_if;

    import instruction_memory_pkg::*;

    // fetch sends a byte address aligned to four bytes
    imem_address_t address;
    logic read_enable; // take a new address on the clock edge

    // the low word is at address, the high word is at address + 4
    imem_data_t data;

    // one error bit per word for a bad address or invalid word
    imem_error_t error; // which returned words had a problem


    // frontend side
    // read_enable controls when the ROM takes a new address
    modport frontend (
        output address,
               read_enable,

        input data,
              error
    );


    // ROM side
    modport memory (
        input address,
              read_enable,

        output data,
               error
    );

endinterface
