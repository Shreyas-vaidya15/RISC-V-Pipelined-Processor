// Minimal riscv_test.h for the RV32I core (x30 = 99 end marker, x10 = verdict)
#ifndef _ENV_MINIMAL_H
#define _ENV_MINIMAL_H

#define TESTNUM x3

#define RVTEST_RV32U

#define RVTEST_CODE_BEGIN \
        .section .text.init; \
        .globl _start; \
_start:

#define RVTEST_CODE_END

// pass: x10 = 0, then park with the end marker
#define RVTEST_PASS \
        li x10, 0; \
        li x30, 99; \
1:      j 1b

// fail: x10 = (failing test number << 1) | 1, then park with the end marker
#define RVTEST_FAIL \
        slli x10, TESTNUM, 1; \
        ori x10, x10, 1; \
        li x30, 99; \
1:      j 1b

#define RVTEST_DATA_BEGIN .align 4;
#define RVTEST_DATA_END

#endif
