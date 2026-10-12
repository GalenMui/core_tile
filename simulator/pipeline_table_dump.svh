// Optional simulation only snapshots of the major pipeline structures
// Enable with +pipeline_dump=path/to/pipeline.tsv.
`define PIPE_DP DUT.subtile_inst.sargantana_inst.datapath_inst
`define PIPE_MEM `PIPE_DP.exe_stage_inst.mem_unit_inst
`define PIPE_LSQ `PIPE_MEM.load_store_queue_inst
`define PIPE_SB `PIPE_LSQ.store_buffer_inst
`define PIPE_PMRQ `PIPE_MEM.pending_mem_req_queue_inst

integer pipeline_fd;
string pipeline_path;
initial begin
    pipeline_fd = 0;
    if ($value$plusargs("pipeline_dump=%s", pipeline_path)) begin
        pipeline_fd = $fopen(pipeline_path, "w");
        if (pipeline_fd == 0) $fatal(1, "Could not open pipeline dump: %s", pipeline_path);
    end
end

// A falling-edge sample sees the registered state produced by the preceding rising edge.
always @(negedge tb_clk) begin : dump_pipeline_tables
    integer i;
    if (pipeline_fd != 0 && tb_rstn) begin
        $fdisplay(pipeline_fd, "C\t%0d\tif1=%h\tif1_valid=%0d\tif2=%h\tif2_valid=%0d\tid=%h\tid_valid=%0d\trr=%h\trr_valid=%0d\texe=%h\texe_valid=%0d\twb=%h\twb_valid=%0d",
            cycles, `PIPE_DP.pc_if1, `PIPE_DP.valid_if1, `PIPE_DP.pc_if2, `PIPE_DP.valid_if2,
            `PIPE_DP.pc_id, `PIPE_DP.valid_id, `PIPE_DP.pc_rr, `PIPE_DP.valid_rr,
            `PIPE_DP.pc_exe, `PIPE_DP.valid_exe, `PIPE_DP.pc_wb, `PIPE_DP.valid_wb);

        $fdisplay(pipeline_fd, "H\tIQ\thead=%0d\ttail=%0d\tcount=%0d\tfull=%0d",
            `PIPE_DP.instruction_queue_inst.head, `PIPE_DP.instruction_queue_inst.tail,
            `PIPE_DP.instruction_queue_inst.num, `PIPE_DP.instruction_queue_inst.full_o);
        for (i = 0; i < 16; i++) begin
            if (((i + 16 - int'(`PIPE_DP.instruction_queue_inst.head)) % 16) < int'(`PIPE_DP.instruction_queue_inst.num))
                $fdisplay(pipeline_fd, "I\t%0d\tpc=%h\tid=%h\tinst=%h\trs1=%0d\trs2=%0d\trd=%0d\tunit=%0d\tmem=%0d\ttype=%0d",
                    i, `PIPE_DP.instruction_queue_inst.instruction_buffer[i].instr.pc,
                    `PIPE_DP.instruction_queue_inst.instruction_buffer[i].instr.id,
                    `PIPE_DP.instruction_queue_inst.instruction_buffer[i].instr.inst,
                    `PIPE_DP.instruction_queue_inst.instruction_buffer[i].instr.rs1,
                    `PIPE_DP.instruction_queue_inst.instruction_buffer[i].instr.rs2,
                    `PIPE_DP.instruction_queue_inst.instruction_buffer[i].instr.rd,
                    `PIPE_DP.instruction_queue_inst.instruction_buffer[i].instr.unit,
                    `PIPE_DP.instruction_queue_inst.instruction_buffer[i].instr.mem_type,
                    `PIPE_DP.instruction_queue_inst.instruction_buffer[i].instr.instr_type);
        end

        $fdisplay(pipeline_fd, "H\tRN\tversion=%0d\tcheckpoints=%0d",
            `PIPE_DP.rename_table_inst.version_head_q, `PIPE_DP.rename_table_inst.num_checkpoints_q);
        for (i = 0; i < 32; i++) begin
            $fdisplay(pipeline_fd, "N\t%0d\tphys=%0d\tready=%0d",
                i, `PIPE_DP.rename_table_inst.register_table_q[i][`PIPE_DP.rename_table_inst.version_head_q],
                `PIPE_DP.rename_table_inst.ready_table_q[i][`PIPE_DP.rename_table_inst.version_head_q]);
        end

        $fdisplay(pipeline_fd, "H\tFL\tversion=%0d\thead=%0d\ttail=%0d\tcount=%0d",
            `PIPE_DP.free_list_inst.version_head,
            `PIPE_DP.free_list_inst.head[`PIPE_DP.free_list_inst.version_head],
            `PIPE_DP.free_list_inst.tail,
            `PIPE_DP.free_list_inst.num_registers[`PIPE_DP.free_list_inst.version_head]);
        for (i = 0; i < 32; i++) begin
            if (((i + 32 - int'(`PIPE_DP.free_list_inst.head[`PIPE_DP.free_list_inst.version_head])) % 32)
                    < int'(`PIPE_DP.free_list_inst.num_registers[`PIPE_DP.free_list_inst.version_head]))
                $fdisplay(pipeline_fd, "F\t%0d\tphys=%0d",
                    i, `PIPE_DP.free_list_inst.register_table[i]);
        end

        $fdisplay(pipeline_fd, "H\tGL\thead=%0d\ttail=%0d\tcount=%0d\tfull=%0d",
            `PIPE_DP.graduation_list_inst.head, `PIPE_DP.graduation_list_inst.tail,
            `PIPE_DP.graduation_list_inst.num, `PIPE_DP.graduation_list_inst.full_o);
        for (i = 0; i < 32; i++) begin
            if (((i + 32 - int'(`PIPE_DP.graduation_list_inst.head)) % 32) < int'(`PIPE_DP.graduation_list_inst.num))
                $fdisplay(pipeline_fd, "G\t%0d\tready=%0d\tpc=%h\tid=%h\tinst=%h\trs1=%0d\trd=%0d\tprd=%0d\told_prd=%0d\tmem=%0d\ttype=%0d\texception=%0d\tregwrite=%0d\taddr=%h\tresult=%h",
                    i, `PIPE_DP.graduation_list_inst.valid_bit_q[i],
                    `PIPE_DP.graduation_list_inst.entries_q[i].pc,
                    `PIPE_DP.graduation_list_inst.entries_q[i].id,
                    `PIPE_DP.graduation_list_inst.entries_q[i].inst,
                    `PIPE_DP.graduation_list_inst.entries_q[i].rs1,
                    `PIPE_DP.graduation_list_inst.entries_q[i].rd,
                    `PIPE_DP.graduation_list_inst.entries_q[i].prd,
                    `PIPE_DP.graduation_list_inst.entries_q[i].old_prd,
                    `PIPE_DP.graduation_list_inst.entries_q[i].mem_type,
                    `PIPE_DP.graduation_list_inst.entries_q[i].instr_type,
                    `PIPE_DP.graduation_list_inst.entries_q[i].ex_valid,
                    `PIPE_DP.graduation_list_inst.entries_q[i].regfile_we,
                    `PIPE_DP.graduation_list_inst.entries_q[i].addr,
                    `PIPE_DP.graduation_list_inst.entries_q[i].result[63:0]);
        end

        $fdisplay(pipeline_fd, "H\tLSQ\thead=%0d\ttail=%0d\tcount=%0d\tto_translate=%0d\ttlb_tail=%0d",
            `PIPE_LSQ.head, `PIPE_LSQ.tail, int'(`PIPE_LSQ.num_to_exe) + int'(`PIPE_LSQ.num_to_translate),
            `PIPE_LSQ.num_to_translate, `PIPE_LSQ.tlb_tail);
        for (i = 0; i < 8; i++) begin
            if (((i + 8 - int'(`PIPE_LSQ.head)) % 8)
                    < (int'(`PIPE_LSQ.num_to_exe) + int'(`PIPE_LSQ.num_to_translate)))
                $fdisplay(pipeline_fd, "L\t%0d\tpc=%h\tid=%h\tgl=%0d\taddr=%h\tdata=%h\tmem=%0d\tsize=%0d\ttranslated=%0d\texception=%0d",
                    i, `PIPE_LSQ.control_table[i].instr.pc, `PIPE_LSQ.control_table[i].instr.id,
                    `PIPE_LSQ.control_table[i].gl_index, `PIPE_LSQ.control_table[i].data_rs1,
                    `PIPE_LSQ.control_table[i].data_rs2[63:0],
                    `PIPE_LSQ.control_table[i].instr.mem_type, `PIPE_LSQ.control_table[i].instr.mem_size,
                    `PIPE_LSQ.control_table[i].translated, `PIPE_LSQ.control_table[i].ex.valid);
        end

        $fdisplay(pipeline_fd, "H\tSB\thead=%0d\ttail=%0d\tcount=%0d\tfull=%0d",
            `PIPE_SB.head, `PIPE_SB.tail, `PIPE_SB.num, `PIPE_SB.full_o);
        for (i = 0; i < 8; i++) begin
            if (`PIPE_SB.valid_table[i])
                $fdisplay(pipeline_fd, "B\t%0d\tpc=%h\tid=%h\tgl=%0d\taddr=%h\tdata=%h\tmem=%0d\tsize=%0d\ttranslated=%0d",
                    i, `PIPE_SB.instruction_table[i].instr.pc, `PIPE_SB.instruction_table[i].instr.id,
                    `PIPE_SB.instruction_table[i].gl_index, `PIPE_SB.instruction_table[i].data_rs1,
                    `PIPE_SB.instruction_table[i].data_rs2[63:0],
                    `PIPE_SB.instruction_table[i].instr.mem_type, `PIPE_SB.instruction_table[i].instr.mem_size,
                    `PIPE_SB.instruction_table[i].translated);
        end

        $fdisplay(pipeline_fd, "H\tPMRQ\thead=%0d\ttail=%0d\tcount=%0d\tfull=%0d",
            `PIPE_PMRQ.head, `PIPE_PMRQ.tail, `PIPE_PMRQ.num, `PIPE_PMRQ.full_o);
        for (i = 0; i < 16; i++) begin
            if (((i + 16 - int'(`PIPE_PMRQ.head)) % 16) < int'(`PIPE_PMRQ.num))
                $fdisplay(pipeline_fd, "P\t%0d\tpc=%h\tid=%h\tgl=%0d\ttag=%h\tfinished=%0d\taddr=%h\tdata=%h\tmem=%0d",
                    i, `PIPE_PMRQ.instruction_table[i].instr.pc, `PIPE_PMRQ.instruction_table[i].instr.id,
                    `PIPE_PMRQ.instruction_table[i].gl_index, `PIPE_PMRQ.tag_table[i],
                    `PIPE_PMRQ.finish_bit_table[i], `PIPE_PMRQ.instruction_table[i].data_rs1,
                    `PIPE_PMRQ.instruction_table[i].data_rs2[63:0],
                    `PIPE_PMRQ.instruction_table[i].instr.mem_type);
        end
    end
end

final begin
    if (pipeline_fd != 0) $fclose(pipeline_fd);
end

`undef PIPE_DP
`undef PIPE_MEM
`undef PIPE_LSQ
`undef PIPE_SB
`undef PIPE_PMRQ
