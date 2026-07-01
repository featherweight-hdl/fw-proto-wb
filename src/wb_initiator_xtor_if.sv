// ----------------------------------------------------------------------------
// Wishbone Initiator transactor interface (SV, signal-level RV ports)
//
// Hand-coded in-built FIFOs bridge the blocking task API (HVL side) to the
// ready/valid request/response channels of the core:
//   - ingress FIFO : request()/put()  push -> drives (req_dat, req_valid)
//   - egress  FIFO : response()/get()  pop  <- captures (rsp_dat, rsp_valid)
//
// Migrated from fwvip-wb. Task ports use the per-instance ADDR_WIDTH/DATA_WIDTH
// (the kit carries no shared *_WIDTH_MAX; non-parameterized consumers own that).
// ----------------------------------------------------------------------------
interface wb_initiator_xtor_if #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int REQ_WIDTH  = (ADDR_WIDTH + DATA_WIDTH + (DATA_WIDTH/8) + 1),
        parameter int RSP_WIDTH  = (DATA_WIDTH + 1),
        parameter int DEPTH      = 4
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // RV request channel: interface sources, core accepts
        output wire [REQ_WIDTH-1:0]     req_dat,
        output wire                     req_valid,
        input  wire                     req_ready,

        // RV response channel: core sources, interface accepts
        input  wire [RSP_WIDTH-1:0]     rsp_dat,
        input  wire                     rsp_valid,
        output wire                     rsp_ready
    );

    typedef struct packed {
        bit [ADDR_WIDTH-1:0]      adr;
        bit [DATA_WIDTH-1:0]      dat;
        bit                       we;
        bit [(DATA_WIDTH/8)-1:0]  stb;
    } req_s;

    typedef struct packed {
        bit [DATA_WIDTH-1:0]      dat;
        bit                       err;
    } rsp_s;

    // --------------------------------------------------------------------
    // Ingress FIFO : request stream into the core
    // --------------------------------------------------------------------
    localparam int REQ_PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    logic [REQ_WIDTH-1:0] req_mem [0:DEPTH-1];
    logic [REQ_PTR_W-1:0] req_wr, req_rd;
    int unsigned          req_cnt;
    logic                 req_put_req, req_put_gnt;
    logic [REQ_WIDTH-1:0] req_put_dat;

    assign req_valid = (req_cnt != 0);
    assign req_dat   = req_mem[req_rd];

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            req_wr      <= '0;
            req_rd      <= '0;
            req_cnt     <= 0;
            req_put_gnt <= 1'b0;
        end else begin
            automatic logic do_push = (req_put_req && !req_put_gnt && (req_cnt < DEPTH));
            automatic logic do_pop  = (req_valid && req_ready);
            req_put_gnt <= 1'b0;
            if (do_push) begin
                req_mem[req_wr] <= req_put_dat;
                req_wr      <= (req_wr == REQ_PTR_W'(DEPTH-1)) ? '0 : req_wr + 1'b1;
                req_put_gnt <= 1'b1;
            end
            if (do_pop) begin
                req_rd <= (req_rd == REQ_PTR_W'(DEPTH-1)) ? '0 : req_rd + 1'b1;
            end
            case ({do_push, do_pop})
                2'b10:   req_cnt <= req_cnt + 1;
                2'b01:   req_cnt <= req_cnt - 1;
                default: req_cnt <= req_cnt;
            endcase
        end
    end

    // --------------------------------------------------------------------
    // Egress FIFO : response stream out of the core
    // --------------------------------------------------------------------
    localparam int RSP_PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    logic [RSP_WIDTH-1:0] rsp_mem [0:DEPTH-1];
    logic [RSP_PTR_W-1:0] rsp_wr, rsp_rd;
    int unsigned          rsp_cnt;
    logic                 rsp_get_req, rsp_get_gnt;
    logic [RSP_WIDTH-1:0] rsp_get_dat;

    assign rsp_ready = (rsp_cnt < DEPTH);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            rsp_wr      <= '0;
            rsp_rd      <= '0;
            rsp_cnt     <= 0;
            rsp_get_gnt <= 1'b0;
            rsp_get_dat <= '0;
        end else begin
            automatic logic do_push = (rsp_valid && rsp_ready);
            automatic logic do_pop  = (rsp_get_req && !rsp_get_gnt && (rsp_cnt != 0));
            rsp_get_gnt <= 1'b0;
            if (do_push) begin
                rsp_mem[rsp_wr] <= rsp_dat;
                rsp_wr <= (rsp_wr == RSP_PTR_W'(DEPTH-1)) ? '0 : rsp_wr + 1'b1;
            end
            if (do_pop) begin
                rsp_get_dat <= rsp_mem[rsp_rd];
                rsp_rd      <= (rsp_rd == RSP_PTR_W'(DEPTH-1)) ? '0 : rsp_rd + 1'b1;
                rsp_get_gnt <= 1'b1;
            end
            case ({do_push, do_pop})
                2'b10:   rsp_cnt <= rsp_cnt + 1;
                2'b01:   rsp_cnt <= rsp_cnt - 1;
                default: rsp_cnt <= rsp_cnt;
            endcase
        end
    end

    initial begin
        req_put_req = 1'b0;
        req_put_dat = '0;
        rsp_get_req = 1'b0;
    end

    // --------------------------------------------------------------------
    // Task API
    // --------------------------------------------------------------------

    // Blocking push of a raw request vector
    task automatic put(input [REQ_WIDTH-1:0] val);
        req_put_dat = val;
        req_put_req = 1'b1;
        do @(posedge clock); while (!req_put_gnt);
        req_put_req = 1'b0;
    endtask

    // Blocking pop of a raw response vector
    task automatic get(output [RSP_WIDTH-1:0] val);
        rsp_get_req = 1'b1;
        do @(posedge clock); while (!rsp_get_gnt);
        val = rsp_get_dat;
        rsp_get_req = 1'b0;
    endtask

    // Queue a Wishbone request
    task automatic request(
            input [ADDR_WIDTH-1:0]      adr,
            input [DATA_WIDTH-1:0]      dat,
            input [(DATA_WIDTH/8)-1:0]  sel,
            input                       we);
        req_s r;
        r = '{adr: adr, dat: dat, we: we, stb: sel};
        put(r);
    endtask

    // Wait for the matching response
    task automatic response(
            output [DATA_WIDTH-1:0]     dat,
            output                      err);
        rsp_s r;
        get(r);
        dat = r.dat;
        err = r.err;
    endtask

endinterface
