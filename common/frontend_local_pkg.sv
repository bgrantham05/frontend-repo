// types used inside the frontend
package frontend_local_pkg;
    // one instruction with its PC, prediction, and fetch error
    typedef struct packed {
        logic [31:0] pc; // address of this instruction
        logic [31:0] instruction;
        logic [31:0] predicted_next_pc; // where we think execution goes next
        logic fetch_error; // the ROM reported a problem with this word
    } fetch_slot_t;
endpackage
