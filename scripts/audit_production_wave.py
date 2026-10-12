"""Independently audit the selected ModelSim VCD and crop its turnaround."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / "reports/gpio_production.vcd"
lines = source.read_text(encoding="ascii").splitlines()
boundary = lines.index("$enddefinitions $end") + 1
header = lines[:boundary]
scope = []
symbols = {}
widths = {}
for line in header:
    words = line.split()
    if words[:1] == ["$scope"]:
        scope.append(words[2])
    elif words[:1] == ["$upscope"]:
        scope.pop()
    elif words[:1] == ["$var"]:
        symbols[".".join(scope + [words[4]])] = words[3]
        widths[words[3]] = int(words[2])
if not any("1ps" in line for line in header):
    raise ValueError("This audit expects the production ModelSim 1ps timebase")

events = []
timestamp = 0
for line in lines[boundary:]:
    if line.startswith("#"):
        timestamp = int(line[1:])
    elif line and line[0] in "01xXzZ":
        events.append((timestamp, line[1:], line[0]))
    elif line and line[0] in "bB":
        value, symbol = line[1:].split()
        events.append((timestamp, symbol, value))

prefix = "tb_gpio_production.dut."
drive_symbol = symbols[prefix + "drive_en"]
drive_changes = []
last_mask = None
for timestamp, symbol, value in events:
    if symbol == drive_symbol:
        if any(char not in "01" for char in value):
            raise AssertionError("Unknown drive mask")
        mask = int(value, 2)
        if mask not in (0, 1, 2):
            raise AssertionError("Unsafe/nonselected/multiple output enable")
        if mask != last_mask:
            drive_changes.append((timestamp, mask))
            last_mask = mask
assert [mask for _, mask in drive_changes] == [0, 1, 0, 2, 0], drive_changes
ab_start, ab_end, ba_start, ba_end = [timestamp for timestamp, _ in drive_changes[1:]]
symbol_ps = 1_000_000_000
settle_ps = 100_000_000
assert ab_end - ab_start == 100 * symbol_ps
assert ba_end - ba_start == 100 * symbol_ps
assert ba_start - ab_end == settle_ps

sampling = {}
for suffix, direction_start in (("ab", ab_start), ("ba", ba_start)):
    symbol = symbols[prefix + "samples_" + suffix]
    comparisons = []
    count = 0
    for timestamp, event_symbol, value in events:
        if event_symbol != symbol:
            continue
        new_count = int(value, 2)
        if new_count > count:
            assert new_count == count + 1
            comparisons.append(timestamp)
        count = new_count
    assert count == 100 and len(comparisons) == 100
    offsets = [(time - direction_start) % symbol_ps for time in comparisons]
    assert all(offset == settle_ps for offset in offsets), offsets[:3]
    assert all(second - first == symbol_ps for first, second in zip(comparisons, comparisons[1:]))
    sampling[suffix] = {"samples": count, "settle_ns": min(offsets) // 1000, "symbol_ns": symbol_ps // 1000}

# Preserve all selected signal values at the crop boundary, then shift time
# origin. The original VCD remains unchanged; crop metadata records its origin.
crop_start = ab_end - 2 * symbol_ps
crop_end = ba_start + 2 * symbol_ps
initial_values = {}
for timestamp, symbol, value in events:
    if timestamp < crop_start:
        initial_values[symbol] = value
def value_line(symbol, value):
    return value + symbol if widths[symbol] == 1 else "b" + value + " " + symbol
cropped = header + ["#0", "$dumpvars"] + [value_line(symbol, value) for symbol, value in initial_values.items()] + ["$end"]
last_timestamp = None
for timestamp, symbol, value in events:
    if crop_start <= timestamp <= crop_end:
        relative_time = timestamp - crop_start
        if relative_time != last_timestamp:
            cropped.append("#" + str(relative_time))
            last_timestamp = relative_time
        cropped.append(value_line(symbol, value))
crop_path = ROOT / "reports/gpio_turnaround.vcd"
crop_path.write_text("\n".join(cropped) + "\n", encoding="ascii")
audit = {"ok": True, "source": source.name, "timebase": "1ps", "drive_masks": [mask for _, mask in drive_changes],
         "direction_duration_ns": [(ab_end - ab_start) // 1000, (ba_end - ba_start) // 1000],
         "high_z_gap_ns": (ba_start - ab_end) // 1000, "sampling": sampling,
         "crop_start_absolute_ns": crop_start // 1000, "crop_end_absolute_ns": crop_end // 1000,
         "cropped_vcd": crop_path.name}
(ROOT / "reports/production_wave_audit.json").write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")
print(json.dumps(audit, indent=2))
