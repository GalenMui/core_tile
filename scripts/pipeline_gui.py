#!/usr/bin/env python3
"""View Sargantana pipeline snapshots from +pipeline_dump in the simulator."""

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tkinter as tk
from tkinter import ttk


ROOT = Path(__file__).resolve().parent.parent
MEM_TYPES = {"0": "—", "1": "LOAD", "2": "STORE", "3": "AMO", "4": "CMO", "5": "PREFETCH"}
ROW_KINDS = {"I": "IQ", "N": "RN", "F": "FL", "G": "GL", "L": "LSQ", "B": "SB", "P": "PMRQ"}


def run_program(binary, trace_path, rebuild=False):
    if not binary.is_file():
        raise FileNotFoundError(f"Missing executable: {binary}; build the test first")
    trace_path.parent.mkdir(parents=True, exist_ok=True)
    build = ["make", "-j4"]
    if rebuild:
        build.extend(["-W", "simulator/sim_top.sv"])
    subprocess.run([*build, "sim"], cwd=ROOT, check=True)
    args = ["./sim", f"+load={binary}", f"+pipeline_dump={trace_path}",
            "+max-cycles=100000"]
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    result.check_returncode()
    if "Run finished correctly" not in result.stdout:
        raise RuntimeError("Simulation did not finish correctly")


def parse_fields(parts):
    return dict(part.split("=", 1) for part in parts if "=" in part)


def symbols(binary):
    command = shutil.which("riscv64-unknown-elf-nm")
    if not command or binary is None or not binary.exists():
        return {}
    output = subprocess.run([command, str(binary)], check=True, capture_output=True, text=True).stdout
    wanted = {"_start", "main", "store_insn", "load_insn", "pass_exit"}
    found = {}
    for line in output.splitlines():
        words = line.split()
        if len(words) == 3 and words[2] in wanted:
            found[words[2]] = int(words[0], 16)
    return found


def disassembly(binary):
    result = {}
    if binary is None:
        return result
    dump = Path(str(binary) + ".dump")
    if dump.exists():
        for line in dump.read_text().splitlines():
            match = re.match(r"\s*([0-9a-f]+):\s+[0-9a-f]+\s+(.+)", line)
            if match:
                result[int(match[1], 16)] = match[2].strip()
    return result


class Trace:
    def __init__(self, path, binary=None):
        if not path.exists():
            raise FileNotFoundError(f"Missing {path}; run this script with --run first")
        self.path = path
        self.file = path.open("rb")
        self.offsets = []
        self.cycles = []
        self.focus = {}
        targets = symbols(binary)
        while True:
            offset = self.file.tell()
            line = self.file.readline()
            if not line:
                break
            if line.startswith(b"C\t"):
                parts = line.decode().rstrip().split("\t")
                self.offsets.append(offset)
                self.cycles.append(int(parts[1]))
                stage = parse_fields(parts[2:])
                if stage.get("id_valid") == "1":
                    pc = int(stage.get("id", "0"), 16)
                    for label, target in targets.items():
                        if label not in self.focus and pc == target:
                            self.focus[label] = len(self.offsets) - 1
        if not self.offsets:
            self.file.close()
            raise ValueError(f"No cycle records in {path}")
        start = self.focus.get("main", self.focus.get("_start", 0))
        end = self.focus.get("pass_exit", self.focus.get("load_insn", start))
        self.focus_start = max(0, start - 4)
        self.focus_end = min(len(self.offsets) - 1, max(start + 30, end + 50))

    def frame(self, index):
        index = max(0, min(index, len(self.offsets) - 1))
        self.file.seek(self.offsets[index])
        frame = {"cycle": self.cycles[index], "stages": {}, "meta": {},
                 "rows": {key: [] for key in ROW_KINDS.values()}}
        first = True
        while True:
            line = self.file.readline()
            if not line:
                break
            parts = line.decode().rstrip().split("\t")
            if parts[0] == "C":
                if not first:
                    break
                frame["stages"] = parse_fields(parts[2:])
                first = False
            elif parts[0] == "H":
                frame["meta"][parts[1]] = parse_fields(parts[2:])
            elif parts[0] in ROW_KINDS:
                row = parse_fields(parts[2:])
                row["slot"] = parts[1]
                frame["rows"][ROW_KINDS[parts[0]]].append(row)
        return frame


def hexfmt(raw):
    if raw is None:
        return "—"
    try:
        return f"0x{int(raw, 16):x}"
    except ValueError:
        return raw


class Viewer:
    def __init__(self, trace, binary=None):
        self.trace = trace
        self.asm = disassembly(binary)
        self.root = tk.Tk()
        self.root.title(f"Sargantana pipeline tables — {trace.path.name}")
        self.root.geometry("1500x930")
        self.root.configure(cursor="arrow")
        self.current = None
        self.full_run = tk.BooleanVar(value=False)
        self.step = tk.StringVar()
        self.status = tk.StringVar()
        self.slider = tk.DoubleVar()
        self.stage_labels = {}
        self.tables = {}
        self._layout()
        self.show(trace.focus.get("load_insn", trace.focus_start))
        self.root.mainloop()

    def _layout(self):
        top = ttk.Frame(self.root, padding=10)
        top.pack(fill="x")
        ttk.Label(top, text="Sargantana pipeline tables", font=("Sans", 18, "bold")).pack(anchor="w")
        ttk.Label(top, text="Rows are occupied hardware slots. Snapshots are taken on falling clock edges.").pack(anchor="w")
        controls = ttk.Frame(top)
        controls.pack(fill="x", pady=9)
        ttk.Button(controls, text="◀ Cycle", command=lambda: self.show(self.index - 1)).pack(side="left")
        ttk.Button(controls, text="Cycle ▶", command=lambda: self.show(self.index + 1)).pack(side="left", padx=4)
        for label, key in (("Start", "main" if "main" in self.trace.focus else "_start"),
                           ("Store", "store_insn"), ("Load", "load_insn")):
            button = ttk.Button(controls, text=label, command=lambda key=key: self.show(self.trace.focus[key]))
            if key not in self.trace.focus:
                button.state(["disabled"])
            button.pack(side="left", padx=2)
        ttk.Checkbutton(controls, text="Full run", variable=self.full_run, command=self._range_changed).pack(side="left", padx=10)
        scale = ttk.Scale(controls, from_=self.trace.focus_start, to=self.trace.focus_end,
                          variable=self.slider, command=lambda value: self.show(round(float(value))))
        scale.pack(side="left", fill="x", expand=True, padx=7)
        self.scale = scale
        ttk.Entry(controls, textvariable=self.step, width=8).pack(side="left")
        self.root.bind("<Return>", self._typed_step)
        ttk.Label(controls, textvariable=self.status).pack(side="left", padx=8)
        self.root.bind_all("<Left>", lambda _: self.show(self.index - 1))
        self.root.bind_all("<Right>", lambda _: self.show(self.index + 1))

        stage_frame = ttk.LabelFrame(self.root, text="Instruction flow", padding=8)
        stage_frame.pack(fill="x", padx=10, pady=(0, 8))
        for col, name in enumerate(("IF1", "IF2", "ID", "RR", "EXE", "WB")):
            variable = tk.StringVar(value="—")
            self.stage_labels[name.lower()] = variable
            ttk.Label(stage_frame, text=name, font=("Sans", 10, "bold")).grid(row=0, column=col, sticky="w", padx=9)
            ttk.Label(stage_frame, textvariable=variable, font=("Monospace", 10)).grid(row=1, column=col, sticky="w", padx=9)
            stage_frame.columnconfigure(col, weight=1)

        tabs = ttk.Notebook(self.root)
        tabs.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        front = ttk.Frame(tabs, padding=8)
        backend = ttk.Frame(tabs, padding=8)
        memory = ttk.Frame(tabs, padding=8)
        retire = ttk.Frame(tabs, padding=8)
        tabs.add(front, text="Front end")
        tabs.add(backend, text="Rename / issue")
        tabs.add(memory, text="Memory")
        tabs.add(retire, text="Retirement")

        self._table(front, "IQ", "Instruction queue · 16 slots",
                    ["slot", "pc", "asm", "id", "inst", "rs1", "rs2", "rd", "unit", "mem", "type"], 16)
        split = ttk.PanedWindow(backend, orient="horizontal")
        split.pack(fill="both", expand=True)
        ren = ttk.Frame(split)
        free = ttk.Frame(split)
        split.add(ren, weight=3)
        split.add(free, weight=2)
        self._table(ren, "RN", "Scalar rename map · 32 architectural registers",
                    ["slot", "phys", "ready"], 32)
        self._table(free, "FL", "Scalar free list · available physical registers",
                    ["slot", "phys"], 32)
        mem_tabs = ttk.Notebook(memory)
        mem_tabs.pack(fill="both", expand=True)
        for key, title, columns, height in (
            ("LSQ", "Load/store queue · 8 slots", ["slot", "pc", "asm", "id", "gl", "addr", "data", "mem", "size", "translated", "exception"], 8),
            ("SB", "Store buffer · 8 slots", ["slot", "pc", "asm", "id", "gl", "addr", "data", "mem", "size", "translated"], 8),
            ("PMRQ", "Pending memory requests · 16 slots", ["slot", "pc", "asm", "id", "gl", "tag", "finished", "addr", "data", "mem"], 16),
        ):
            pane = ttk.Frame(mem_tabs, padding=8)
            mem_tabs.add(pane, text=key)
            self._table(pane, key, title, columns, height)
        self._table(retire, "GL", "Graduation / retirement list · 32 slots",
                    ["slot", "ready", "pc", "asm", "id", "inst", "rs1", "rd", "prd", "old_prd", "mem", "type", "exception", "regwrite", "addr", "result"], 32)

    def _table(self, parent, key, title, columns, height):
        holder = ttk.LabelFrame(parent, text=title, padding=6)
        holder.pack(fill="both", expand=True)
        summary = tk.StringVar(value="—")
        ttk.Label(holder, textvariable=summary).pack(fill="x", pady=(0, 5))
        table = ttk.Treeview(holder, columns=columns, show="headings", height=height)
        table.configure(cursor="arrow")
        for column in columns:
            width = {"slot": 52, "pc": 115, "asm": 240, "id": 65, "inst": 95,
                     "addr": 115, "data": 115, "result": 115, "type": 72}.get(column, 78)
            table.heading(column, text=column.upper() if column in ("pc", "id", "gl") else column.replace("_", " ").title())
            table.column(column, width=width, minwidth=width, stretch=column == "asm")
        table.tag_configure("changed", background="#e9f5dd")
        table.pack(fill="both", expand=True, side="top")
        scrollbar = ttk.Scrollbar(holder, orient="horizontal", command=table.xview)
        scrollbar.pack(fill="x")
        table.configure(xscrollcommand=scrollbar.set)
        self.tables[key] = (summary, table, columns)

    def _typed_step(self, _):
        try:
            self.show(int(self.step.get()))
        except ValueError:
            pass

    def _range_changed(self):
        if self.full_run.get():
            self.scale.configure(from_=0, to=len(self.trace.offsets) - 1)
        else:
            self.scale.configure(from_=self.trace.focus_start, to=self.trace.focus_end)
            self.show(max(self.trace.focus_start, min(self.index, self.trace.focus_end)))

    def _value(self, key, row, column):
        raw = row.get(column)
        if column == "slot" and key == "RN":
            return "x" + str(raw)
        if column == "asm":
            try:
                return self.asm.get(int(row["pc"], 16), "—")
            except (KeyError, ValueError):
                return "—"
        if column in ("pc", "addr", "data", "result", "inst", "tag"):
            return hexfmt(raw)
        if column == "id":
            try:
                return str(int(raw, 16))
            except (TypeError, ValueError):
                return "—"
        if column == "mem":
            return MEM_TYPES.get(raw, raw or "—")
        if column in ("ready", "translated", "finished", "exception", "regwrite"):
            return "✓" if raw == "1" else "—"
        if column == "phys":
            return "p" + raw if raw is not None else "—"
        if column in ("prd", "old_prd"):
            return "p" + raw if raw is not None else "—"
        if column in ("rs1", "rs2", "rd"):
            return "x" + raw if raw is not None else "—"
        return raw or "—"

    def show(self, requested):
        low, high = (0, len(self.trace.offsets) - 1) if self.full_run.get() else (self.trace.focus_start, self.trace.focus_end)
        index = max(low, min(high, requested))
        if self.current is not None and index == self.index:
            return
        previous = self.current
        self.index = index
        frame = self.trace.frame(index)
        self.current = frame
        self.slider.set(index)
        self.step.set(str(index))
        self.status.set(f"Cycle {frame['cycle']} · step {index + 1}/{len(self.trace.offsets)}")
        for stage, variable in self.stage_labels.items():
            valid = frame["stages"].get(f"{stage}_valid") == "1"
            pc = hexfmt(frame["stages"].get(stage))
            variable.set(f"{pc}\n{'valid' if valid else 'idle'}")
        for key, (summary, table, columns) in self.tables.items():
            meta = frame["meta"].get(key, {})
            summary.set("  ·  ".join(f"{name.replace('_', ' ')}: {value}" for name, value in meta.items()) or "No summary")
            children = table.get_children()
            if children:
                table.delete(*children)
            old_rows = {row["slot"]: row for row in previous["rows"][key]} if previous else {}
            for row in frame["rows"][key]:
                values = [self._value(key, row, column) for column in columns]
                table.insert("", "end", values=values,
                             tags=("changed",) if old_rows.get(row["slot"]) != row else ())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace", type=Path, default=ROOT / "benchmarks/pipeline.tsv",
                        help="snapshot file to read or generate (default: benchmarks/pipeline.tsv)")
    parser.add_argument("--binary", type=Path, help="ELF executable; optional when viewing an existing trace")
    parser.add_argument("--run", action="store_true", help="build the simulator and run --binary before opening")
    parser.add_argument("--rebuild", action="store_true", help="rebuild the simulator before running")
    args = parser.parse_args()
    if args.run and args.binary is None:
        parser.error("--run requires --binary; build the test with the existing project workflow first")
    if args.rebuild and not args.run:
        parser.error("--rebuild requires --run")
    binary = args.binary.resolve() if args.binary else None
    trace_path = args.trace.resolve()
    if args.run:
        run_program(binary, trace_path, args.rebuild)
    trace = Trace(trace_path, binary)
    try:
        Viewer(trace, binary)
    finally:
        trace.file.close()


if __name__ == "__main__":
    main()
