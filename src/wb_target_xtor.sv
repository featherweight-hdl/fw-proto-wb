// Target transactor module: instances the core + transactor-interface and wires
// them with the two plain ready/valid link buses, exposing clock/reset + the
// Wishbone SLAVE pins. Reach `u_if` from a testbench to bind the target bridge's
// virtual interface.
module wb_target_xtor
    import wb_types_pkg::*;
(
    input                  clock,
    input                  reset,
    input  [WB_AW-1:0]     adr_i,
    input  [WB_DW-1:0]     dat_i,
    input  [WB_SW-1:0]     sel_i,
    input                  we_i,
    input                  cyc_i,
    input                  stb_i,
    output bit [WB_DW-1:0] dat_o,
    output bit             ack_o,
    output bit             err_o,
    output bit             rty_o
);
    wb_req_t req_data;
    bit      req_valid;
    bit      req_ready;
    wb_rsp_t rsp_data;
    bit      rsp_valid;
    bit      rsp_ready;

    wb_target_xtor_if u_if (
        .clock(clock), .reset(reset),
        .req_data(req_data), .req_valid(req_valid), .req_ready(req_ready),
        .rsp_data(rsp_data), .rsp_valid(rsp_valid), .rsp_ready(rsp_ready)
    );
    wb_target_xtor_core u_core (
        .clock(clock), .reset(reset),
        .req_data(req_data), .req_valid(req_valid), .req_ready(req_ready),
        .rsp_data(rsp_data), .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .adr_i(adr_i), .dat_i(dat_i), .sel_i(sel_i), .we_i(we_i),
        .cyc_i(cyc_i), .stb_i(stb_i),
        .dat_o(dat_o), .ack_o(ack_o), .err_o(err_o), .rty_o(rty_o)
    );
endmodule
