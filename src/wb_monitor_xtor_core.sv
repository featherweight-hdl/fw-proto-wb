// ----------------------------------------------------------------------------
// Wishbone bus monitor core transactor (pure module, signal-level ports)
//
//   - Passively observes the Wishbone signals
//   - Emits one RV transaction per completed access on the egress channel
//   mon_* : RV initiator port (core -> FIFO)  { adr, dat, we, sel, err }
//
// Migrated from fwvip-wb (authoritative transactor API). ack/err only.
// ----------------------------------------------------------------------------
module wb_monitor_xtor_core #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int MON_WIDTH  = (ADDR_WIDTH + DATA_WIDTH + (DATA_WIDTH/8) + 1 + 1)
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // Wishbone (protocol) signals -- passively observed
        input  wire [ADDR_WIDTH-1:0]    adr,
        input  wire [DATA_WIDTH-1:0]    dat_w,
        input  wire [DATA_WIDTH-1:0]    dat_r,
        input  wire                     cyc,
        input  wire                     err,
        input  wire [DATA_WIDTH/8-1:0]  sel,
        input  wire                     stb,
        input  wire                     ack,
        input  wire                     we,

        // RV egress channel of observed transactions (core drives)
        output wire [MON_WIDTH-1:0]     mon_dat,
        output wire                     mon_valid,
        input  wire                     mon_ready
    );

    typedef struct packed {
        bit [ADDR_WIDTH-1:0]      adr;
        bit [DATA_WIDTH-1:0]      dat;   // write data on WE=1, read data on WE=0
        bit                       we;
        bit [(DATA_WIDTH/8)-1:0]  sel;
        bit                       err;
    } mon_s;

    reg        mon_valid_r;
    assign mon_valid = mon_valid_r;

    mon_s      mon_q;
    assign mon_dat = mon_q;

    // Termination of a bus cycle
    wire term     = (ack || err) && cyc && stb;
    wire mon_fire = mon_valid && mon_ready;

    // Single-entry buffer
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            mon_valid_r <= 1'b0;
            mon_q       <= '0;
        end else begin
            // Consume when downstream ready
            if (mon_fire) begin
                mon_valid_r <= 1'b0;
            end

            // Produce on termination if buffer empty (or consumed same cycle)
            if (term && (!mon_valid_r || mon_fire)) begin
                mon_q.adr   <= adr;
                mon_q.dat   <= we ? dat_w : dat_r;
                mon_q.we    <= we;
                mon_q.sel   <= sel;
                mon_q.err   <= err;
                mon_valid_r <= 1'b1;
            end
        end
    end

endmodule
