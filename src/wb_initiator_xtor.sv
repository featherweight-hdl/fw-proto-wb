// Initiator transactor module: instances the transactor-interface + core and
// wires them with the two plain ready/valid link buses (request + response),
// exposing clock/reset + the Wishbone MASTER pins. Reach `u_if` from a testbench
// to bind the initiator bridge's virtual interface.
module wb_initiator_xtor
    import wb_types_pkg::*;
(
    input                  clock,
    input                  reset,
    output bit [WB_AW-1:0] adr_o,
    output bit [WB_DW-1:0] dat_o,
    output bit [WB_SW-1:0] sel_o,
    output bit             we_o,
    output bit             cyc_o,
    output bit             stb_o,
    input      [WB_DW-1:0] dat_i,
    input                  ack_i,
    input                  err_i,
    input                  rty_i
);
    wb_req_t req_data;
    bit      req_valid;
    bit      req_ready;
    wb_rsp_t rsp_data;
    bit      rsp_valid;
    bit      rsp_ready;

    wb_initiator_xtor_if u_if (
        .clock(clock), .reset(reset),
        .req_data(req_data), .req_valid(req_valid), .req_ready(req_ready),
        .rsp_data(rsp_data), .rsp_valid(rsp_valid), .rsp_ready(rsp_ready)
    );
    wb_initiator_xtor_core u_core (
        .clock(clock), .reset(reset),
        .req_data(req_data), .req_valid(req_valid), .req_ready(req_ready),
        .rsp_data(rsp_data), .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .adr_o(adr_o), .dat_o(dat_o), .sel_o(sel_o), .we_o(we_o),
        .cyc_o(cyc_o), .stb_o(stb_o),
        .dat_i(dat_i), .ack_i(ack_i), .err_i(err_i), .rty_i(rty_i)
    );
endmodule
