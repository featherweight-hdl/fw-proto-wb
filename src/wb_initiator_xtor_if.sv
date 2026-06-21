// Initiator transactor-interface: the caller-facing endpoint of the master.
// It owns TWO plain ready/valid links to the core (design-rule 2): a REQUEST link
// it PRODUCES (iface -> core) and a RESPONSE link it CONSUMES (core -> iface).
// xfer() pushes one request and blocks for the matching response.
//
// Classic Wishbone is single-outstanding on the wire, so xfer() serializes one
// transaction at a time (a `busy` gate). That is semantically exact for classic
// WB; registered-feedback bursts (design O-2) would relax this with a deeper
// outstanding count + response ticketing. Both link endpoints are CLOCKED -- a
// combinational drive into a core input port would be lost to a delta race.
interface wb_initiator_xtor_if
    import wb_types_pkg::*;
(
    input               clock,
    input               reset,
    // request link: iface -> core (ready/valid)
    output wb_req_t     req_data,
    output bit          req_valid,
    input               req_ready,
    // response link: core -> iface (ready/valid)
    input  wb_rsp_t     rsp_data,
    input               rsp_valid,
    output bit          rsp_ready
);
    wb_req_t req_q[$];                 // pending request (depth 1 in classic use)
    wb_rsp_t rsp_q[$];                 // returned response
    bit      busy;                     // one outstanding transaction at a time

    // Caller side: issue one transfer; block until its response returns.
    task automatic xfer(output wb_rsp_t rsp, input wb_req_t req);
        while (busy) @(posedge clock);             // serialize (classic = 1 outst.)
        busy = 1'b1;
        req_q.push_back(req);                       // hand request to the drain
        while (rsp_q.size() == 0) @(posedge clock); // await the response
        rsp  = rsp_q.pop_front();
        busy = 1'b0;
    endtask

    // Drain side: present the pending request on the request link; pop on accept.
    always @(posedge clock) begin
        if (reset) begin
            req_valid <= 1'b0;
            req_data  <= '0;
        end else begin
            if (req_valid && req_ready)
                void'(req_q.pop_front());           // accepted request leaves
            if (req_q.size() != 0) begin
                req_valid <= 1'b1;
                req_data  <= req_q[0];
            end else begin
                req_valid <= 1'b0;
            end
        end
    end

    // Fill side: capture response-link beats into rsp_q; ready whenever empty.
    always @(posedge clock) begin
        if (reset) begin
            rsp_ready <= 1'b0;
        end else begin
            if (rsp_valid && rsp_ready)
                rsp_q.push_back(rsp_data);          // captured response enters
            rsp_ready <= (rsp_q.size() == 0);       // room for exactly one
        end
    end
endinterface
