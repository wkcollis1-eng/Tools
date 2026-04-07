#!/usr/bin/env python3
"""Setback recovery CSV writer for Home Assistant.

Usage:
    python3 setback_csv.py <zone> <hold> <setback> <start_temp> <recovery_min> <outdoor>

Positional args eliminate all JSON/shell quoting issues.
Validates all values before appending.
Writes to /config/reports/hvac_setback_<zone>.csv
"""

import sys
import os
import csv
from datetime import datetime

REPORT_DIR = "/config/reports"
HEADER = [
    "date",
    "hold_setpoint",
    "setback_setpoint",
    "setback_degrees",
    "recovery_start_temp",
    "degrees_to_recover",
    "recovery_minutes",
    "min_per_degree",
    "outdoor_temp",
]


def validate(val, name, lo, hi):
    try:
        v = float(val)
    except (ValueError, TypeError):
        raise ValueError(f"{name}: not a number ({val!r})")
    if v < lo or v > hi:
        raise ValueError(f"{name}: {v} outside [{lo}, {hi}]")
    return v


def main():
    if len(sys.argv) != 7:
        print(
            f"Usage: {sys.argv[0]} <zone> <hold> <setback> <start_temp> <recovery_min> <outdoor>",
            file=sys.stderr,
        )
        sys.exit(1)

    zone = sys.argv[1].upper()
    if zone not in ("1F", "2F"):
        print(f"Invalid zone: {zone!r} (expected 1F or 2F)", file=sys.stderr)
        sys.exit(1)

    try:
        hold = validate(sys.argv[2], "hold_setpoint", 55, 85)
        setback = validate(sys.argv[3], "setback_setpoint", 45, 85)
        start_temp = validate(sys.argv[4], "recovery_start_temp", 40, 85)
        recovery_min = validate(sys.argv[5], "recovery_minutes", 0.1, 300)
        outdoor = validate(sys.argv[6], "outdoor_temp", -30, 110)
    except ValueError as e:
        print(f"Validation failed for {zone}: {e}", file=sys.stderr)
        sys.exit(2)

    setback_degrees = round(hold - setback, 1)
    degrees_to_recover = round(hold - start_temp, 1)

    if setback_degrees < 0.5:
        print(
            f"Rejected {zone}: setback_degrees={setback_degrees} < 0.5", file=sys.stderr
        )
        sys.exit(2)
    if degrees_to_recover < 0.1:
        print(
            f"Rejected {zone}: degrees_to_recover={degrees_to_recover} < 0.1",
            file=sys.stderr,
        )
        sys.exit(2)

    min_per_degree = round(recovery_min / max(degrees_to_recover, 0.1), 1)

    filepath = os.path.join(REPORT_DIR, f"hvac_setback_{zone.lower()}.csv")
    os.makedirs(REPORT_DIR, exist_ok=True)

    write_header = not os.path.exists(filepath)

    row = {
        "date": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "hold_setpoint": hold,
        "setback_setpoint": setback,
        "setback_degrees": setback_degrees,
        "recovery_start_temp": start_temp,
        "degrees_to_recover": degrees_to_recover,
        "recovery_minutes": round(recovery_min, 1),
        "min_per_degree": min_per_degree,
        "outdoor_temp": outdoor,
    }

    try:
        with open(filepath, "a", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=HEADER)
            if write_header:
                writer.writeheader()
            writer.writerow(row)
    except IOError as e:
        print(f"Write failed for {zone}: {e}", file=sys.stderr)
        sys.exit(3)

    print(
        f"OK {zone}: {setback_degrees}°F setback, {recovery_min} min recovery, "
        f"{min_per_degree} min/°F",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
