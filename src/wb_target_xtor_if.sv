// ----------------------------------------------------------------------------
// Wishbone Target transactor interface (SV, signal-level RV ports)
//
// Hand-coded in-built FIFOs bridge the blocking task API (HVL side) to the
// ready/valid request/response channels of the core:
//   - egress  FIFO : wait_req()/get_req() pop  <- captures (req_dat, req_valid)
//   - ingress FIFO : send_rsp()/put_rsp() push -> drives  (rsp_dat, rsp_valid)
//
// Migrated from fwvip-wb. Task ports use the per-instance ADDR_WIDTH/DATA_WIDTH.
// ----------------------------------------------------------------------------
interface wb_target_xtor_if #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int REQ_WIDTH  = (ADDR_WIDTH + DATA_WIDTH + (DATA_WIDTH/8) + 1),
        parameter int RSP_WIDTH  = (DATA_WIDTH + 1),
        parameter int DEPTH      = 4
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // RV request channel: core sources, interface accepts
        input  wire [REQ_WIDTH-1:0]     req_dat,
        input  wire                     req_valid,
        output wire                     req_ready,

        // RV response channel: interface sources, core accepts
        output wire [RSP_WIDTH-1:0]     rsp_dat,
        output wire                     rsp_valid,
        input  wire                     rsp_ready
    );

    typedef struct packed {
        bit [ADDR_WIDTH-1:0]      adr;
        bit [DATA_WIDTH-1:0]      dat;
        bit                       we;
        bit [(DATA_WIDTH/8)-1:0]  sel;
    } req_s;

    typedef struct packed {
        bit [DATA_WIDTH-1:0]      dat;
        bit                       err;
    } rsp_s;

    // --------------------------------------------------------------------
    // Egress FIFO : request stream captured from the core
    // --------------------------------------------------------------------
    localparam int REQ_PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    logic [REQ_WIDTH-1:0] req_mem [0:DEPTH-1];
    logic [REQ_PTR_W-1:0] req_wr, req_rd;
    int unsigned          req_cnt;
    logic                 req_get_req, req_get_gnt;
    logic [REQ_WIDTH-1:0] req_get_dat;

    assign req_ready = (req_cnt < DEPTH);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            req_wr      <= '0;
            req_rd      <= '0;
            req_cnt     <= 0;
            req_get_gnt <= 1'b0;
            req_get_dat <= '0;
        end else begin
            automatic logic do_push = (req_valid && req_ready);
            automatic logic do_pop  = (req_get_req && !req_get_gnt && (req_cnt != 0));
            req_get_gnt <= 1'b0;
            if (do_push) begin
                req_mem[req_wr] <= req_dat;
                req_wr <= (req_wr == REQ_PTR_W'(DEPTH-1)) ? '0 : req_wr + 1'b1;
            end
            if (do_pop) begin
                req_get_dat <= req_mem[req_rd];
                req_rd      <= (req_rd == REQ_PTR_W'(DEPTH-1)) ? '0 : req_rd + 1'b1;
                req_get_gnt <= 1'b1;
            end
            case ({do_push, do_pop})
                2'b10:   req_cnt <= req_cnt + 1;
                2'b01:   req_cnt <= req_cnt - 1;
                default: req_cnt <= req_cnt;
            endcase
        end
    end

    // --------------------------------------------------------------------
    // Ingress FIFO : response stream driven into the core
    // --------------------------------------------------------------------
    localparam int RSP_PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    logic [RSP_WIDTH-1:0] rsp_mem [0:DEPTH-1];
    logic [RSP_PTR_W-1:0] rsp_wr, rsp_rd;
    int unsigned          rsp_cnt;
    logic                 rsp_put_req, rsp_put_gnt;
    logic [RSP_WIDTH-1:0] rsp_put_dat;

    assign rsp_valid = (rsp_cnt != 0);
    assign rsp_dat   = rsp_mem[rsp_rd];

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            rsp_wr      <= '0;
            rsp_rd      <= '0;
            rsp_cnt     <= 0;
            rsp_put_gnt <= 1'b0;
        end else begin
            automatic logic do_push = (rsp_put_req && !rsp_put_gnt && (rsp_cnt < DEPTH));
            automatic logic do_pop  = (rsp_valid && rsp_ready);
            rsp_put_gnt <= 1'b0;
            if (do_push) begin
                rsp_mem[rsp_wr] <= rsp_put_dat;
                rsp_wr      <= (rsp_wr == RSP_PTR_W'(DEPTH-1)) ? '0 : rsp_wr + 1'b1;
                rsp_put_gnt <= 1'b1;
            end
            if (do_pop) begin
                rsp_rd <= (rsp_rd == RSP_PTR_W'(DEPTH-1)) ? '0 : rsp_rd + 1'b1;
            end
            case ({do_push, do_pop})
                2'b10:   rsp_cnt <= rsp_cnt + 1;
                2'b01:   rsp_cnt <= rsp_cnt - 1;
                default: rsp_cnt <= rsp_cnt;
            endcase
        end
    end

    initial begin
        req_get_req = 1'b0;
        rsp_put_req = 1'b0;
        rsp_put_dat = '0;
    end

    // --------------------------------------------------------------------
    // Task API
    // --------------------------------------------------------------------
    task wait_reset();
        if (reset) @(negedge reset);
        @(posedge clock);
    endtask

    // Blocking pop of a raw request vector
    task automatic get_req(output [REQ_WIDTH-1:0] val);
        req_get_req = 1'b1;
        do @(posedge clock); while (!req_get_gnt);
        val = req_get_dat;
        req_get_req = 1'b0;
    endtask

    // Blocking push of a raw response vector
    task automatic put_rsp(input [RSP_WIDTH-1:0] val);
        rsp_put_dat = val;
        rsp_put_req = 1'b1;
        do @(posedge clock); while (!rsp_put_gnt);
        rsp_put_req = 1'b0;
    endtask

    // Wait for the next observed Wishbone request
    task automatic wait_req(
            output [ADDR_WIDTH-1:0]     adr,
            output [DATA_WIDTH-1:0]     dat,
            output [(DATA_WIDTH/8)-1:0] sel,
            output                      we);
        req_s r;
        get_req(r);
        adr = r.adr;
        dat = r.dat;
        sel = r.sel;
        we  = r.we;
    endtask

    // Provide a response for the outstanding request
    task automatic send_rsp(
            input [DATA_WIDTH-1:0]      dat,
            input                       err);
        rsp_s r;
        r = '{dat: dat, err: err};
        put_rsp(r);
    endtask

endinterface
