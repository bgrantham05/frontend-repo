// Frontend-private types; shared course packages/interfaces stay unchanged.
package frontend_local_pkg;
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instruction;
        logic [31:0] predicted_next_pc;
        logic fetch_error;
    } fetch_slot_t;
endpackage
