# Can Joshua Lehmann 2026

import math
from dataclasses import dataclass

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly

N = 2 # LUT Size
IN_PORTS_PER_POOL = 8
OUT_PORTS_PER_POOL = 4
LUTS_PER_POOL = 8

XBAR_OPERAND_CONF_SIZE = math.ceil(math.log2(IN_PORTS_PER_POOL + LUTS_PER_POOL))

# a b | out
# 0 0 | 0
# 0 1 | 1
# 1 0 | 1
# 1 1 | 0
lut_toggle1_if0 = [False, True, True, False]
lut_and = [False, False, False, True]
lut_toggle1 = [True, True, False, False]

@dataclass
class LUT:
    lut: list[bool]
    inputs: list[int]
    register: bool = False

    def default() -> "LUT":
        return LUT([False] * (2 ** N), [0] * N, False)

@dataclass
class Conf:
    luts: list[LUT]
    outputs: list[int]

@cocotb.test()
async def test_toggle(dut):
    pass

"""
def to_bitstream(conf: Conf) -> list[bool]:
    while len(conf.luts) < LUTS_PER_POOL:
        conf.luts.append(LUT.default())

    while len(conf.outputs) < OUT_PORTS_PER_POOL:
        conf.outputs.append(0)
    
    data = []

    def write_int(value: int, width: int):
        assert value >= 0
        assert value < 2 ** width

        for i in range(width):
            data.append((value >> i) & 1 == 1)

    for lut in conf.luts:
        write_int(lut.register, 1)
        data += lut.lut
        for input in lut.inputs:
            write_int(input, XBAR_OPERAND_CONF_SIZE)

    for output in conf.outputs:
        write_int(output, XBAR_OPERAND_CONF_SIZE)

    return data

async def load_conf(dut, conf: Conf):
    bitstream = to_bitstream(conf)

    for bit in reversed(bitstream):
        dut.uio_in.value = 2 | int(bit)
        await ClockCycles(dut.clk, 1)
    
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 10)

    dut.uio_in.value = 4
    await ClockCycles(dut.clk, 1)
    
    dut.uio_in.value = 0

async def reset(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

@cocotb.test()
async def test_toggle(dut):
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await reset(dut)
    await load_conf(dut, Conf(
        luts=[
            LUT(
                lut=lut_toggle1,
                inputs=[IN_PORTS_PER_POOL + 0, IN_PORTS_PER_POOL + 0],
                register=True
            )
        ],
        outputs=[IN_PORTS_PER_POOL + 0]
    ))

    for i in range(10):
        await ReadOnly()
        assert dut.uo_out.value[0] == 0
        await ClockCycles(dut.clk, 1)
        await ReadOnly()
        assert dut.uo_out.value[0] == 1
        await ClockCycles(dut.clk, 1)

@cocotb.test()
async def test_counter(dut):
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    await reset(dut)
    await load_conf(dut, Conf(
        luts=[
            LUT(
                lut=lut_toggle1,
                inputs=[IN_PORTS_PER_POOL + 0, IN_PORTS_PER_POOL + 0],
                register=True
            ),
            LUT(
                lut=lut_toggle1_if0,
                inputs=[IN_PORTS_PER_POOL + 0, IN_PORTS_PER_POOL + 1],
                register=True
            ),
            LUT(
                lut=lut_toggle1_if0,
                inputs=[IN_PORTS_PER_POOL + 4, IN_PORTS_PER_POOL + 2],
                register=True
            ),
            LUT(
                lut=lut_toggle1_if0,
                inputs=[IN_PORTS_PER_POOL + 5, IN_PORTS_PER_POOL + 3],
                register=True
            ),
            # Carry logic
            LUT(
                lut=lut_and,
                inputs=[IN_PORTS_PER_POOL + 0, IN_PORTS_PER_POOL + 1],
                register=False
            ),
            LUT(
                lut=lut_and,
                inputs=[IN_PORTS_PER_POOL + 4, IN_PORTS_PER_POOL + 2],
                register=False
            )
        ],
        outputs=[
            IN_PORTS_PER_POOL + 0,
            IN_PORTS_PER_POOL + 1,
            IN_PORTS_PER_POOL + 2,
            IN_PORTS_PER_POOL + 3,
        ]
    ))

    for i in range(32):
        await ReadOnly()
        assert dut.uo_out.value == i % 16
        await ClockCycles(dut.clk, 1)
"""