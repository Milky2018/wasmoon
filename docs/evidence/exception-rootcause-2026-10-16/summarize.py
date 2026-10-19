"""Summarize the archived paired samples; no benchmark is run here."""

import json
from pathlib import Path
import random
import statistics


def comparison(row, first, second, field):
    pairs = list(zip(row["samples"][first], row["samples"][second]))
    changes = [100 * (b[field] / a[field] - 1) for a, b in pairs]
    rng = random.Random(637)
    resamples = sorted(
        statistics.median(rng.choices(changes, k=len(changes)))
        for _ in range(10000)
    )
    return {
        "workload": row["workload"],
        "iterations": row.get("count", row.get("n")),
        "first": first,
        "second": second,
        "field": field,
        "first_median": statistics.median(a[field] for a, _ in pairs),
        "second_median": statistics.median(b[field] for _, b in pairs),
        "paired_median_change_percent": statistics.median(changes),
        "paired_median_bootstrap_95_percent": [resamples[249], resamples[9749]],
    }


def main():
    directory = Path(__file__).resolve().parent
    results = {}
    for name, first, second, field in [
        ("final-cli", "before", "fixed", "cpu_ns"),
        ("final-cli", "matched_c", "fixed", "cpu_ns"),
        ("final-cli-counters", "before", "fixed", "cycles"),
        ("final-store-counters", "before", "fixed", "cpu_ns"),
        ("final-store-counters", "matched_c", "fixed", "cpu_ns"),
        ("minimal-control-counters", "original", "empty_fast", "cycles"),
        ("same-site-control-counters", "original", "empty_fast", "cycles"),
        ("aligned-counters", "original", "candidate", "cycles"),
    ]:
        data = json.loads((directory / f"{name}.json").read_text())
        key = f"{name}:{first}->{second}:{field}"
        results[key] = [comparison(row, first, second, field) for row in data["results"]]
    report = {
        "method": "Median paired ratios; percentile bootstrap, 10000 resamples, seed 637. Descriptive intervals for these batches, not cross-machine guarantees.",
        "results": results,
    }
    (directory / "paired-summary.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
