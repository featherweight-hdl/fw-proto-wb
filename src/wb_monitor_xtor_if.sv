// ----------------------------------------------------------------------------
// Wishbone Monitor transactor interface (SV, signal-level RV ports)
//
// Hand-coded in-built egress FIFO bridges the core's observed-transaction
// stream to the blocking task API (HVL side):
//   - egress FIFO : wait_txn()/get_txn() pop <- captures (mon_dat, mon_valid)
//
// Migrated from fwvip-wb. Parameterized by ADDR_WIDTH/DATA_WIDTH (D7); the
// task ports use the per-instance widths.
// ----------------------------------------------------------------------------
interface wb_monitor_xtor_if #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int MON_WIDTH  = (ADDR_WIDTH + DATA_WIDTH + (DATA_WIDTH/8) + 1 + 1),
        parameter int DEPTH      = 4
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // RV egress channel: core sources observed transactions, interface accepts
        input  wire [MON_WIDTH-1:0]     mon_dat,
        input  wire                     mon_valid,
        output wire                     mon_ready
    );

    typedef struct packed {
        bit [ADDR_WIDTH-1:0]      adr;
        bit [DATA_WIDTH-1:0]      dat;
        bit                       we;
        bit [(DATA_WIDTH/8)-1:0]  sel;
        bit                       err;
    } mon_s;

    // --------------------------------------------------------------------
    // Egress FIFO : observed-transaction stream captured from the core
    // --------------------------------------------------------------------
    localparam int MON_PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    logic [MON_WIDTH-1:0] mon_mem [0:DEPTH-1];
    logic [MON_PTR_W-1:0] mon_wr, mon_rd;
    int unsigned          mon_cnt;
    logic                 mon_get_req, mon_get_gnt;
    logic [MON_WIDTH-1:0] mon_get_dat;

    assign mon_ready = (mon_cnt < DEPTH);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            mon_wr      <= '0;
            mon_rd      <= '0;
            mon_cnt     <= 0;
            mon_get_gnt <= 1'b0;
            mon_get_dat <= '0;
        end else begin
            automatic logic do_push = (mon_valid && mon_ready);
            automatic logic do_pop  = (mon_get_req && !mon_get_gnt && (mon_cnt != 0));
            mon_get_gnt <= 1'b0;
            if (do_push) begin
                mon_mem[mon_wr] <= mon_dat;
                mon_wr <= (mon_wr == MON_PTR_W'(DEPTH-1)) ? '0 : mon_wr + 1'b1;
            end
            if (do_pop) begin
                mon_get_dat <= mon_mem[mon_rd];
                mon_rd      <= (mon_rd == MON_PTR_W'(DEPTH-1)) ? '0 : mon_rd + 1'b1;
                mon_get_gnt <= 1'b1;
            end
            case ({do_push, do_pop})
                2'b10:   mon_cnt <= mon_cnt + 1;
                2'b01:   mon_cnt <= mon_cnt - 1;
                default: mon_cnt <= mon_cnt;
            endcase
        end
    end

    initial begin
        mon_get_req = 1'b0;
    end

    // --------------------------------------------------------------------
    // Task API
    // --------------------------------------------------------------------
    task wait_reset();
        if (reset) @(negedge reset);
        @(posedge clock);
    endtask

    // Blocking pop of a raw observed-transaction vector
    task automatic get_txn(output [MON_WIDTH-1:0] val);
        mon_get_req = 1'b1;
        do @(posedge clock); while (!mon_get_gnt);
        val = mon_get_dat;
        mon_get_req = 1'b0;
    endtask

    // Wait for the next observed Wishbone transaction
    task automatic wait_txn(
            output [ADDR_WIDTH-1:0]     adr,
            output [DATA_WIDTH-1:0]     dat,
            output [(DATA_WIDTH/8)-1:0] sel,
            output                      we,
            output                      err);
        mon_s r;
        get_txn(r);
        adr = r.adr;
        dat = r.dat;
        sel = r.sel;
        we  = r.we;
        err = r.err;
    endtask

endinterface
