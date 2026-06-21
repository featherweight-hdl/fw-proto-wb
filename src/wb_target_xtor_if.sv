// Target transactor-interface: the model-facing endpoint of the slave. It owns
// TWO plain ready/valid links to the core (the mirror of the initiator): a
// REQUEST link it CONSUMES (core -> iface, captured bus requests) and a RESPONSE
// link it PRODUCES (iface -> core, responses to drive on the bus). recv_req()
// pops a captured request; send_rsp() hands back the response. Both endpoints
// clocked; single-outstanding by the bridge's recv/access/send loop.
interface wb_target_xtor_if
    import wb_types_pkg::*;
(
    input               clock,
    input               reset,
    // request link: core -> iface (ready/valid)
    input  wb_req_t     req_data,
    input               req_valid,
    output bit          req_ready,
    // response link: iface -> core (ready/valid)
    output wb_rsp_t     rsp_data,
    output bit          rsp_valid,
    input               rsp_ready
);
    wb_req_t req_q[$];                 // captured requests (fill pushes, caller pops)
    wb_rsp_t rsp_q[$];                 // responses to drive (caller pushes, drain pops)

    // Caller side: pop the next captured request; block while none captured.
    task automatic recv_req(output wb_req_t req);
        while (req_q.size() == 0) @(posedge clock);
        req = req_q.pop_front();
    endtask

    // Caller side: hand back a response; block while the drain is still busy.
    task automatic send_rsp(input wb_rsp_t rsp);
        while (rsp_q.size() != 0) @(posedge clock);   // depth 1: one in flight
        rsp_q.push_back(rsp);
    endtask

    // Fill side: capture request-link beats into req_q; ready whenever empty.
    always @(posedge clock) begin
        if (reset) begin
            req_ready <= 1'b0;
        end else begin
            if (req_valid && req_ready)
                req_q.push_back(req_data);
            req_ready <= (req_q.size() == 0);
        end
    end

    // Drain side: present the pending response on the response link; pop on accept.
    always @(posedge clock) begin
        if (reset) begin
            rsp_valid <= 1'b0;
            rsp_data  <= '0;
        end else begin
            if (rsp_valid && rsp_ready)
                void'(rsp_q.pop_front());
            if (rsp_q.size() != 0) begin
                rsp_valid <= 1'b1;
                rsp_data  <= rsp_q[0];
            end else begin
                rsp_valid <= 1'b0;
            end
        end
    end
endinterface
