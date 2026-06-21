// Monitor core: a clocked FSM that WATCHES the bus (every signal is an input -- it
// drives nothing) and, on each completed phase (CYC_I && STB_I && (ACK|ERR|RTY)),
// assembles a wb_xfer_t (request + response sampled at the termination edge) and
// pushes it onto the internal ready/valid link. 1-deep skid like the rv monitor;
// a zero-drop monitor at full bus rate would need a deeper capture path (O-6).
// Two separate data taps: dat_w is the master's write data (DAT_O), dat_r is the
// slave's read data (its DAT_O) -- Wishbone's two unidirectional data buses.
module wb_monitor_xtor_core
    import wb_types_pkg::*;
(
    input            clock,
    input            reset,
    // ready/valid link to the xtor_if (PRODUCER)
    output wb_xfer_t up_data,
    output bit       up_valid,
    input            up_ready,
    // Wishbone bus taps (observed, never driven)
    input  [WB_AW-1:0] adr,
    input  [WB_DW-1:0] dat_w,           // master write data (DAT master->slave)
    input  [WB_DW-1:0] dat_r,           // slave  read  data (DAT slave->master)
    input  [WB_SW-1:0] sel,
    input              we,
    input              cyc,
    input              stb,
    input              ack,
    input              err,
    input              rty
);
    typedef enum bit [0:0] {WB_WATCH, WB_PRESENT} state_t;
    state_t st;

    always @(posedge clock) begin
        if (reset) begin
            st       <= WB_WATCH;
            up_valid <= 1'b0;
            up_data  <= '0;
        end else case (st)
            WB_WATCH:
                if (cyc && stb && (ack || err || rty)) begin   // completed phase
                    up_data.req.adr      <= adr;
                    up_data.req.dat      <= dat_w;
                    up_data.req.sel      <= sel;
                    up_data.req.we       <= we;
                    up_data.req.cyc_hold <= 1'b0;
                    up_data.rsp.dat      <= dat_r;
                    up_data.rsp.err      <= err;
                    up_data.rsp.rty      <= rty;
                    up_valid             <= 1'b1;
                    st                   <= WB_PRESENT;
                end

            WB_PRESENT:
                if (up_valid && up_ready) begin                // link transfer
                    up_valid <= 1'b0;
                    st       <= WB_WATCH;
                end

            default: st <= WB_WATCH;
        endcase
    end
endmodule
