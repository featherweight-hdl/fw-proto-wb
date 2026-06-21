// Initiator core: a clocked Wishbone MASTER FSM. It is a CONSUMER on the request
// link, a PRODUCER on the response link, and the master on the bus pins. Per
// accepted request it runs one classic cycle: assert CYC/STB, drive the qualified
// signals (held stable until terminated, RULE 3.60), wait for ACK|ERR|RTY, then
// capture DAT_I + flags into a response beat and drop STB (and CYC unless the
// request asked to hold it for a block/RMW chain). Clocked + queue-free, so yosys
// can reason about it in the back-to-back proof.
module wb_initiator_xtor_core
    import wb_types_pkg::*;
(
    input            clock,
    input            reset,
    // request link (from xtor_if): ready/valid CONSUMER
    input  wb_req_t  req_data,
    input            req_valid,
    output bit       req_ready,
    // response link (to xtor_if): ready/valid PRODUCER
    output wb_rsp_t  rsp_data,
    output bit       rsp_valid,
    input            rsp_ready,
    // Wishbone MASTER pins
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
    typedef enum bit [1:0] {WB_IDLE, WB_ACTIVE, WB_RESP} state_t;
    state_t st;
    bit     hold;                       // remembered cyc_hold for this cycle

    always @(posedge clock) begin
        if (reset) begin
            st        <= WB_IDLE;
            req_ready <= 1'b1;
            rsp_valid <= 1'b0;
            rsp_data  <= '0;
            adr_o     <= '0;
            dat_o     <= '0;
            sel_o     <= '0;
            we_o      <= 1'b0;
            cyc_o     <= 1'b0;          // RULE 3.20: CYC/STB negated under reset
            stb_o     <= 1'b0;
            hold      <= 1'b0;
        end else case (st)
            WB_IDLE:
                if (req_valid && req_ready) begin   // request-link transfer
                    adr_o     <= req_data.adr;
                    dat_o     <= req_data.dat;
                    sel_o     <= req_data.sel;
                    we_o      <= req_data.we;
                    cyc_o     <= 1'b1;
                    stb_o     <= 1'b1;
                    hold      <= req_data.cyc_hold;
                    req_ready <= 1'b0;
                    st        <= WB_ACTIVE;
                end

            WB_ACTIVE:
                if (ack_i || err_i || rty_i) begin  // bus phase terminated
                    rsp_data.dat <= dat_i;
                    rsp_data.err <= err_i;
                    rsp_data.rty <= rty_i;
                    rsp_valid    <= 1'b1;
                    stb_o        <= 1'b0;
                    cyc_o        <= hold;           // hold CYC for block/RMW chain
                    st           <= WB_RESP;
                end

            WB_RESP:
                if (rsp_valid && rsp_ready) begin   // response-link transfer
                    rsp_valid <= 1'b0;
                    req_ready <= 1'b1;
                    st        <= WB_IDLE;
                end

            default: st <= WB_IDLE;
        endcase
    end
endmodule
