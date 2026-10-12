"""Summarize saved UART results; stdlib only, no serial/hardware access."""
import argparse
import csv
import re
from pathlib import Path

HEADER = re.compile(r"PAIR=(\d{2}) J8=(\d{2})/(\d{2}) MODE=(SMOKE |NORMAL|STRESS) ABORTED=([01])")
DIRECTION = re.compile(r"(\d{2})->(\d{2}): (PASS|INTERMITTENT|FAIL|INVALID)\s+errors=(\d{10})/(\d{10}) MAX10K=(\d{10})")
GOALS = {"SMOKE": 100, "NORMAL": 10000, "STRESS": 100000}
FIELDS = ["report_index", "pair", "j8_a", "j8_b", "mode", "aborted", "ab_status", "ab_errors", "ab_samples", "ab_max10k", "ba_status", "ba_errors", "ba_samples", "ba_max10k", "conclusion"]


def read_runs(text):
    """Incomplete frames remain INVALID rather than being counted as PASS."""
    runs = []
    current = None
    for line in text.splitlines():
        header = HEADER.search(line)
        if header:
            pair, pin_a, pin_b, mode, aborted = header.groups()
            current = dict.fromkeys(FIELDS, "")
            current.update(report_index=len(runs) + 1, pair=int(pair), j8_a=int(pin_a), j8_b=int(pin_b),
                           mode=mode.strip(), aborted=int(aborted), conclusion="INVALID_INCOMPLETE")
            runs.append(current)
            continue
        direction = DIRECTION.search(line)
        if not direction or current is None:
            continue
        source, dest, status, errors, samples, max10k = direction.groups()
        endpoint = (int(source), int(dest))
        if endpoint == (current["j8_a"], current["j8_b"]):
            prefix = "ab"
        elif endpoint == (current["j8_b"], current["j8_a"]):
            prefix = "ba"
        else:
            current["conclusion"] = "INVALID_ENDPOINTS"
            current = None
            continue
        if current[prefix + "_status"]:
            current["conclusion"] = "INVALID_DUPLICATE_DIRECTION"
            current = None
            continue
        current.update({prefix + "_status": status, prefix + "_errors": int(errors),
                        prefix + "_samples": int(samples), prefix + "_max10k": int(max10k)})
        if current["ab_status"] and current["ba_status"]:
            statuses = [current["ab_status"], current["ba_status"]]
            goal = GOALS[current["mode"]]
            pair = current["pair"]
            valid_pair = pair == 0 or (1 <= pair <= 17 and
                         (current["j8_a"], current["j8_b"]) == (2 * pair + 1, 2 * pair + 2))
            valid_pins = 3 <= current["j8_a"] <= 36 and 3 <= current["j8_b"] <= 36 and current["j8_a"] != current["j8_b"]
            valid_counts = all(0 <= current[p + "_max10k"] <= current[p + "_errors"] <= current[p + "_samples"] <= goal for p in ("ab", "ba"))
            if not valid_pair or not valid_pins or not valid_counts:
                current["conclusion"] = "INVALID_DATA"
            elif current["aborted"] or "INVALID" in statuses or any(current[p + "_samples"] != goal for p in ("ab", "ba")):
                current["conclusion"] = "INVALID"
            elif statuses == ["PASS", "PASS"] and current["ab_errors"] == current["ba_errors"] == 0:
                current["conclusion"] = "PASS"
            elif "FAIL" in statuses:
                current["conclusion"] = "FAIL"
            elif "INTERMITTENT" in statuses:
                current["conclusion"] = "INTERMITTENT"
            else:
                current["conclusion"] = "INVALID_DATA"
    return runs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--csv", type=Path, help="Default: <logstem>_results.csv")
    args = parser.parse_args()
    runs = read_runs(args.log.read_text(encoding="utf-8-sig", errors="replace"))
    destination = args.csv or args.log.with_name(args.log.stem + "_results.csv")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(runs)
    latest = {row["pair"]: row for row in runs if 1 <= row["pair"] <= 17}
    passed = sum(row["conclusion"] == "PASS" for row in latest.values())
    suspect = sum(row["conclusion"] in ("FAIL", "INTERMITTENT") for row in latest.values())
    invalid = len(latest) - passed - suspect
    print(f"REPORTS={len(runs)} PASS_PAIRS={passed} SUSPECT_PAIRS={suspect} INVALID_PAIRS={invalid} UNTESTED_PAIRS={17-len(latest)}")
    print("Latest report per adjacent pair only; repeated REPORT responses remain in CSV, so REPORTS is not a count of distinct tests. CROSS reports stay in CSV.")
    print("PASS is under recorded conditions, not a solder-joint diagnosis.")
    print(destination.resolve())


if __name__ == "__main__":
    main()
