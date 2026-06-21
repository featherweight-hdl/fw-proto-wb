// Monitor transactor-interface: ready/valid CONSUMER on the internal link, with a
// receive FIFO. get() is a BLOCKING task the monitor bridge calls; the bridge then
// fans the phase out through the (non-blocking) monitor API. Same shape as the rv
// monitor interface. Deeper than the data path: a passive monitor cannot
// backpressure the bus, so size the FIFO to absorb bursts while the bridge drains.
interface wb_monitor_xtor_if
    import wb_types_pkg::*;
(
    input               clock,
    input               reset,
    input  wb_xfer_t    up_data,
    input               up_valid,
    output bit          up_ready
);
    localparam int unsigned DEPTH = 8;
    wb_xfer_t fifo[$];                 // observed-phase queue

    // Caller side (monitor bridge): pop the next observed phase; block if empty.
    task automatic get(output wb_xfer_t x);
        while (fifo.size() == 0) @(posedge clock);
        x = fifo.pop_front();
    endtask

    // Fill side: capture link beats into the FIFO; assert up_ready when room.
    always @(posedge clock) begin
        if (reset) begin
            up_ready <= 1'b0;
        end else begin
            if (up_valid && up_ready)
                fifo.push_back(up_data);
            up_ready <= (fifo.size() < DEPTH);
        end
    end
endinterface
