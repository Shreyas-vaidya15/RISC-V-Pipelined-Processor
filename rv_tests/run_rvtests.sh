#!/bin/bash
# Build and run the rv32ui riscv-tests on the core. Usage: ./rv_tests/run_rvtests.sh
# Needs: iverilog, riscv64-unknown-elf-gcc, a clone of riscv-tests (default ~/riscv-tests, or set RISCV_TESTS)
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
RT="${RISCV_TESTS:-$HOME/riscv-tests}"
OUT=/tmp/rvt_build
rm -rf "$OUT"; mkdir -p "$OUT"

# 1. simulator: repo-root RTL, minus the testbenches and the sweep instruction image, plus the hex-loading instruction memory
RTL=""
for f in "$ROOT"/*.v; do
  b=$(basename "$f")
  case "$b" in tb*|instruction_memory.v) continue;; esac
  RTL="$RTL $f"
done
iverilog -s tb_rv -o "$OUT/sim_rv" $RTL "$HERE/inst_memory_hex.v" "$HERE/tb_rv.v" || exit 1

# 2. assemble + link every rv32ui test except fence_i and ma_data, then split into text/data hex
count=0
for s in "$RT"/isa/rv32ui/*.S; do
  n=$(basename "$s" .S)
  case "$n" in fence_i|ma_data) continue;; esac
  riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
      -I "$HERE" -I "$RT/isa/macros/scalar" -T "$HERE/link_test.ld" "$s" -o "$OUT/$n.elf" || exit 1
  riscv64-unknown-elf-objcopy -O verilog --only-section=.text "$OUT/$n.elf" "$OUT/$n.text.hex"
  riscv64-unknown-elf-objcopy -O verilog --only-section=.data "$OUT/$n.elf" "$OUT/$n.data.hex"
  sed -i 's/^@00010000/@00000000/' "$OUT/$n.data.hex"
  count=$((count+1))
done
echo "TESTS BUILT=$count"

# 3. run at 0, 1, 2 wait states
rc=0
for w in 0 1 2; do
  p=0; f=0
  for t in "$OUT"/*.text.hex; do
    n=$(basename "$t" .text.hex)
    r=$(vvp "$OUT/sim_rv" +hex="$t" +data="$OUT/$n.data.hex" +wait=$w | grep "RV RESULT")
    if echo "$r" | grep -q PASS; then p=$((p+1)); else f=$((f+1)); rc=1; echo "== wait=$w $n: $r"; fi
  done
  echo "WAIT=$w PASS=$p FAIL=$f"
done
exit $rc
