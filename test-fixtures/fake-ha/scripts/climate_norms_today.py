#!/usr/bin/env python3
"""
Climate Norms Lookup Script for Home Assistant
Reads climate_daily_norms.csv and outputs today's expected values as JSON.
Run daily at midnight via command_line sensor.
"""

import csv
import json
from datetime import datetime
from pathlib import Path

# Path to climate norms CSV (relative to HA config directory)
CSV_PATH = Path(__file__).parent.parent / "climate_daily_norms.csv"


def get_climate_norms_today():
    """Look up today's climate norms from CSV."""
    today = datetime.now()
    day_of_year = today.timetuple().tm_yday

    try:
        with open(CSV_PATH, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if int(row["DayOfYear"]) == day_of_year:
                    # Return the key values we need
                    return {
                        "day_of_year": day_of_year,
                        "month": int(row["Month"]),
                        "day": int(row["Day"]),
                        "hdd_mean": round(float(row["HDD65_mean"]), 2),
                        "hdd_min": round(float(row["HDD65_min"]), 2),
                        "hdd_max": round(float(row["HDD65_max"]), 2),
                        "hdd_p10": round(float(row["HDD65_p10"]), 2),
                        "hdd_p90": round(float(row["HDD65_p90"]), 2),
                        "cdd_mean": round(float(row["CDD65_mean"]), 2),
                        "cdd_p10": round(float(row["CDD65_p10"]), 2),
                        "cdd_p90": round(float(row["CDD65_p90"]), 2),
                        "tmean": round(float(row["Tmean_mean"]), 1),
                        "tmin": round(float(row["Tmin_mean"]), 1),
                        "tmax": round(float(row["Tmax_mean"]), 1),
                        "samples": int(row["Samples"]),
                        "status": "ok",
                    }

        # Day not found (shouldn't happen with 365-day file)
        return {"status": "error", "message": f"Day {day_of_year} not found"}

    except FileNotFoundError:
        return {"status": "error", "message": f"CSV not found: {CSV_PATH}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def get_smoothed_hdd(window=3):
    """Get smoothed HDD mean using a rolling window around today."""
    today = datetime.now()
    day_of_year = today.timetuple().tm_yday

    # Calculate days to average (centered window)
    half_window = window // 2
    days_to_check = [
        (day_of_year - half_window + i - 1) % 365 + 1 for i in range(window)
    ]

    try:
        hdd_values = []
        with open(CSV_PATH, "r") as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        for row in rows:
            if int(row["DayOfYear"]) in days_to_check:
                hdd_values.append(float(row["HDD65_mean"]))

        if hdd_values:
            return round(sum(hdd_values) / len(hdd_values), 2)
        return None
    except Exception:
        return None


if __name__ == "__main__":
    result = get_climate_norms_today()

    # Add smoothed value
    smoothed = get_smoothed_hdd(3)
    if smoothed is not None:
        result["hdd_mean_smoothed"] = smoothed

    print(json.dumps(result))
