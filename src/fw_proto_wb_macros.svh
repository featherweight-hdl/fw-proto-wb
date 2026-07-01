// ----------------------------------------------------------------------------
// fw_proto_wb_macros.svh
//
// Declare/connect macros for the physical Wishbone bus exposed by the
// fw-proto-wb transactor modules (wb_initiator_xtor / wb_target_xtor /
// wb_monitor_xtor) and the wb_proto_checker. Classic single-outstanding
// Wishbone (ACK/ERR, no rty) -- the same pin set every kit module presents:
//
//   adr, dat_w, dat_r, cyc, err, sel, stb, ack, we
//
// One macro pair per role keeps a module's port list, the bus wires that feed
// it, and the .pin(wire) connection list in agreement from a single source --
// e.g. the back-to-back tests instantiate initiator + target + monitor + checker
// on one bus, repeating the same 9-signal connect list four times by hand.
//
// File name follows the fwprotocol-defs convention (<unit>_macros.svh); the
// macros stay WB_-prefixed so they read the same as the Wishbone macros in
// fwprotocol-defs (verilog/rtl/wishbone_macros.svh) and can be used
// interchangeably. The two files define the same WB_* names, so include only
// ONE of them in a given compilation image.
//
// Scope: bus signals only. clock/reset are not part of the WB bundle -- the kit
// modules carry them as separate ports; connect them explicitly.
// ----------------------------------------------------------------------------
`ifndef INCLUDED_FW_PROTO_WB_MACROS_SVH
`define INCLUDED_FW_PROTO_WB_MACROS_SVH

// ----------------------------------------------------------------------------
// Port lists. PREFIX token-pastes onto each pin (e.g. m0_adr) so several buses
// can share a port namespace. No trailing comma -- these go inside ( ... ).
// ----------------------------------------------------------------------------

// Bus master view: drives the request, samples the response.
`define WB_INITIATOR_PORT(PREFIX, ADDR_WIDTH, DATA_WIDTH) \
    output [ADDR_WIDTH-1:0]      PREFIX``adr,   \
    output [DATA_WIDTH-1:0]      PREFIX``dat_w, \
    input  [DATA_WIDTH-1:0]      PREFIX``dat_r, \
    output                       PREFIX``cyc,   \
    input                        PREFIX``err,   \
    output [(DATA_WIDTH/8)-1:0]  PREFIX``sel,   \
    output                       PREFIX``stb,   \
    input                        PREFIX``ack,   \
    output                       PREFIX``we

// Bus slave view: exact inverse directions of INITIATOR.
`define WB_TARGET_PORT(PREFIX, ADDR_WIDTH, DATA_WIDTH) \
    input  [ADDR_WIDTH-1:0]      PREFIX``adr,   \
    input  [DATA_WIDTH-1:0]      PREFIX``dat_w, \
    output [DATA_WIDTH-1:0]      PREFIX``dat_r, \
    input                        PREFIX``cyc,   \
    output                       PREFIX``err,   \
    input  [(DATA_WIDTH/8)-1:0]  PREFIX``sel,   \
    input                        PREFIX``stb,   \
    output                       PREFIX``ack,   \
    input                        PREFIX``we

// Passive tap: all inputs (the monitor drives nothing).
`define WB_MONITOR_PORT(PREFIX, ADDR_WIDTH, DATA_WIDTH) \
    input  [ADDR_WIDTH-1:0]      PREFIX``adr,   \
    input  [DATA_WIDTH-1:0]      PREFIX``dat_w, \
    input  [DATA_WIDTH-1:0]      PREFIX``dat_r, \
    input                        PREFIX``cyc,   \
    input                        PREFIX``err,   \
    input  [(DATA_WIDTH/8)-1:0]  PREFIX``sel,   \
    input                        PREFIX``stb,   \
    input                        PREFIX``ack,   \
    input                        PREFIX``we

// ----------------------------------------------------------------------------
// Wires for one bus instance. Self-terminating: every line, including the last,
// ends with ';' -- the caller appends nothing.
// ----------------------------------------------------------------------------
`define WB_WIRES(PREFIX, ADDR_WIDTH, DATA_WIDTH) \
    wire [ADDR_WIDTH-1:0]        PREFIX``adr;   \
    wire [DATA_WIDTH-1:0]        PREFIX``dat_w; \
    wire [DATA_WIDTH-1:0]        PREFIX``dat_r; \
    wire                         PREFIX``cyc;   \
    wire                         PREFIX``err;   \
    wire [(DATA_WIDTH/8)-1:0]    PREFIX``sel;   \
    wire                         PREFIX``stb;   \
    wire                         PREFIX``ack;   \
    wire                         PREFIX``we;

// ----------------------------------------------------------------------------
// Named association list: .pin(wire) for an instantiation. P_PREFIX is the port
// side, W_PREFIX the wire side. No trailing comma.
// ----------------------------------------------------------------------------
`define WB_CONNECT(P_PREFIX, W_PREFIX) \
    .P_PREFIX``adr   (W_PREFIX``adr),   \
    .P_PREFIX``dat_w (W_PREFIX``dat_w), \
    .P_PREFIX``dat_r (W_PREFIX``dat_r), \
    .P_PREFIX``cyc   (W_PREFIX``cyc),   \
    .P_PREFIX``err   (W_PREFIX``err),   \
    .P_PREFIX``sel   (W_PREFIX``sel),   \
    .P_PREFIX``stb   (W_PREFIX``stb),   \
    .P_PREFIX``ack   (W_PREFIX``ack),   \
    .P_PREFIX``we    (W_PREFIX``we)

// ----------------------------------------------------------------------------
// Vector-bundle forms: model SIZE buses as one flattened packed vector
// ([SIZE*WIDTH-1:0]) since Verilog port lists can't carry interface arrays.
// INDEX*WIDTH +: WIDTH part-selects one bus out of the bundle.
// ----------------------------------------------------------------------------

`define WB_INITIATOR_PORT_ARR(PREFIX, ADDR_WIDTH, DATA_WIDTH, SIZE) \
    output [(SIZE*ADDR_WIDTH)-1:0]      PREFIX``adr,   \
    output [(SIZE*DATA_WIDTH)-1:0]      PREFIX``dat_w, \
    input  [(SIZE*DATA_WIDTH)-1:0]      PREFIX``dat_r, \
    output [SIZE-1:0]                   PREFIX``cyc,   \
    input  [SIZE-1:0]                   PREFIX``err,   \
    output [(SIZE*(DATA_WIDTH/8))-1:0]  PREFIX``sel,   \
    output [SIZE-1:0]                   PREFIX``stb,   \
    input  [SIZE-1:0]                   PREFIX``ack,   \
    output [SIZE-1:0]                   PREFIX``we

`define WB_TARGET_PORT_ARR(PREFIX, ADDR_WIDTH, DATA_WIDTH, SIZE) \
    input  [(SIZE*ADDR_WIDTH)-1:0]      PREFIX``adr,   \
    input  [(SIZE*DATA_WIDTH)-1:0]      PREFIX``dat_w, \
    output [(SIZE*DATA_WIDTH)-1:0]      PREFIX``dat_r, \
    input  [SIZE-1:0]                   PREFIX``cyc,   \
    output [SIZE-1:0]                   PREFIX``err,   \
    input  [(SIZE*(DATA_WIDTH/8))-1:0]  PREFIX``sel,   \
    input  [SIZE-1:0]                   PREFIX``stb,   \
    output [SIZE-1:0]                   PREFIX``ack,   \
    input  [SIZE-1:0]                   PREFIX``we

`define WB_MONITOR_PORT_ARR(PREFIX, ADDR_WIDTH, DATA_WIDTH, SIZE) \
    input  [(SIZE*ADDR_WIDTH)-1:0]      PREFIX``adr,   \
    input  [(SIZE*DATA_WIDTH)-1:0]      PREFIX``dat_w, \
    input  [(SIZE*DATA_WIDTH)-1:0]      PREFIX``dat_r, \
    input  [SIZE-1:0]                   PREFIX``cyc,   \
    input  [SIZE-1:0]                   PREFIX``err,   \
    input  [(SIZE*(DATA_WIDTH/8))-1:0]  PREFIX``sel,   \
    input  [SIZE-1:0]                   PREFIX``stb,   \
    input  [SIZE-1:0]                   PREFIX``ack,   \
    input  [SIZE-1:0]                   PREFIX``we

`define WB_WIRES_ARR(PREFIX, ADDR_WIDTH, DATA_WIDTH, SIZE) \
    wire [(SIZE*ADDR_WIDTH)-1:0]        PREFIX``adr;   \
    wire [(SIZE*DATA_WIDTH)-1:0]        PREFIX``dat_w; \
    wire [(SIZE*DATA_WIDTH)-1:0]        PREFIX``dat_r; \
    wire [SIZE-1:0]                     PREFIX``cyc;   \
    wire [SIZE-1:0]                     PREFIX``err;   \
    wire [(SIZE*(DATA_WIDTH/8))-1:0]    PREFIX``sel;   \
    wire [SIZE-1:0]                     PREFIX``stb;   \
    wire [SIZE-1:0]                     PREFIX``ack;   \
    wire [SIZE-1:0]                     PREFIX``we;

// Slice helper: PREFIX``FIELD[INDEX*WIDTH +: WIDTH]
`define WB_INDEX_ARR(PREFIX, FIELD, WIDTH, INDEX) \
    PREFIX``FIELD``[(INDEX)*(WIDTH)+:(WIDTH)]

// Connect one bus slice of a bundle to a scalar-port instance.
`define WB_CONNECT_ARR(P_PREFIX, W_PREFIX, INDEX, ADDR_WIDTH, DATA_WIDTH) \
    .P_PREFIX``adr   (W_PREFIX``adr[(INDEX)*(ADDR_WIDTH)+:(ADDR_WIDTH)]),         \
    .P_PREFIX``dat_w (W_PREFIX``dat_w[(INDEX)*(DATA_WIDTH)+:(DATA_WIDTH)]),       \
    .P_PREFIX``dat_r (W_PREFIX``dat_r[(INDEX)*(DATA_WIDTH)+:(DATA_WIDTH)]),       \
    .P_PREFIX``cyc   (W_PREFIX``cyc[INDEX]),                                      \
    .P_PREFIX``err   (W_PREFIX``err[INDEX]),                                      \
    .P_PREFIX``sel   (W_PREFIX``sel[(INDEX)*(DATA_WIDTH/8)+:(DATA_WIDTH/8)]),     \
    .P_PREFIX``stb   (W_PREFIX``stb[INDEX]),                                      \
    .P_PREFIX``ack   (W_PREFIX``ack[INDEX]),                                      \
    .P_PREFIX``we    (W_PREFIX``we[INDEX])

// ----------------------------------------------------------------------------
// Bundle <-> scalar-wire bridges (continuous assigns). Direction-aware: drive
// the master-sourced signals one way and the slave-sourced (dat_r/err/ack) the
// other, exactly as the bus does. Self-terminating.
//
//   ARR2WIRES: fan one bundle slice out to a scalar WB_WIRES set
//   WIRES2ARR: fan a scalar WB_WIRES set into one bundle slice
// ----------------------------------------------------------------------------
`define WB_ASSIGN_ARR2WIRES(W_PREFIX, A_PREFIX, INDEX, ADDR_WIDTH, DATA_WIDTH) \
    assign W_PREFIX``adr   = A_PREFIX``adr[(INDEX)*(ADDR_WIDTH)+:(ADDR_WIDTH)];     \
    assign W_PREFIX``dat_w = A_PREFIX``dat_w[(INDEX)*(DATA_WIDTH)+:(DATA_WIDTH)];   \
    assign A_PREFIX``dat_r[(INDEX)*(DATA_WIDTH)+:(DATA_WIDTH)] = W_PREFIX``dat_r;   \
    assign W_PREFIX``cyc   = A_PREFIX``cyc[INDEX];                                  \
    assign A_PREFIX``err[INDEX] = W_PREFIX``err;                                    \
    assign W_PREFIX``sel   = A_PREFIX``sel[(INDEX)*(DATA_WIDTH/8)+:(DATA_WIDTH/8)]; \
    assign W_PREFIX``stb   = A_PREFIX``stb[INDEX];                                  \
    assign A_PREFIX``ack[INDEX] = W_PREFIX``ack;                                    \
    assign W_PREFIX``we    = A_PREFIX``we[INDEX];

`define WB_ASSIGN_WIRES2ARR(A_PREFIX, W_PREFIX, INDEX, ADDR_WIDTH, DATA_WIDTH) \
    assign A_PREFIX``adr[(INDEX)*(ADDR_WIDTH)+:(ADDR_WIDTH)]   = W_PREFIX``adr;     \
    assign A_PREFIX``dat_w[(INDEX)*(DATA_WIDTH)+:(DATA_WIDTH)] = W_PREFIX``dat_w;   \
    assign W_PREFIX``dat_r = A_PREFIX``dat_r[(INDEX)*(DATA_WIDTH)+:(DATA_WIDTH)];   \
    assign A_PREFIX``cyc[INDEX]   = W_PREFIX``cyc;                                  \
    assign W_PREFIX``err = A_PREFIX``err[INDEX];                                    \
    assign A_PREFIX``sel[(INDEX)*(DATA_WIDTH/8)+:(DATA_WIDTH/8)] = W_PREFIX``sel;   \
    assign A_PREFIX``stb[INDEX]   = W_PREFIX``stb;                                  \
    assign W_PREFIX``ack = A_PREFIX``ack[INDEX];                                    \
    assign A_PREFIX``we[INDEX]    = W_PREFIX``we;

`endif /* INCLUDED_FW_PROTO_WB_MACROS_SVH */
