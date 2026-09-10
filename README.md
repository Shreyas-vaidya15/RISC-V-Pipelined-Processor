# RV32I RISC-V Processor (Single-Cycle → 5-Stage Pipeline)

A **32-bit RV32I RISC-V Processor** implemented in **Verilog HDL**, originally built as a single-cycle design and since converted into a **5-stage pipelined implementation** (IF → ID → EX → MEM → WB) with full data forwarding and load-use stall handling.

This project implements the **RV32I Base Integer Instruction Set Architecture (ISA)** using a modular datapath. The design is divided into independent RTL modules, making it easier to understand, verify, and extend into more advanced processor architectures.

---

## Features

- 32-bit RV32I architecture
- **5-stage pipelined datapath**: IF, ID, EX, MEM, WB
- Dedicated pipeline registers: `IF_ID_reg`, `ID_EX_reg`, `EX_MEM_reg`, `MEM_WB_reg`
- **Full data forwarding**: `forwarding_unit` + `forward_mux` resolve RAW hazards from both EX/MEM and MEM/WB, covering ALU-operand forwarding, store-data forwarding, store-address forwarding, and jalr base-register forwarding
- **Load-use stall detection**: `stall_unit` inserts a one-cycle bubble (PC hold, `IF_ID_reg` hold, `ID_EX_reg` bubble) when a load's result is needed by the immediately following instruction
- **Branch/jump flush**: `IF_ID_reg` and `ID_EX_reg` flush on a taken branch or jump, resolved in EX
- Modular RTL design, one module per pipeline stage
- Separate control decoding (`main_decoder`, `alu_decoder`) inside the ID stage
- Arithmetic Logic Unit (ALU)
- Register File with same-cycle write-read bypass
- Program Counter (PC) with branch/jump redirect muxing
- Instruction Memory
- Data Memory with byte/halfword/word width control and sign/zero-extended loads
- Sign Extension Unit
- Multiplexers for datapath control
- Verilog testbench for functional verification

---

## Project Structure

```text
.
├── alu.v
├── alu_decoder.v
├── alu_mux.v
├── control_path.v          # single-cycle control path (legacy, unused by pipeline top)
├── data_memory.v
├── data_path.v              # single-cycle datapath (legacy, unused by pipeline top)
├── instruction_memory.v
├── main_decoder.v
├── pc.v
├── pc_mux.v
├── pc_plus_4.v
├── pc_target.v
├── register_file.v
├── result_mux.v
├── riscv.v                  # single-cycle top wrapper (legacy)
├── sign_extender.v
├── IF_stage.v
├── IF_ID_reg.v
├── ID_stage.v
├── ID_EX_reg.v
├── EX_stage.v
├── EX_MEM_reg.v
├── MEM_stage.v
├── MEM_WB_reg.v
├── forwarding_unit.v        # RAW hazard detection (EX/MEM, MEM/WB)
├── forward_mux.v            # 3-input operand select (regfile / EX-MEM / MEM-WB)
├── stall_unit.v             # load-use hazard detection
├── top.v                    # pipeline top module
├── tb.v
├── .gitignore
└── README.md
```

---

## Pipeline Architecture

```text
IF_stage → IF_ID_reg → ID_stage → ID_EX_reg → EX_stage → EX_MEM_reg → MEM_stage → MEM_WB_reg → result_mux → (write-back into register file)
```

- **IF**: PC register, PC+4 adder, branch/jump target mux, instruction memory
- **ID**: register file read (with same-cycle write bypass), immediate sign-extension, control signal decode (`main_decoder`, `alu_decoder`)
- **EX**: ALU, ALU-source mux, PC-target adder, branch decision, `jalr`/`auipc` muxing — operands arrive pre-resolved via `forward_mux` before reaching this stage
- **MEM**: data memory access, load sign/zero-extension based on `Funct3`
- **WB**: result mux (ALU result / memory data / PC+4) selects final write-back value; no dedicated WB module — `result_mux` is instantiated directly in `top.v`

### Hazard Control

- **Forwarding**: `forwarding_unit` compares the ID/EX-stage instruction's `rs1`/`rs2` against `EX_MEM_reg`'s and `MEM_WB_reg`'s destination register, with EX/MEM given priority when both match (most recent producer wins). Two 3-input `forward_mux` instances (`ForwardA`/`ForwardB`) select between the register-file value, the EX/MEM candidate, and the MEM/WB candidate. The EX/MEM candidate is `ALUResult` for most instructions but switches to `PC+4` for `jal`/`jalr`. The resolved rs2 value (`ForwardedRD2`) feeds both the ALU's B-input and `EX_MEM_reg.RD2_In`, covering both ALU-operand and store-data forwarding with one path.
- **Stalling**: `stall_unit` detects when the instruction currently in ID/EX is a load whose destination matches either source register of the instruction currently in ID (the 0-gap load-use case forwarding can't resolve, since `ReadData` doesn't exist until MEM). On a hit, it holds the PC and `IF_ID_reg`, and forces a one-cycle bubble into `ID_EX_reg`.
- **Flush**: a taken branch or jump resolves in EX and asserts `PCSrc`, which flushes the two younger, wrong-path instructions currently sitting in `IF_ID_reg` and `ID_EX_reg`.

---

## Supported Instructions

All **37 RV32I base instructions** have been individually verified through the pipeline:

| Category | Instructions |
|---|---|
| R-type ALU | `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and` |
| I-type ALU | `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai` |
| Loads | `lb`, `lh`, `lw`, `lbu`, `lhu` |
| Stores | `sb`, `sh`, `sw` |
| Branches | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu` |
| Jumps | `jal`, `jalr` |
| Upper immediate | `lui`, `auipc` |

> Verification method: instruction functionality was first exercised via hazard-free (NOP-padded) sequences; forwarding and stalling were then verified against a dedicated set of hazard-adversarial sequences written directly into `instruction_memory.v` (0-gap and 1-gap RAW hazards, double-hazard priority, store data/address forwarding, jalr base forwarding, all load-use stall variants, and multi-hazard interaction cases). See inline comments in `instruction_memory.v` for expected register values per test.

---

## Verification Status

- ✅ All 37 RV32I instructions functionally correct in isolation (hazard-free sequencing)
- ✅ Pipeline register timing confirmed (4-cycle IF→WB latency)
- ✅ Branch/jump redirect target computation confirmed correct
- ✅ x0 write-immunity confirmed
- ✅ Signed vs. unsigned comparison/shift correctness confirmed (`slt` vs `sltu`, `sra` vs `srl`, `blt` vs `bltu`, etc.)
- ✅ EX/MEM and MEM/WB forwarding confirmed for ALU-operand, store-data, store-address, and jalr-base-register hazards, including EX/MEM-vs-MEM/WB priority resolution
- ✅ Load-use stalling confirmed (rs1-only, rs2-only, both-operand, x0-guard, store-data-consumer, and back-to-back stall cases)
- ✅ Branch/jump flush confirmed — no wrong-path instruction reaches write-back

---

## Development Environment

- Visual Studio Code
- GitHub Desktop

---

## Tools Used

- Verilog HDL
- Icarus Verilog
- GTKWave
- Git
- GitHub

---

## Requirements

- Icarus Verilog
- GTKWave

---

## Running the Simulation

### Compile the design

```bash
iverilog -o sim_out *.v
```

### Run the simulation

```bash
vvp sim_out
```

### View the waveform

Windows:

```bash
"C:\iverilog\gtkwave\bin\gtkwave.exe" waves.vcd
```

If GTKWave is available in your system PATH:

```bash
gtkwave waves.vcd
```

---

## Future Improvements

- BTFNT branch prediction with a 2-bit saturating counter predictor
- AXI-Lite / AHB-Lite bus interface for SoC integration
- cocotb-based verification environment
- Migrate the design to SystemVerilog

---

## Version Control

This project is version-controlled using **Git** and hosted on **GitHub**.

- `main` — tracks the current 5-stage pipeline implementation with forwarding and stalling
- `pipeline` — development branch where forwarding/stalling were built and verified before merging to `main`

The original single-cycle implementation remains available in the commit history prior to the pipeline merge into `main`.

---

## Author

**Shreyas Vaidya**

---

## License

This project is shared for **educational and learning purposes**.
