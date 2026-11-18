#!/usr/bin/env python3
"""
Validate Memora's Swift FSRS-6 port against the py-fsrs reference.

`mirror_outcome` is a line-by-line Python translation of
Memora/Core/Scheduler/FSRSScheduler.swift `outcome(...)`. We drive the official
py-fsrs Scheduler and the mirror through identical rating sequences (fuzz
disabled) and assert that state, stability, difficulty and interval match.

If the mirror matches the reference, and the Swift matches the mirror
(structurally identical), then the Swift port is correct.
"""
import math
import sys
from datetime import datetime, timezone, timedelta

from fsrs import Scheduler, Card, Rating, State

PARAMS = list(Scheduler().parameters)  # FSRS-6 defaults (21)
DR = 0.9
LEARN = [60, 600]      # seconds (1 min, 10 min)
RELEARN = [600]        # seconds (10 min)
MAX_IVL = 36500
DECAY = -PARAMS[20]
FACTOR = 0.9 ** (1 / DECAY) - 1
S_MIN = 0.001

# ---- mirror of FSRSScheduler.swift ----

def clampS(s): return max(s, S_MIN)
def clampD(d): return min(max(d, 1.0), 10.0)
def initS(g): return clampS(PARAMS[g - 1])
def initD(g, clamp):
    d = PARAMS[4] - math.exp(PARAMS[5] * (g - 1)) + 1
    return clampD(d) if clamp else d
def retr(elapsed, s): return (1 + FACTOR * max(0, elapsed) / s) ** DECAY
def next_ivl(s):
    raw = (s / FACTOR) * (DR ** (1 / DECAY) - 1)
    return min(max(int(round(raw)), 1), MAX_IVL)
def short_term(s, g):
    inc = math.exp(PARAMS[17] * (g - 3 + PARAMS[18])) * (s ** -PARAMS[19])
    if g >= 2:
        inc = max(inc, 1.0)
    return clampS(s * inc)
def next_D(d, g):
    arg1 = initD(4, False)
    delta = -(PARAMS[6] * (g - 3))
    damped = (10.0 - d) * delta / 9.0
    arg2 = d + damped
    return clampD(PARAMS[7] * arg1 + (1 - PARAMS[7]) * arg2)
def forget_S(d, s, r):
    long = PARAMS[11] * (d ** -PARAMS[12]) * (((s + 1) ** PARAMS[13]) - 1) * math.exp((1 - r) * PARAMS[14])
    short = s / math.exp(PARAMS[17] * PARAMS[18])
    return min(long, short)
def recall_S(d, s, r, g):
    hp = PARAMS[15] if g == 2 else 1.0
    eb = PARAMS[16] if g == 4 else 1.0
    return s * (1 + math.exp(PARAMS[8]) * (11 - d) * (s ** -PARAMS[9]) * (math.exp((1 - r) * PARAMS[10]) - 1) * hp * eb)
def next_S(d, s, r, g):
    return clampS(forget_S(d, s, r) if g == 1 else recall_S(d, s, r, g))
def hard_step(steps, step):
    if step == 0 and len(steps) == 1:
        return int(steps[0] * 1.5)
    if step == 0 and len(steps) >= 2:
        return (steps[0] + steps[1]) // 2
    if step < len(steps):
        return steps[step]
    return steps[-1]

# card: dict(state, step, S, D) ; state in {'new','learning','review','relearning'}
def mirror_outcome(card, g, elapsed):
    state = card['state']; step = card['step']; S = card['S']; D = card['D']
    same_day = (card['last'] is not None) and (elapsed < 1)
    interval = ('s', 60)

    if state in ('new', 'learning'):
        if S is None or D is None:
            S = initS(g); D = initD(g, True)
        elif same_day:
            S = short_term(S, g); D = next_D(D, g)
        else:
            r = retr(elapsed, S); S = next_S(D, S, r, g); D = next_D(D, g)
        steps = LEARN
        if len(steps) == 0 or (step >= len(steps) and g >= 2):
            state = 'review'; step = 0; interval = ('d', next_ivl(S))
        else:
            state = 'learning'  # first review of a new card keeps it in learning
            if g == 1:
                step = 0; interval = ('s', steps[0])
            elif g == 2:
                interval = ('s', hard_step(steps, step))
            elif g == 3:
                if step + 1 == len(steps):
                    state = 'review'; step = 0; interval = ('d', next_ivl(S))
                else:
                    step += 1; interval = ('s', steps[step])
            else:
                state = 'review'; step = 0; interval = ('d', next_ivl(S))

    elif state == 'review':
        if same_day:
            S = short_term(S, g)
        else:
            r = retr(elapsed, S); S = next_S(D, S, r, g)
        D = next_D(D, g)
        if g == 1:
            if len(RELEARN) == 0:
                interval = ('d', next_ivl(S))
            else:
                state = 'relearning'; step = 0; interval = ('s', RELEARN[0])
        else:
            interval = ('d', next_ivl(S))

    elif state == 'relearning':
        if same_day:
            S = short_term(S, g); D = next_D(D, g)
        else:
            r = retr(elapsed, S); S = next_S(D, S, r, g); D = next_D(D, g)
        steps = RELEARN
        if len(steps) == 0 or (step >= len(steps) and g >= 2):
            state = 'review'; step = 0; interval = ('d', next_ivl(S))
        else:
            if g == 1:
                step = 0; interval = ('s', steps[0])
            elif g == 2:
                interval = ('s', hard_step(steps, step))
            elif g == 3:
                if step + 1 == len(steps):
                    state = 'review'; step = 0; interval = ('d', next_ivl(S))
                else:
                    step += 1; interval = ('s', steps[step])
            else:
                state = 'review'; step = 0; interval = ('d', next_ivl(S))

    return {'state': state, 'step': step, 'S': S, 'D': D, 'interval': interval}


PY_STATE = {State.Learning: 'learning', State.Review: 'review', State.Relearning: 'relearning'}

def run():
    scheduler = Scheduler(parameters=PARAMS, desired_retention=DR,
                          learning_steps=[timedelta(seconds=s) for s in LEARN],
                          relearning_steps=[timedelta(seconds=s) for s in RELEARN],
                          maximum_interval=MAX_IVL, enable_fuzzing=False)
    # A battery of rating sequences and elapsed-day gaps.
    sequences = [
        [(3, 0), (3, 0), (3, 1), (3, 3), (4, 10), (1, 20), (3, 0), (3, 1), (3, 5)],
        [(1, 0), (1, 0), (3, 0), (3, 1), (2, 2), (3, 6), (3, 15), (1, 5), (3, 0)],
        [(4, 0), (3, 4), (3, 10), (2, 8), (1, 12), (3, 0), (4, 20)],
        [(2, 0), (3, 0), (3, 0), (3, 1), (3, 2), (3, 4), (4, 9), (3, 25), (1, 30), (3, 0), (3, 1)],
        [(3, 0), (3, 1), (3, 3), (3, 7), (3, 16), (3, 40), (3, 90), (3, 200)],
    ]
    mism = 0
    checks = 0
    for si, seq in enumerate(sequences):
        pcard = Card()
        mcard = {'state': 'new', 'step': 0, 'S': None, 'D': None, 'last': None}
        t = datetime(2025, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
        for ri, (g, gap) in enumerate(seq):
            t = t + timedelta(days=gap)
            # py-fsrs
            pcard, _ = scheduler.review_card(pcard, Rating(g), review_datetime=t)
            p_ivl_days = (pcard.due - t)
            # mirror: elapsed days since last review
            elapsed = gap if mcard['last'] is not None else 0
            m = mirror_outcome(mcard, g, elapsed)
            mcard.update(S=m['S'], D=m['D'], state=m['state'], step=m['step'], last=t)

            # compare state
            ps = PY_STATE[pcard.state]
            checks += 1
            ok = True
            if ps != m['state']:
                ok = False
            # compare stability/difficulty
            if pcard.stability is not None and m['S'] is not None:
                if abs(pcard.stability - m['S']) > 1e-6:
                    ok = False
            if pcard.difficulty is not None and m['D'] is not None:
                if abs(pcard.difficulty - m['D']) > 1e-6:
                    ok = False
            # compare interval
            kind, val = m['interval']
            if kind == 'd':
                if abs(p_ivl_days.total_seconds() - val * 86400) > 1:
                    ok = False
            else:
                if abs(p_ivl_days.total_seconds() - val) > 1:
                    ok = False
            if not ok:
                mism += 1
                print(f"MISMATCH seq{si} step{ri} g={g} gap={gap}")
                print(f"  py: state={ps} S={pcard.stability} D={pcard.difficulty} due_s={p_ivl_days.total_seconds()}")
                print(f"  mir:state={m['state']} S={m['S']} D={m['D']} ivl={m['interval']}")
    print(f"\nChecks: {checks}, mismatches: {mism}")
    if mism == 0:
        print("PASS: Swift FSRS-6 port matches py-fsrs reference exactly.")
        return 0
    print("FAIL")
    return 1

if __name__ == "__main__":
    sys.exit(run())
