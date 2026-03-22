/*
 * Copyright (c) 2026 Can Joshua Lehmann
 * SPDX-License-Identifier: Apache-2.0
 * Based on the Tiny Tapeout Template
 */

`default_nettype none

module LUT #(
  parameter N = 2
) (
  input clock,
  input rst_n,
  input [N - 1 : 0] in,
  output out,
  input virtual_reset,
  input [2 ** N + 1 - 1 : 0] conf
);

  wire reg_conf = conf[0];
  wire [2 ** N - 1 : 0] lut_conf = conf[1 +: 2 ** N];

  wire lut_out = lut_conf[in];

  reg register;

  always @(posedge clock)
    if (!rst_n)
      register <= 0;
    else
      if (virtual_reset)
        register <= 0;
      else
        register <= lut_out;

  assign out = virtual_reset ? 0
             : reg_conf ? register
             : lut_out;

endmodule

module Pool #(
  parameter LUTS = 4,
  parameter PORTS_IN = 2,
  parameter PORTS_OUT = 2,
  parameter N = 2
) (
  input clock,
  input rst_n,
  input [PORTS_IN - 1 : 0] ports_in,
  output [PORTS_OUT - 1 : 0] ports_out,
  input virtual_reset,
  input [(2 ** N + 1 + N * $clog2(PORTS_IN + LUTS)) * LUTS + $clog2(PORTS_IN + LUTS) * PORTS_OUT - 1 : 0] conf
);

  genvar i;
  genvar j;
  
  /* verilator lint_off UNOPTFLAT */
  wire xbar [PORTS_IN + LUTS];
  /* verilator lint_on UNOPTFLAT */

  for (i = 0; i < PORTS_IN; i = i + 1)
    begin : xbar_inputs
      assign xbar[i] = ports_in[i];
    end

  localparam LUT_CONF_SIZE = 2 ** N + 1;
  localparam XBAR_OPERAND_CONF_SIZE = $clog2(PORTS_IN + LUTS);
  localparam XBAR_CONF_SIZE = 2 * XBAR_OPERAND_CONF_SIZE;
  localparam STRIDE = LUT_CONF_SIZE + XBAR_CONF_SIZE;


  for (i = 0; i < LUTS; i = i + 1)
    begin : luts
      wire [N - 1 : 0] in;

      for (j = 0; j < N; j = j + 1)
        begin : lut_inputs
          wire [XBAR_OPERAND_CONF_SIZE - 1:0] operand = conf[STRIDE * i + LUT_CONF_SIZE + XBAR_OPERAND_CONF_SIZE * j +: XBAR_OPERAND_CONF_SIZE];
          assign in[j] = xbar[operand];
        end

      LUT #(.N(N)) lut (
        .clock(clock),
        .rst_n(rst_n),
        .in(in),
        .out(xbar[PORTS_IN + i]),
        .virtual_reset(virtual_reset),
        .conf(conf[STRIDE * i +: LUT_CONF_SIZE])
      );
    end
  
  for (i = 0; i < PORTS_OUT; i = i + 1)
    begin : outputs
      wire [XBAR_OPERAND_CONF_SIZE - 1:0] operand = conf[LUTS * STRIDE + XBAR_OPERAND_CONF_SIZE * i +: XBAR_OPERAND_CONF_SIZE];
      assign ports_out[i] = xbar[operand];
    end

endmodule

module ConfMemory #(
  parameter SIZE = 8
) (
  input clock,
  input rst_n,
  input prog_data,
  input prog_enable,
  output [SIZE - 1 : 0] conf
);

  reg [SIZE - 1 : 0] mem;

  always @(posedge clock)
    if (!rst_n)
      mem <= 0;
    else
      if (prog_enable)
        mem <= {mem[SIZE - 2 : 0], prog_data};

  assign conf = mem;

endmodule

module tt_um_fpga_can_lehmann (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  localparam IN_PORTS_PER_POOL = 8;
  localparam OUT_PORTS_PER_POOL = 4;
  localparam LUTS_PER_POOL = 8;
  localparam N = 3;
  localparam XBAR_OPERAND_CONF_SIZE = $clog2(IN_PORTS_PER_POOL + LUTS_PER_POOL);
  localparam CONF_SIZE =
    (2 ** N + 1 + N * $clog2(IN_PORTS_PER_POOL + LUTS_PER_POOL)) * LUTS_PER_POOL +
    XBAR_OPERAND_CONF_SIZE * OUT_PORTS_PER_POOL;

  wire [CONF_SIZE - 1 : 0] conf;

  ConfMemory #(
    .SIZE(CONF_SIZE)
  ) conf_memory (
    .clock(clk),
    .rst_n(rst_n),
    .prog_data(uio_in[0]),
    .prog_enable(uio_in[1]),
    .conf(conf)
  );

  Pool #(
    .PORTS_IN(IN_PORTS_PER_POOL),
    .PORTS_OUT(OUT_PORTS_PER_POOL),
    .LUTS(LUTS_PER_POOL),
    .N(N)
  ) pool (
    .clock(clk),
    .rst_n(rst_n),
    .ports_in(ui_in),
    .ports_out(uo_out[3:0]),
    .virtual_reset(uio_in[2] | uio_in[1]),
    .conf(conf)
  );

  assign uo_out[7:4] = 0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, clk, rst_n, ui_in[7:3], 1'b0};

endmodule
