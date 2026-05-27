# write_vcd.py
import sys, json, os, argparse
from vcd import VCDWriter  # pyvcd

DUMP_DIR = "/home/Dropbox/programming/Swift/TwosCmplt/Resources/DumpDir"
VCD_DIR  = "/home/Dropbox/programming/Swift/TwosCmplt/Resources/VCDFiles"


def write_vcd(base_name: str,
              dump_dir: str = DUMP_DIR,
              vcd_dir: str = VCD_DIR) -> None:
    """Read {dump_dir}/{base_name}.json and write {vcd_dir}/{base_name}.vcd."""
    input_path  = os.path.join(dump_dir, base_name + ".json")
    output_path = os.path.join(vcd_dir,  base_name + ".vcd")

    with open(input_path) as f:
        cfg = json.load(f)

    timescale = cfg.get("timescale", "1 ps")
    signals   = cfg["signals"]  # [{scope, name, type, size, changes: [[t, val], ...]}]

    with open(output_path, "w") as f, VCDWriter(f, timescale=timescale, date="today") as writer:
        vars: dict[str, object] = {}
        for s in signals:
            v = writer.register_var(s["scope"], s["name"], s["type"], size=s["size"])
            vars[s["name"]] = v

        all_changes: list[tuple[int, str, object, int]] = []
        for s in signals:
            name = s["name"]
            v = vars[name]
            for t, val in s["changes"]:
                all_changes.append((t, name, v, val))

        all_changes.sort(key=lambda x: (x[0], x[1]))

        for t, name, v, val in all_changes:
            # print("CHANGE", name, t, val, file=sys.stderr)
            writer.change(v, t, val)

    # print(f"VCD written to {output_path}", file=sys.stderr)
    aa=0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert a JSON signal dump to VCD format.")
    parser.add_argument("base_name", help="Base name (no extension) shared by input .json and output .vcd")
    parser.add_argument("--dump-dir", default=DUMP_DIR, help="Directory containing the input JSON file")
    parser.add_argument("--vcd-dir",  default=VCD_DIR,  help="Directory for the output VCD file")
    args = parser.parse_args()

    write_vcd(args.base_name, args.dump_dir, args.vcd_dir)
