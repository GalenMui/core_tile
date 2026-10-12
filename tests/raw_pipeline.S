// Six test instructions before the parking loop: store 1, load it, send it to tohost.
// The data word starts at 3, so a missing store produces a failure code.
    .option norvc
    .section .text.init, "ax", @progbits
    .globl _start
_start:
.Ldata_base:
    auipc t0, %pcrel_hi(test_word)
    li    t1, 1
    .globl store_insn
store_insn:
    sd    t1, %pcrel_lo(.Ldata_base)(t0)
    .globl load_insn
load_insn:
    ld    t2, %pcrel_lo(.Ldata_base)(t0)
.Ltohost_base:
    auipc t3, %pcrel_hi(tohost)
    .globl pass_exit
pass_exit:
    sd    t2, %pcrel_lo(.Ltohost_base)(t3)
1:  j    1b

    .section .data, "aw", @progbits
    .align 3
test_word:
    .dword 3

    .section .tohost, "aw", @progbits
    .globl tohost
    .align 3
tohost:
    .dword 0
