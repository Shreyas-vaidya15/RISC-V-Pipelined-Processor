# RV32I RISC-V Processor with Nested Interrupts, Exceptions and a Shared AHB-Lite Bus (5-Stage Pipeline)

A **32-bit RV32I RISC-V Processor** implemented in **Verilog HDL** and built up in stages: a single-cycle design, converted into a **5-stage pipelined implementation** (IF → ID → EX → MEM → WB), then given hazard control (full data forwarding and load-use stall handling), then **BTFNT static branch prediction** (backward-taken, forward-not-taken: a branch that jumps backward, like a loop, is guessed taken; one that jumps forward is guessed not taken; `jal` is always redirected in IF), then extended with **machine-mode trap handling for two external interrupt sources (keyboard, disk) with hardware priority tracking and software-managed nesting**, then with **synchronous exceptions** (illegal instruction, misaligned memory accesses, `ecall`, `ebreak`, instruction faults), then with an **AHB-Lite bus**: the data memory and the instruction memory now sit outside the CPU as AHB slaves, and instruction fetch and load/store share **one bus** with the CPU as the only master. An address decoder selects the instruction memory, the data memory or a **default slave** that answers unmapped addresses with an **ERROR response**. Slaves can insert **wait states** and answer with ERROR: an ERROR on a load/store becomes a load/store access-fault exception, an ERROR on a fetch becomes an instruction access fault. Finally the core got the **identification CSRs** and the 64-bit **`mcycle` / `minstret` counters**.

The control and status registers (CSRs) follow the **official RISC-V privileged spec**: standard CSR addresses, `mstatus` bit layout, `mie`, `mip`, `mtvec` (with direct/vectored mode), `mtval`, `mscratch`, `misa`, the identification CSRs (`mvendorid`, `marchid`, `mimpid`, `mhartid`) and the cycle / instructions-retired counters (`mcycle`, `minstret` and their read-only `cycle` / `instret` copies). The only non-standard CSRs are the two priority registers, placed in the spec's custom machine-mode address range.

---

## Features

- 32-bit RV32I architecture, machine mode only
- **5-stage pipelined datapath**: IF, ID, EX, MEM, WB
- Dedicated pipeline registers: `IF_ID_reg`, `ID_EX_reg`, `EX_MEM_reg`, `MEM_WB_reg`
- **Full data forwarding**: `forwarding_unit` + `forward_mux` resolve RAW hazards from EX/MEM and MEM/WB (ALU operands, store data/address, `jalr` base, CSR reads)
- **Load-use stall detection**: `stall_unit` inserts a one-cycle bubble only when the instruction in ID really reads the register the load writes: rs1 for `jalr`, loads, ALU-immediate and the register forms of CSR instructions; rs1 and rs2 for branches, stores and ALU-register instructions. Instructions that read no register (`lui`, `auipc`, `jal`, the CSR-immediate forms, `ecall`, `ebreak`, `mret`) never stall, so immediate or shift-amount bits that look like the loaded register number no longer cause a false stall
- **BTFNT static branch prediction**: predicted in IF from the sign of the branch offset, resolved in EX; a mispredicted branch flushes `IF_ID_reg` and `ID_EX_reg`
- **`jal` redirected in IF**: `jal` always jumps, so IF takes its target (J-type immediate) straight away and nothing is flushed. Only `jalr`, whose target needs a register value, still redirects from EX and flushes
- **Real `nop` bubbles**: a flushed or stalled slot holds `addi x0, x0, 0` (`0x00000013`) as the spec requires, and a `Valid` bit travels with each instruction through every stage up to WB, so the core can tell a bubble from a real `nop`
- **One shared AHB-Lite bus** for instruction fetch and load/store (CPU = only master), with an **address decoder**, two slaves (instruction memory, data memory) and a **default slave** for unmapped addresses (see [Memory map](#memory-map))
- **Arbitration in the master**: a load/store in MEM wins the bus, the fetch waits. A fetch is presented only when `HREADY = 1`
- **Wait states** (`HREADY` freezes the pipeline) and a **two-cycle ERROR response** (`HRESP`). An ERROR on a load/store is a trap (cause 5 / 7); an ERROR on a fetch is not a trap on the bus, it travels with the instruction as an instruction access fault (cause 1)
- **Two external interrupt sources (keyboard, disk)**, each with its own pending latch (`interrupt_latch`); both are reported as machine external interrupts (cause 11)
- **Priority-based arbitration**: `interrupt_priority_encoder` reports the highest pending source (disk = 2, keyboard = 1, none = 0). A trap is taken only if that level is **strictly greater than** the level currently running (`current_priority`)
- **Hardware priority save/restore**: on trap entry `previous_priority <= current_priority` and `current_priority <= interrupt_ID`; `mret` restores `current_priority <= previous_priority`
- **Software-managed nesting**: a handler saves `mepc`, `mcause`, `previous_priority` and any live registers on a stack in data memory *before* re-enabling `mstatus.MIE`
- **Exceptions** raised from ID, EX and WB, each with its spec cause code and an `mtval` value (see [Exceptions](#exceptions))
- **Older-transfer hold**: an exception never overtakes an older load/store that is still on the bus (see [Older-transfer hold](#older-transfer-hold))
- **CSR set**: `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, the identification CSRs (`mvendorid`, `marchid`, `mimpid`, `mhartid`, all reading 0), plus custom `current_priority` / `previous_priority`
- **Cycle and instruction counters**: 64-bit `mcycle` and `minstret` (low and high halves) with read-only `cycle` / `instret` copies. `mcycle` counts every clock, including stall and wait-state cycles. `minstret` counts only instructions that retire: bubbles and trapped or squashed instructions are never counted
- **Read-only CSRs**: a write to a CSR whose address bits [11:10] are `11` raises an illegal-instruction exception
- **Writable `mtvec`** with direct and vectored modes
- `csrrs`/`csrrc`/`csrrsi`/`csrrci` with `rs1`/`uimm` = 0 only read, as the spec requires
- CSR write bypasses so an `mret` or a trap in ID sees a CSR write that is still in EX
- Register file with same-cycle write-read bypass
- Self-checking Verilog testbench that sweeps an interrupt across every cycle of a program, in four wait-state modes, with bus errors and fetch faults in the program

---

## Project Structure

```text
.
├── alu.v
├── alu_decoder.v
├── alu_mux.v
├── branch_comparator.v           # branch decision: equal / signed less-than / unsigned less-than on the two register values
├── csr_addr_decoder.v            # CSR address -> "which CSR is addressed" select signals
├── csr_read_data.v               # selects the old CSR value returned to rd
├── csr_write_data.v              # selects the new CSR value to write, per funct3
├── csr_counters.v                # mcycle / minstret 64-bit counters (cycle / instret read the same registers)
├── current_priority.v            # priority level of the code currently running (0 = main program)
├── previous_priority.v           # level that was interrupted; restored into current_priority by mret
├── interrupt_priority_encoder.v  # pending keyboard/disk -> interrupt_ID (2 = disk, 1 = keyboard, 0 = none)
├── interrupt_latch.v             # per-source pending latch (keyboard + disk instances)
├── instruction_memory.v          # sweep program image (module inst_memory, built by an initial block, see Verification)
├── inst_memory_hex.v             # instruction memory loaded from a hex file (C programs, tb_rv.v); same module name as instruction_memory.v, compile only one of the two
├── main_decoder.v
├── illegal_function.v            # illegal funct3 / funct7 detection
├── illegal_csr_addr.v            # CSR address not implemented, or a write to a read-only CSR
├── misaligned_detect.v           # misaligned load/store (EX)
├── instruction_address_misalign.v# taken branch/jump to a target with bit 1 set (EX)
├── instruction_access_fault.v    # fetch address outside the instruction memory window (IF), BASE and DEPTH parameters
├── mepc.v                        # PC of the instruction that trapped
├── mcause.v                      # trap cause register
├── mtval.v                       # extra trap info (bad address / instruction bits)
├── mtvec.v                       # trap vector base + mode (writable, resets to 0x65)
├── mie.v                         # mstatus.MIE (global interrupt enable)
├── mpie.v                        # mstatus.MPIE (MIE saved on trap entry)
├── mie_csr.v                     # mie CSR (0x304): per-source enables
├── mscratch.v                    # scratch register for software
├── misa.v                        # hardwired RV32I
├── pc.v
├── pc_mtvec_mcause.v             # trap target from mtvec mode, base and interrupt_ID
├── pc_mux.v
├── pc_plus_4.v
├── pc_target.v
├── register_file.v
├── result_mux.v
├── sign_extender.v
├── load_extend.v                 # sign/zero-extends HRDATA for lb/lh/lw/lbu/lhu (WB)
├── IF_stage.v / IF_ID_reg.v
├── ID_stage.v / ID_EX_reg.v
├── EX_stage.v / EX_MEM_reg.v
├── MEM_WB_reg.v
├── forwarding_unit.v             # RAW hazard detection (EX/MEM, MEM/WB)
├── forward_mux.v                 # 3-input operand select
├── stall_unit.v                  # load-use hazard detection (only for instructions that read the loaded register)
├── AHB_master_CPU_interface.v    # the master and its arbiter: load/store (EX/MEM outputs) and fetch -> one set of AHB-Lite master signals
├── AHB_interconnect.v            # address decoder, registered data-phase select (hsel_dp), response mux (HREADY / HRESP / HRDATA)
├── AHB_inst_memory.v             # AHB-Lite slave: read-only instruction memory (wraps inst_memory)
├── data_memory.v                 # byte-organised memory array (little-endian)
├── AHB_data_memory.v             # AHB-Lite slave: wait states, ERROR response, wraps data_memory
├── AHB_default_slave.v           # AHB-Lite slave for unmapped addresses: answers every transfer with ERROR
├── top.v                         # the CPU: pipeline + interrupt/exception logic + bus master side
├── soc_top.v                     # CPU + interconnect + instruction slave + data slave + default slave
├── tb.v                          # interrupt sweep testbench (module tb_sweep)
├── tb_rv.v                       # riscv-tests (rv32ui) testbench (module tb_rv)
└── README.md
```

There is no separate MEM-stage module: the data memory is outside the CPU, so the MEM stage is just the `EX_MEM_reg` outputs driving the bus (`AHB_master_CPU_interface`).

---

## Pipeline Architecture

```text
IF_stage → IF_ID_reg → ID_stage → ID_EX_reg → EX_stage → EX_MEM_reg → MEM_WB_reg → load_extend / result_mux → (register file)
   │  ▲                                           │  ▲
   │  └── instruction (data phase, HRDATA) ───────┼──┘ load/store data phase (HRDATA / HWDATA)
   └── fetch address ─────► AHB_master_CPU_interface ◄── load/store address (EX_MEM_reg) ──► ONE shared AHB-Lite bus
```

- **IF**: PC register, PC+4 adder, branch predictor (backward branches, and `jal` always), PC mux (trap / EX redirect / `mret` / predicted target / PC+4), the fetch **address phase** on the shared bus, the fetch **data phase** one cycle later (the instruction comes back on `HRDATA`), a delayed PC and a valid bit that travel with the instruction in flight, a one-entry buffer that holds the instruction when the front end is frozen, and the instruction access fault check
- **ID**: register file read (with write bypass), immediate extension, control decode, illegal-instruction detection (including a write to a read-only CSR), `mret` detection (redirects PC to `mepc` from here)
- **EX**: ALU, branch resolution, `jalr`/`auipc` handling, CSR read/write value computation, misaligned-access detection, interrupt acceptance point
- **MEM**: the **address phase** of a load/store goes out on the bus (`HADDR`, `HWRITE`, `HSIZE`, `HTRANS`) from the `EX_MEM_reg` outputs
- **WB**: the **data phase** of the same load/store happens while it sits in WB (`HRDATA` comes back, `HWDATA` goes out, a bus ERROR arrives). `load_extend` extends the data, `result_mux` selects ALU result / memory data / PC+4 / old CSR value. An instruction **retires** here (counted by `minstret`) if its `Valid` bit is set, the stage is not frozen and it took no bus error

### Hazard Control

- **Forwarding**: EX/MEM has priority over MEM/WB. The EX/MEM candidate is `ALUResult` normally, `PC+4` for `jal`/`jalr`, and the old CSR value for CSR reads.
- **Stalling**: a load in EX holds the pipeline one cycle only if the instruction in ID reads the register the load writes. rs1 is read by `jalr`, loads, stores, ALU-immediate, ALU-register, branches and the register forms of CSR instructions; rs2 is read by branches, stores and ALU-register instructions. `lui`, `auipc`, `jal`, the CSR-immediate forms, `ecall`, `ebreak` and `mret` read no register, so they never stall, even if their immediate bits happen to match the loaded register number.
- **Flush**: a mispredicted branch or a `jalr` resolves in EX and flushes the two younger instructions. `jal` no longer flushes, because it is redirected in IF.
- **Fetch denied**: when a load/store in MEM takes the bus, the fetch address is not sent. The front end still advances, so a bubble follows, but the PC stays on the address that was not sent (a predicted-taken jump still moves the PC to its target).
- **Bus wait (`HREADY` low)**: the whole pipeline freezes (see below).

---

## Shared AHB-Lite Bus

The CPU (`top.v`) is the only AHB-Lite **master**. Instruction fetch and load/store use the same bus. `soc_top.v` joins the CPU, the interconnect and three slaves.

### Memory map

Each window is 4 KB and is decoded on `HADDR[31:12]` (`REGION_BITS = 12` in `AHB_interconnect.v`).

| Slave | Base | Notes |
|---|---|---|
| Instruction memory (`AHB_inst_memory`) | `0x0000_0000` | Read-only. The reset PC is 0. |
| Data memory (`AHB_data_memory`) | `0x1000_0000` | 256 bytes by default. Reachable with one `lui` plus a 12-bit offset. |
| Default slave (`AHB_default_slave`) | everything else | Answers every transfer with the two-cycle ERROR response. |

Both memories have a `BASE` parameter and work on `HADDR - BASE`, so moving a slave is a one-parameter change (a boot ROM is meant to go at `0x0` later, with the instruction memory moving). `instruction_access_fault` has the same `BASE` and `DEPTH` parameters.

### Master side and arbitration (`AHB_master_CPU_interface.v`)

| Signal | Driven by |
|---|---|
| `HADDR` | `ALUResult_MEM` when a load/store is in MEM, otherwise the fetch address |
| `HWRITE` | `MemWrite_MEM` (0 for a fetch) |
| `HSIZE` | `{1'b0, Width_MEM}` for a load/store (byte / halfword / word), word for a fetch |
| `HTRANS` | NONSEQ (`2'b10`) when a load/store is in MEM, or when the fetch is granted; otherwise IDLE (`2'b00`). Forced to IDLE in the last cycle of a **load/store** ERROR response (`HRESP & HREADY` with the data phase a load/store), which cancels the next transfer, whichever it is. Also IDLE while `reset` is high. A fetch ERROR cancels nothing |
| `HWDATA` | `RD2_WB` (store data, one cycle after the address phase) |

- **A load/store in MEM wins the bus**; the fetch waits (`fetch_grant = 0`).
- **A fetch is presented only when `HREADY = 1`.** An unaccepted fetch address never has to be held, because the fetch address can change in any cycle (redirect, trap). A load/store address is held by the frozen pipeline while `HREADY = 0`.
- The fetch drops its address (`HTRANS = IDLE`) on `EX_Override_EX`, `Mret_taken_ID`, `interrupt_taken` and `exception_taken`.
- `dp_data` and `dp_fetch` say whether the transfer in its data phase is a load/store or a fetch. They update only when `HREADY = 1`, like the slaves' saved address phase.
- Back-to-back load/stores slow the fetch: it only gets the bus in the gaps. This costs throughput only, not correctness.

### Interconnect (`AHB_interconnect.v`)

- **Decoder**: compares `HADDR[31:12]` with each slave's base. The default slave is selected when no other slave matches, so exactly one `HSEL` is high at any time.
- **`hsel_dp`**: a registered copy of the selects, updated only when `HREADY = 1`. It says which slave's response belongs to the data phase on the bus. It resets to the default slave, which answers OKAY and ready while idle.
- **Response mux**: `HREADY`, `HRESP` and `HRDATA` come from the slave picked by `hsel_dp`. The result is the bus-wide `HREADY` that the master, the pipeline and every slave see.

### Wait states (`HREADY` low)

While `HREADY = 0` everything is frozen: `EX_MEM_reg` and `MEM_WB_reg` hold, the front of the pipeline (`pc`, `IF_ID_reg`, `ID_EX_reg`) holds, and nothing acts: no register write, no CSR write, no interrupt, no exception. A frozen stage acts **once**, in the last cycle (the one where `HREADY = 1`). All bus signals driven by the master stay unchanged while a transfer is pending and `HREADY` is low (the one allowed change is `HTRANS` going to IDLE in the last cycle of a load/store ERROR response). Because `HREADY` is bus-wide, the first cycle of an ERROR response to a fetch also freezes the pipeline for one cycle.

### Slaves

Each slave is a small FSM; the outputs depend only on the state. A transfer is accepted when `HSEL && HTRANS[1] && HREADY` (the bus-wide `HREADY`).

| State | `HREADYOUT` | `HRESP` | `HRDATA` | Meaning |
|---|---|---|---|---|
| `OKAY` | 1 | 0 | memory data (0 in the default slave) | ready |
| `WAIT` (data memory only) | 0 | 0 | `0xBAD0BAD0` | inserting wait states |
| `ERR1` | 0 | 1 | 0 | first ERROR cycle |
| `ERR2` | 1 | 1 | 0 | second (last) ERROR cycle |

- **Instruction memory**: read-only, no wait states. A write, or an offset `>= DEPTH * 4`, gets an ERROR response.
- **Data memory**: `WAIT_CYCLES` (a 4-bit input, a test knob) is the number of wait states given to each accepted transfer (0 = none). An out-of-range offset (`>= DEPTH * 4`, start address only; `DEPTH` is in words, default 64 = 256 bytes) gets an ERROR response; wait states come first, then the two-cycle ERROR. The address phase is saved and a write happens in the data phase, only when `HREADYOUT = 1` and `HRESP = 0`, so a bad store never writes anything.
- **Default slave**: no memory, no wait states. Every accepted transfer gets the two-cycle ERROR. It stays in `OKAY` while the bus is idle.
- **`ERR2` also accepts a new transfer.** The master cancels the next address only after a load/store ERROR, not after a fetch ERROR, so a slave in `ERR2` can already see a new bad transfer and goes to `ERR1` again (the data memory goes to `WAIT` if it has to wait first).
- Misaligned accesses never reach a slave: they trap in EX first.

Not implemented yet: a boot ROM and peripherals (the memory map has room for them), more than one master.

---

## CSR Map

| Address | CSR | Notes |
|---|---|---|
| `0x300` | `mstatus` | Read: `MIE` at bit 3, `MPIE` at bit 7, `MPP` (bits 12:11) fixed to `11`. Write: only `MIE` and `MPIE` change |
| `0x301` | `misa` | Hardwired `0x40000100` (32-bit, base `I`). Writes ignored |
| `0x304` | `mie` | Per-source enables. Only bit 11 (external) and bit 7 (timer) are stored |
| `0x305` | `mtvec` | Resets to `0x65` (base `0x64`, vectored mode). Bit 1 is forced to 0; bit 0 is the mode |
| `0x340` | `mscratch` | Plain read/write |
| `0x341` | `mepc` | Low 2 bits forced to 0 on write |
| `0x342` | `mcause` | Writable |
| `0x343` | `mtval` | Writable |
| `0x344` | `mip` | Read-only. Bit 11 = keyboard or disk pending. Writes ignored |
| `0x7C0` | `current_priority` | Custom (spec's custom machine-mode range). Level of the running code |
| `0x7C1` | `previous_priority` | Custom. Level that was interrupted |
| `0xB00` / `0xB80` | `mcycle` / `mcycleh` | 64-bit cycle counter, low / high half. Read-write. Counts every clock, including stall and wait-state cycles |
| `0xB02` / `0xB82` | `minstret` / `minstreth` | 64-bit instructions-retired counter, low / high half. Read-write |
| `0xC00` / `0xC80` | `cycle` / `cycleh` | Read-only copy of `mcycle` / `mcycleh` (same counter, different address) |
| `0xC02` / `0xC82` | `instret` / `instreth` | Read-only copy of `minstret` / `minstreth` |
| `0xF11` | `mvendorid` | Read-only, reads 0 |
| `0xF12` | `marchid` | Read-only, reads 0 |
| `0xF13` | `mimpid` | Read-only, reads 0 |
| `0xF14` | `mhartid` | Read-only, reads 0 (one hart) |

Accessing any other CSR address raises an illegal-instruction exception (cause 2). So does **writing** a read-only CSR (address bits [11:10] = `11`: the identification CSRs and the `cycle` / `instret` copies). `csrrs`/`csrrc` with `rs1` = x0 and `csrrsi`/`csrrci` with `uimm` = 0 only read, so they are allowed on read-only CSRs.

Reset values: `MIE` = 0 and `MPIE` = 0, so **interrupts are off after reset**. Software must set `mie[11]` and then `mstatus.MIE` before an interrupt can be taken. `mcycle` and `minstret` reset to 0.

### Counters

- `mcycle` is a 64-bit register that adds 1 every clock.
- `minstret` is a 64-bit register that adds 1 for every instruction that **retires**: one that is in WB with its `Valid` bit set, while `HREADY` is high and no bus error occurs. Bubbles, instructions squashed by a flush or an interrupt, and instructions that trap (including `ecall` and `ebreak`) are not counted. An instruction squashed by an interrupt is counted once, when it re-executes after `mret`. `mret` and ordinary `nop`s are counted.
- CSR instructions read and write in EX, while retirement happens in WB. So a read of `minstret` returns the stored count plus the older instructions still in MEM and WB that are about to retire: it reflects every older instruction and nothing younger.
- A write to one half replaces that half of the 64-bit value; the other half is kept. The writing instruction itself is not counted. A write wins over an increment in the same clock.
- Reading the two halves is two separate instructions, so software that needs a consistent 64-bit value reads high, low, high and repeats if the high halves differ.

---

## Interrupt Handling

### Trap acceptance

A trap is taken in a cycle when **all** of these hold:

```text
interrupt_taken = mstatus.MIE
                & mie[11]
                & (interrupt_ID != 0)
                & (interrupt_ID > current_priority)
                & EX is not a bubble
                & EX is not an mret
                & HREADY                 (bus not waiting: a frozen stage acts once)
                & no bus error this cycle
                & no load/store in MEM
```

- The bubble and `mret` conditions guarantee `mepc` never captures a bogus PC (a bubble has no real PC; an `mret` in EX has already redirected fetch).
- **No interrupt while a load/store is in MEM.** Otherwise the interrupt would squash the instruction in EX but let the older transfer finish, and a bus error from that transfer would arrive as a second trap right after the interrupt, overwriting `mepc` and `MPIE`. The interrupt just waits one cycle. Because of this, the instructions right behind a load/store are never interrupted (by design).
- Keyboard and disk share the single external-interrupt enable (`mie[11]`); the priority registers are what tell them apart.

### What happens on trap entry

- `mepc <= PC` of the instruction in EX (that instruction is squashed and re-executed after `mret`)
- `mcause <= 0x8000000B` (interrupt bit set, cause 11 = machine external), `mtval <= 0`
- `mstatus.MPIE <= mstatus.MIE`, then `mstatus.MIE <= 0`
- `previous_priority <= current_priority`, `current_priority <= interrupt_ID`
- IF/ID, ID/EX and EX/MEM are flushed, and the fetch drops its address (`HTRANS = IDLE`)
- PC <= trap target (see below)
- The served source's pending bit is cleared; the other source's stays set

### Trap vector

`mtvec` holds a base address and a mode in bit 0:

| Mode (`mtvec[0]`) | Interrupts go to | Exceptions go to |
|---|---|---|
| 0 (direct) | base | base |
| 1 (vectored) | base + 4 × cause | base |

After reset `mtvec = 0x65`, so base = `0x64` and mode = vectored. Both interrupt sources have cause 11, so they land at `0x64 + 44 = 0x90` (144). Exceptions land at `0x64` (100).

### What happens on `mret`

- PC <= `mepc` (redirected from the ID stage)
- `mstatus.MIE <= mstatus.MPIE`, `mstatus.MPIE <= 1`
- `current_priority <= previous_priority`
- A wrong-path `mret` (behind a mispredicted branch) is ignored for these updates
- If an `mepc`, `previous_priority` or `mstatus` write is still in EX when the `mret` is in ID, the `mret` uses the value being written (CSR write bypass)
- An `mret` acts once even if it waits in ID for a hold or a bus wait

### Priority and nesting rules

The comparison is strict (`>`), as in the spec-style PLIC rule: a source cannot interrupt a handler of its own level.

| Running at | Disk (2) asserts | Keyboard (1) asserts |
|---|---|---|
| Main program (0) | taken | taken |
| Keyboard ISR (1) | taken (nests, 2 > 1) | **blocked** (1 is not > 1) until keyboard's `mret` |
| Disk ISR (2) | **blocked** (2 is not > 2) until disk's `mret` | **blocked** (1 < 2) until disk's `mret` |

Both sources at once: disk wins; keyboard stays pending and fires after disk's `mret`. With two sources, nesting is at most keyboard → disk.

### Handler structure

A handler that wants to allow nesting should:

1. Allocate a stack frame; save any live registers, `mepc`, `mcause` and `previous_priority`
2. Set `mstatus.MIE` (nesting is now possible, still gated by the priority compare)
3. Do the work
4. Clear `mstatus.MIE` (the epilogue must not be interrupted), restore the saved CSRs and registers, free the frame, `mret`

---

## Exceptions

Exceptions are synchronous: they come from the instruction itself. They use the same trap machinery as interrupts, with `mcause[31] = 0`.

| Cause | Meaning | Detected in | `mtval` holds |
|---|---|---|---|
| 0 | Instruction address misaligned (taken branch / `jal` / `jalr` target has bit 1 set) | EX | the bad target address |
| 1 | Instruction access fault: the fetch address is outside the instruction memory window (range check in IF), or the fetch got an **ERROR response** on the bus | ID (flag set in IF) | the fetch PC |
| 2 | Illegal instruction | ID | the instruction bits |
| 3 | `ebreak` | ID | 0 |
| 4 | Load address misaligned | EX | the bad address |
| 5 | Load access fault: a slave answered a load with an **ERROR response** | WB (bus response) | the bad address |
| 6 | Store address misaligned | EX | the bad address |
| 7 | Store access fault: a slave answered a store with an **ERROR response** | WB (bus response) | the bad address |
| 11 | `ecall` | ID | 0 |

**Illegal instruction** covers: unknown opcode, illegal `funct3`, illegal `funct7`, an unimplemented CSR address, a **write to a read-only CSR**, and a SYSTEM instruction with `funct3 = 000` whose immediate is not `ecall`, `ebreak`, `mret` or `wfi`.

### Load/store access faults come from the bus

There is no address-range check in the CPU for data accesses. The slaves (and the default slave, for addresses nobody owns) are the only judges, and the CPU learns about it from the ERROR response. The bad address can be outside the data memory, in an unmapped region, or a write to the read-only instruction memory:

- The ERROR response lasts two cycles (`HRESP = 1`: `ERR1` with `HREADY = 0`, then `ERR2` with `HREADY = 1`). The CPU traps in the **last** cycle: `bus_error = HRESP & HREADY & dp_data`. The `dp_data` term means the data phase belongs to a load/store; an ERROR on a fetch is not a bus error.
- The faulting load/store is in **WB** at that moment. So `mepc = PC_Plus_4_WB - 4`, `mtval = ALUResult_WB`, and the cause is 5 for a load (`IsLoad_WB`) or 7 for a store.
- A faulting load does **not** write `rd` (the register write is blocked in the trap cycle, so `rd` keeps its old value). A faulting store writes nothing to memory (the slave blocks the write while `HRESP` is high). The slave returns `HRDATA = 0` during the ERROR.
- In that cycle `HTRANS` is forced to IDLE so no new transfer starts. The instructions younger than the faulting one (in EX, ID, IF) are squashed and re-run after `mret`.

### Fetch faults come from the range check or from the bus

A fetch fault is not a trap at the bus. It travels with the instruction as a fault flag:

- **Range check**: a fetch address outside the instruction memory window (`BASE`, `DEPTH`) sets the flag in IF and no bus transfer is made.
- **Bus ERROR**: a fetch that goes out on the bus and comes back with an ERROR response (for example an address nobody owns) sets the same flag when the response arrives. The bubble-instruction (`nop`) moves on with the flag set.
- In ID the flag raises cause 1 with `mtval` = the fetch PC. `mepc` is the fetch PC, so the handler must resume somewhere valid (adding 4 would fault again).

### Rules

- `mepc` is the PC of the instruction that caused the exception (for `ecall`/`ebreak` the handler must add 4 itself before `mret`; for a bus error the handler adds 4 to skip the faulting load/store, or fixes the cause).
- On entry `mstatus.MPIE <= mstatus.MIE` and `mstatus.MIE <= 0`.
- **Priority when several things happen in the same cycle**: bus error > interrupt > exception from EX > exception from ID. The bus error belongs to the oldest instruction (WB), so it always goes first. An interrupt beats an exception: the instruction is squashed and re-faults after `mret`.
- An exception from EX squashes the instruction in EX. An exception from ID lets the older instruction in EX finish first.
- An exception behind a mispredicted branch or a `jalr` is on the wrong path and is ignored.
- When several causes occur in the same cycle, the order is: bus error, misaligned access, instruction address misaligned, instruction access fault, `ecall`, `ebreak`, illegal instruction.
- Exceptions do not change `current_priority`; the entry saves it into `previous_priority`.

**Memory sizes** (word counts, set by parameters): data memory `DEPTH = 64` words (256 bytes, parameter of `AHB_data_memory`); instruction memory `DEPTH = 256` words by default (parameter of `AHB_inst_memory`, and of `IF_stage` for the range check). The sweep testbench overrides the instruction slave to 1024 words (one 4 KB window, which the sweep image needs) and the range check in IF to 2048 words, on purpose (see Verification).

---

## Older-transfer hold

**Problem.** An exception B (from EX or ID) taken while an **older** load/store A is in MEM would trap first. Then A's bus error would trap a second time, overwriting `mepc` and `MPIE`. A is older, so A must be allowed to finish first.

An interrupt can simply wait (see the gate above), but an exception cannot move on, so it waits one cycle:

| Case | What happens during the hold |
|---|---|
| **`ex_hold`**: exception pending in **EX** (misaligned access, bad jump/branch target) with a load/store in MEM | B stays in EX. `pc`, `IF_ID_reg` and `ID_EX_reg` freeze (`pipe_ready` low); `EX_MEM_reg` takes a bubble, so B's own access never reaches the bus. `ID_EX_reg` also **captures B's forwarded operands**, because the instruction that supplied them leaves the pipeline during the hold and the forwarding source disappears |
| **`id_hold`**: exception pending in **ID** (illegal, `ecall`, `ebreak`, fetch fault) with a load/store in MEM | B stays in ID. Treated like the load-use stall: `pc` and `IF_ID_reg` freeze, `ID_EX_reg` takes a bubble. The older instruction in EX moves on normally |

Next cycle A is in WB. If A errors, `bus_error` traps for A and squashes B (B re-runs after `mret`). If not, B traps normally. There is no deadlock: after the hold, MEM holds a bubble (or an older instruction that is not stuck), so the gate turns off. An ID instruction behind a mispredicted branch or a `jalr` is on the wrong path and is flushed, not held.

The holds only matter when `HREADY = 1`; while `HREADY` is low everything is frozen anyway.

---

## Supported Instructions

All **40 RV32I base instructions**, the Zicsr CSR instructions, plus machine-mode trap support:

| Category | Instructions |
|---|---|
| R-type ALU | `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and` |
| I-type ALU | `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai` |
| Loads | `lb`, `lh`, `lw`, `lbu`, `lhu` |
| Stores | `sb`, `sh`, `sw` |
| Branches | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu` |
| Jumps | `jal`, `jalr` |
| Upper immediate | `lui`, `auipc` |
| System | `ecall`, `ebreak`, `mret` |
| Zicsr | `csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci` |
| Treated as `nop` | `fence`, `wfi` |

---

## Verification

### Interrupt sweep with wait states, bus errors and fetch faults (`tb_sweep`)

`tb.v` (module `tb_sweep`) is self-checking and tests `soc_top` (CPU + interconnect + the three slaves). It pairs with `instruction_memory.v`, which builds one deterministic program with Verilog functions that act as a small assembler. A passing run prints `=== ALL CHECKS PASSED ===`.

**The program.** It takes **23 exceptions on purpose**: 15 bus errors (11 in S8, 4 in S10), 3 exceptions from EX (S9) and 5 fetch faults (S10). It reads only CSRs whose values a trap would not change (`mscratch`, `misa`, `mie`, and `mstatus` only in windows where `MIE = 0`). Every data access uses `x30` as the base register, loaded with `0x1000_0000` at the start of S2 (`x30` holds the end marker 99 at the very end). Both handlers are **transparent**:

- the **interrupt handler** only increments `x23`;
- the **exception handler** counts the exception in `x24` and uses `x26` as scratch (cleared again before `mret`). It has two paths, told apart by `mepc >> 12`: a faulting **load/store** (inside the 4 KB program) is skipped with `mepc += 4`; a faulting **fetch** (a jump to `0x1000` or `0x2000`) resumes at the address kept in `mscratch`.

So with the same exceptions taken, everything except `x23` must be identical to a run with no interrupt.

| Section | What it covers |
|---|---|
| S1 | back-to-back ALU forwarding, shifts, `slt`/`sltu`, `lui` |
| S2 | stores/loads of every width, store-to-load, load-use stalls |
| S3 / S3b | loops (backward-taken branches, loop-exit mispredict, load-use in a loop); every branch type, taken / not taken, forward / backward |
| S4 | `jal` / `jalr`, call and return, `jalr` to a computed address |
| S5 | `mscratch` `csrrw`/`csrrs`/`csrrc`/`csrrsi` with the result used at once, `misa` read |
| S6 | `mstatus.MIE = 0` window, then `csrrw mepc ; mret` back to back |
| S7 | CSR / load-pointer / `mret` cases right behind a memory op (checks that a frozen stage acts once during wait states) |
| S10 (placed before S8 in the program) | **the shared bus**: 6 back-to-back stores and 6 back-to-back loads; a taken branch, a `jal` and a `jalr`, each right behind a load; a load from the instruction memory window (a legal read); **bus errors from the default slave** (load and store to `0x2000_0000`) and **from the read-only instruction slave** (a store to address 0); **fetch faults**: a jump to `0x1000` that comes back from the default slave with an ERROR (right behind a load, behind a load and a `nop`, behind a store and two `nop`s), a jump to `0x2000` caught by the range check, and a bad store with a faulty jump right behind it |
| S8 | **bus errors**: bad load, bad store, a good access right behind a bad one, back-to-back bad accesses, a bad access inside a loop, a bad load right before a mispredicted branch and before a `jal` (the bad base is `0x1000_0100`, the first word past the data memory) |
| S9 | **operand capture during the older-transfer hold**: an EX exception (misaligned load, misaligned store, taken branch with a misaligned target) right behind a load/store, with the operand it needs coming from a producer one place before that load/store. The stale operand would give a different result (no exception, a load that runs, a store that writes) |

**Wait modes.** The whole test is run once per mode. The wait states apply to the data slave; the instruction slave and the default slave never wait.

| Mode | Slave behaviour | Reference run length |
|---|---|---|
| 0 | no wait states | 1061 cycles |
| 1 | every transfer waits 1 cycle | 1166 cycles |
| 2 | every transfer waits 2 cycles | 1271 cycles |
| 3 | pseudo-random 0..3 waits per transfer (fixed per cycle number) | 1202 cycles |

**Parts of each mode**

| Part | What it does |
|---|---|
| 1. Reference run | Runs with no interrupt. Checks the final registers and data memory against golden values written next to the program, checks that exactly 23 exceptions were taken and that the image caused at least 3 older-transfer holds, then saves the final state |
| 2. Sweep | For each kind (keyboard, disk, both in the same cycle) and each injection cycle from 0 to the end of the program plus 8, resets, delivers one 1-cycle pulse, runs to the end marker, and compares against the reference run |
| 3. Reset in a handler | Resets 0 to 14 cycles after a trap is taken, checks every piece of trap state (CPU, all three slaves, the interconnect and the master's data-phase flags) is back at its reset value, then reruns the whole program and compares |
| 3b. Reset in an error response | Resets 0 to 5 cycles after a load/store ERROR response starts (the first, a middle and the last of the 15), checks the reset state, then reruns and compares |

**Compared on every run:** all registers except `x23`, every byte of data memory, `mscratch`, `mie`, `mtvec`, `mstatus.MIE`, `mstatus.MPIE`, `current_priority`, the interrupt count in `x23`, **the number of exceptions equals the reference run's**, no pending bits left, no load/store on the bus and all three slaves idle at the end.

**Fetch range check in the testbench.** The instruction slave is 4 KB (1024 words) but the fetch range check in IF is set to 8 KB (2048 words). A jump to `0x1000` passes the range check, goes out on the bus, finds no slave and comes back from the default slave with an ERROR (a real fetch ERROR). A jump to `0x2000` is outside both and is caught by the range check, without a bus transfer.

**Monitors that run every cycle**

- **AHB hold monitor**: if `HREADY` was low in the previous cycle and a transfer was pending (`HTRANS` NONSEQ), `HADDR`/`HTRANS`/`HWRITE`/`HSIZE`/`HWDATA` must be unchanged, with one exception: in the last cycle of an ERROR response `HTRANS` may change to IDLE. An IDLE address phase has nothing pending, so the master may present the fetch as soon as `HREADY` is high again.
- **Bus error monitor**: in every bus-error cycle `HTRANS` is IDLE, no register is written, no interrupt or other exception is taken, the data phase belongs to a load/store, and the slave that answers (instruction, data or default) is in `ERR2`. In the next cycle `mepc`/`mcause`/`mtval` must hold the faulting load/store's PC, cause 5 or 7, and the bad address (the instruction at that PC must really be a load or a store, and the address must be outside the data memory). It also counts how often an interrupt was ready to fire in the very cycle of a bus error (the bus error must win; this must happen at least once).
- **Coverage check**: for every instruction address where the interrupt gate was open at least once in the reference run, the sweep must have landed an interrupt there. A miss is a "hole" and fails the test. Addresses that are never open are blocked by design: before `MIE` is on, inside `MIE = 0` windows, right behind a load/store, and on `mret`.

**Result (from the latest run):** 14820 runs across the four modes (3363, 3678, 3993 and 3786), **0 failures, 0 coverage holes**, `=== ALL CHECKS PASSED ===`. In the reference run, 206 of 276 executed instruction addresses were open to an interrupt (an interrupt landed on all of them); the other 70 are blocked by design as listed above. The reference run is longer than the earlier versions (mode 0: 541 → 1061 cycles) because the program is bigger (S10 added) and fetch now shares the bus with load/stores.

### Official riscv-tests (rv32ui)

The core also runs the `rv32ui` suite from the official `riscv-tests` repository, built with a custom minimal `riscv_test.h` (not the stock environment, which needs privileged setup this SoC does not use). `tb_rv.v` (module `tb_rv`) runs one test per simulation.

**Result: 40 of 40 tests pass at 0, 1 and 2 wait states per transfer.** *(Measured before the load-use stall fix, `jal`-in-IF, the CSR/counter changes and the shared bus. Re-run pending: the tests do not run on the current memory map until the data section is relinked, see below. Update this line with the result.)*

- **Pass / fail protocol.** `TESTNUM` lives in `x3`. A pass sets `x10 = 0`; a fail sets `x10 = (test number << 1) | 1`. Both set `x30 = 99` and loop. The testbench prints PASS only if `x10 = 0` and no exception was taken. A FAIL line reports `x10`, the failing check number, `x3`, the exception count, `mepc` and `mcause`.
- **Memory layout.** `.text` is linked at address 0 and loaded through `+hex=` into the instruction memory (testbench overrides its depth to 1024 words, no RTL change). `.data` is loaded straight into the data slave's byte array through `+data=`. **With the shared bus the data memory sits at `0x1000_0000`, so `.data` must be linked at `0x1000_0000`** (the earlier runs linked it at address 0, which is now the instruction memory). The largest `.data` is 80 bytes, which fits the 256-byte data memory.
- **Harness check.** Running `lw` with a zeroed data image reports FAIL at check 2, so a failing test is visible.
- **Run:** `vvp sim_rv +hex=<test>.text.hex +data=<test>.data.hex [+wait=N]`
- **Reproduce everything:** `./rv_tests/run_rvtests.sh` builds the simulator, assembles all 40 tests and runs them at 0, 1 and 2 waits (needs `iverilog`, `riscv64-unknown-elf-gcc` and a clone of `riscv-tests` at `~/riscv-tests`). Run it from WSL or Linux.

Scope:

- `rv32ui` only. `fence_i` and `ma_data` are skipped (the core traps on misaligned accesses instead of handling them).
- No interrupts are injected in these runs; interrupt interaction is covered by `tb_sweep`.
- Wait modes 0, 1 and 2 only. The random-wait mode is covered by `tb_sweep`.

### Known limitations

- Interrupt inputs must be **1-cycle pulses**: the latch is level-sensitive, so an input held high re-latches right after being served.
- Priority scheme is fixed at two levels (keyboard 1, disk 2); adding sources means widening the priority registers and encoder.
- Keyboard and disk share `mie[11]`; there is no per-source enable. `mie[7]` (timer) is stored but there is no timer source yet.
- `mstatus` writes only affect `MIE` and `MPIE`; `MPP` always reads `11`. Writes to `misa` and `mip` are ignored without an exception.
- `fence` and `wfi` are treated as `nop`.
- Misaligned loads and stores trap instead of being handled in hardware.
- One master only. There is no boot ROM and there are no peripherals yet; the memory map has room for them.
- Back-to-back load/stores slow instruction fetch (the fetch only gets the bus in the gaps): a throughput loss, not a correctness issue.
- There is no execute protection: a fetch that reached the data memory window would read data as instructions. The range check in IF (`instruction_access_fault`) stops a fetch outside the instruction memory window.
- `tb_sweep` reaches fetch ERRORs only through the default slave and the range check. The instruction slave's own ERROR path for a fetch (and its `ERR2` accepting a new bad transfer) was checked only in a separate small directed test with an instruction memory smaller than the range check, not in this repository.
- Interrupts are not taken while a load/store is in MEM (they wait one cycle).
- The register file and data memory have no reset; the testbench clears them itself on every reset.
- No `time` CSR, `mcountinhibit`, `mcounteren` or hardware performance-monitor counters.
- `tb_sweep` never reads the new identification or counter CSRs, so they have no self-checking test in this repository.
- `tb_rv.v` and the C-program flow are not yet adapted to the new memory map (see the rv32ui section).

---

## Development Environment

- Visual Studio Code, GitHub Desktop
- Verilog HDL, Icarus Verilog, GTKWave, Git, GitHub

---

## Running the Simulation

The `-s` name must match the testbench module in `tb.v` (`tb_sweep`), and the matching `instruction_memory.v` image must be in the folder. `inst_memory_hex.v` (used by the C programs and `tb_rv.v`) defines the same module name as `instruction_memory.v`, so compile only one of the two.

```bash
iverilog -s tb_sweep -o sim_out *.v
vvp sim_out
```

To also write a waveform file for the sweep:

```bash
iverilog -DDUMP -s tb_sweep -o sim_out *.v
vvp sim_out
gtkwave waves_sweep.vcd
```

On Windows, GTKWave can be launched with `"C:\iverilog\gtkwave\bin\gtkwave.exe" waves_sweep.vcd`.

---

## Version Control

- `main` — current 5-stage pipeline with forwarding, stalling, `jal` redirected in IF, priority-based nested interrupts, exceptions, the machine-mode CSR set including the identification CSRs and the cycle/instret counters, and the shared AHB-Lite bus (instruction memory, data memory and default slave behind an address decoder)
- `pipeline` — development branch where forwarding/stalling, interrupt handling and the bus work were built and verified before merging

The original single-cycle implementation remains in the commit history prior to the pipeline merge.

---

## Author

**Shreyas Vaidya**

---

## License

This project is shared for **educational and learning purposes**.