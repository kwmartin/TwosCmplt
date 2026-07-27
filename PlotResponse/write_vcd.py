# write_vcd.py
import sys, json
from vcd import VCDWriter  # pyvcd

def main():
    # cfg = json.loads(sys.stdin.read())

    with open('vcd_debug_input.json', 'r') as fp:
        cfgstr = fp.read()
    cfg = json.loads(cfgstr)
    out_path = cfg["out"]
    timescale = cfg.get("timescale", "1 ps")
    signals = cfg["signals"]  # [{scope,name,type,size,changes:[(t,val),...]}]

    with open(out_path, "w") as f, VCDWriter(f, timescale=timescale, date="today") as writer:
        # 1. Register all variables
        vars: dict[str, object] = {}
        for s in signals:
            v = writer.register_var(s["scope"], s["name"], s["type"], size=s["size"])
            vars[s["name"]] = v

        # 2. Flatten all changes with their var object
        all_changes: list[tuple[int, object, str, str]] = []
        for s in signals:
            name = s["name"]
            v = vars[name]
            for t, val in s["changes"]:
                all_changes.append((t, name, v, val))

        # 3. Sort by time (then name for determinism if you like)
        all_changes.sort(key=lambda x: (x[0], x[1]))

        # 4. Apply in time order
        for t, name, v, val in all_changes:
            print("CHANGE", name, t, val, file=sys.stderr)
            writer.change(v, t, val)

if __name__ == "__main__":
    main()
