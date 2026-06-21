`ifndef INCLUDED_WB_PROTO_MACROS_SVH
`define INCLUDED_WB_PROTO_MACROS_SVH

// ----------------------------------------------------------------------
// Implementation-template macros shipped by the wb APIs. EVERY API ships one,
// and any implementation of that API MUST use it to define the implementation
// redirect rather than hand-rolling the fw_export proxy.
//
// Parameter order follows the fw-api-kit convention: OUTPUTS (returns) lead, so
// a transfer is `xfer(output RSP rsp, input REQ req)` -- read "rsp = xfer(req)".
//
// `FW_WB_INITIATOR_IMP(REQ, RSP, IMP, NAME) -- export member NAME whose
//   xfer(rsp,req) redirects to IMP's NAME``_xfer(rsp,req).
// `FW_WB_TARGET_IMP(REQ, RSP, IMP, NAME)    -- export member NAME whose
//   access(rsp,req) redirects to IMP's NAME``_access(rsp,req).
// `FW_WB_MONITOR_IMP(XFER, IMP, NAME)       -- export member NAME whose
//   observe(xfer) redirects to IMP's NAME``_observe(xfer). observe() is a
//   FUNCTION (non-blocking) -- monitor APIs may not block.
// Each macro call needs a trailing `;`.
// ----------------------------------------------------------------------
`define FW_WB_INITIATOR_IMP(REQ, RSP, IMP, NAME) \
    class NAME``_imp_t extends fw_export #(wb_initiator_if #(REQ, RSP)) \
            implements wb_initiator_if #(REQ, RSP); \
        local IMP m_imp; \
        function new(IMP imp); \
            super.new(`"NAME`", imp, this); \
            m_imp = imp; \
        endfunction \
        virtual task xfer(output RSP rsp, input REQ req); \
            m_imp.NAME``_xfer(rsp, req); \
        endtask \
    endclass \
    NAME``_imp_t NAME

`define FW_WB_TARGET_IMP(REQ, RSP, IMP, NAME) \
    class NAME``_imp_t extends fw_export #(wb_target_if #(REQ, RSP)) \
            implements wb_target_if #(REQ, RSP); \
        local IMP m_imp; \
        function new(IMP imp); \
            super.new(`"NAME`", imp, this); \
            m_imp = imp; \
        endfunction \
        virtual task access(output RSP rsp, input REQ req); \
            m_imp.NAME``_access(rsp, req); \
        endtask \
    endclass \
    NAME``_imp_t NAME

`define FW_WB_MONITOR_IMP(XFER, IMP, NAME) \
    class NAME``_imp_t extends fw_export #(wb_monitor_if #(XFER)) \
            implements wb_monitor_if #(XFER); \
        local IMP m_imp; \
        function new(IMP imp); \
            super.new(`"NAME`", imp, this); \
            m_imp = imp; \
        endfunction \
        virtual function void observe(input XFER xfer); \
            m_imp.NAME``_observe(xfer); \
        endfunction \
    endclass \
    NAME``_imp_t NAME

// `FW_STD_MEM_IMP(ADDR, DATA, STRB, IMP, NAME) -- export member NAME providing
//   std_mem_if. write(...) redirects to IMP's NAME``_write(...) and read(...) to
//   NAME``_read(...). Outputs-first arg order in both redirects.
`define FW_STD_MEM_IMP(ADDR, DATA, STRB, IMP, NAME) \
    class NAME``_imp_t extends fw_export #(std_mem_if #(ADDR, DATA, STRB)) \
            implements std_mem_if #(ADDR, DATA, STRB); \
        local IMP m_imp; \
        function new(IMP imp); \
            super.new(`"NAME`", imp, this); \
            m_imp = imp; \
        endfunction \
        virtual task write(output bit err, input ADDR addr, input DATA data, \
                           input STRB strb); \
            m_imp.NAME``_write(err, addr, data, strb); \
        endtask \
        virtual task read(output DATA data, output bit err, input ADDR addr); \
            m_imp.NAME``_read(data, err, addr); \
        endtask \
    endclass \
    NAME``_imp_t NAME

`endif /* INCLUDED_WB_PROTO_MACROS_SVH */
