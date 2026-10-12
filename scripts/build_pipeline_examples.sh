#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
common="$root_dir/riscv-tests/benchmarks/common"
mkdir -p "$root_dir/benchmarks"

case "${1:-}" in
    c)
        binary="$root_dir/benchmarks/pipeline_c.riscv"
        source_file="${2:-$root_dir/tests/pipeline_c.c}"
        riscv64-unknown-elf-gcc \
            -march=rv64g_zba_zbb_zbs -mabi=lp64d -mcmodel=medany \
            -static -nostdlib -nostartfiles -std=gnu99 -O2 \
            -DPREALLOCATE=1 -ffast-math -fno-common -fno-builtin-printf \
            -fno-tree-loop-distribute-patterns \
            -I "$root_dir/riscv-tests/env" -I "$common" \
            "$source_file" "$common/crt.S" "$common/syscalls.c" \
            -T "$common/test.ld" -lm -lgcc -o "$binary"
        ;;
    asm)
        binary="$root_dir/benchmarks/raw_pipeline.riscv"
        source_file="${2:-$root_dir/tests/raw_pipeline.S}"
        riscv64-unknown-elf-gcc \
            -march=rv64imafd -mabi=lp64d -mcmodel=medany -mno-relax \
            -static -nostdlib -nostartfiles -fno-pic \
            -T "$common/test.ld" -o "$binary" "$source_file"
        ;;
    *)
        echo "Usage: $0 {c|asm} [source-file]" >&2
        exit 2
        ;;
esac

riscv64-unknown-elf-objdump \
    --disassemble-all --disassemble-zeroes \
    --section=.text --section=.text.startup --section=.text.init --section=.data \
    "$binary" > "$binary.dump"
echo "Built ${binary#"$root_dir/"}"
