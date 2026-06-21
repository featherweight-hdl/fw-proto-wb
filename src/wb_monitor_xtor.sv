// Monitor transactor module: instances the monitor core + transactor-interface and
// wires them with the plain ready/valid link, exposing clock/reset + the Wishbone
// bus TAPS (all inputs -- the monitor drives nothing). Reach `u_if` from a
// testbench to bind the monitor bridge's virtual interface.
module wb_monitor_xtor
    import wb_types_pkg::*;
(
    input              clock,
    input              reset,
    input  [WB_AW-1:0] adr,
    input  [WB_DW-1:0] dat_w,
    input  [WB_DW-1:0] dat_r,
    input  [WB_SW-1:0] sel,
    input              we,
    input              cyc,
    input              stb,
    input              ack,
    input              err,
    input              rty
);
    wb_xfer_t up_data;
    bit       up_valid;
    bit       up_ready;

    wb_monitor_xtor_if u_if (
        .clock(clock), .reset(reset),
        .up_data(up_data), .up_valid(up_valid), .up_ready(up_ready)
    );
    wb_monitor_xtor_core u_core (
        .clock(clock), .reset(reset),
        .up_data(up_data), .up_valid(up_valid), .up_ready(up_ready),
        .adr(adr), .dat_w(dat_w), .dat_r(dat_r), .sel(sel), .we(we),
        .cyc(cyc), .stb(stb), .ack(ack), .err(err), .rty(rty)
    );
endmodule
