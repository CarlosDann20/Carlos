#!/usr/bin/env python3
"""
Validate Memora's SM-2 easiness-factor update against the canonical SuperMemo-2
formula, and confirm the exact expectations embedded in SM2SchedulerTests.swift.

`updated_ease` mirrors SM2Scheduler.updatedEase (permille). The canonical rule is
    EF' = EF + (0.1 - (5-q)*(0.08 + (5-q)*0.02)),  floored at 1.3
with the button→quality map Again=1, Hard=3, Good=4, Easy=5.
"""
import sys

MIN_EASE = 1300

def updated_ease(ease_permille, rating):
    q = {1: 1, 2: 3, 3: 4, 4: 5}[rating]  # Again/Hard/Good/Easy
    ef = ease_permille / 1000.0
    ef += 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)
    return max(MIN_EASE, round(ef * 1000))

def check(cond, msg):
    print(f"  [{'ok ' if cond else 'FAIL'}] {msg}")
    return cond

def main():
    ok = True
    print("SM-2 ease update from 2500 (matches SM2SchedulerTests.testEaseUpdateFormula):")
    ok &= check(updated_ease(2500, 3) == 2500, f"Good  -> 2500 (got {updated_ease(2500,3)})")  # q4 Δ0
    ok &= check(updated_ease(2500, 4) == 2600, f"Easy  -> 2600 (got {updated_ease(2500,4)})")  # q5 +0.1
    ok &= check(updated_ease(2500, 2) == 2360, f"Hard  -> 2360 (got {updated_ease(2500,2)})")  # q3 -0.14
    ok &= check(updated_ease(2500, 1) == 1960, f"Again -> 1960 (got {updated_ease(2500,1)})")  # q1 -0.54

    print("SM-2 ease floor (testEaseFloor):")
    ok &= check(updated_ease(1400, 1) == 1300, f"Again from 1400 -> 1300 (got {updated_ease(1400,1)})")

    # Interval growth monotonicity for Good >= previous+1 with EF multiplier.
    print("SM-2 interval growth (sanity):")
    def grow(prev, factor):
        return max(round(prev * factor), prev + 1)
    ok &= check(grow(10, 2.5) == 25, f"Good ivl 10*2.5 -> 25 (got {grow(10,2.5)})")
    ok &= check(grow(10, 2.5 * 1.3) > grow(10, 2.5), "Easy interval > Good interval")
    ok &= check(grow(10, 1.2) > 10, "Hard interval grows by at least 1 day")

    print("\n" + ("PASS: SM-2 expectations verified." if ok else "FAIL"))
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
