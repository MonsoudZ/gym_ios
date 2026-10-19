# Gym + Nutrition iOS App — Design Spec

Status: draft for discussion. Nothing here is built yet.

The app has one job: look at what you have actually done, and tell you what to do next.
Every rule below is tied to the evidence it comes from. Where the evidence is weak or
mixed, the spec says so, and the rule is conservative.

---

## 1. Principles

1. **Trend over snapshot.** Daily numbers are noise. The app decides on smoothed trends
   and shows the trend first, the raw number second.
2. **One verdict per screen.** Each screen leads with a plain-language sentence
   ("Add 2.5 kg to bench today", "Hold calories this week"). Details are one tap deeper.
3. **Show the why.** Every prescription can be expanded to show the data that produced it.
4. **Autoregulate, don't schedule.** Deloads and calorie changes are triggered by your
   data, not by the calendar.
5. **Measure what you can measure well.** Sets, reps, load, RPE, bodyweight, intake.
   No step counts or wearable calorie burn as inputs (see §3.2).

---

## 2. Training

### 2.1 What the science says

| Finding | Evidence | Design consequence |
|---|---|---|
| Hypertrophy rises with weekly hard sets per muscle; 10+ sets/week beats fewer, with diminishing returns higher up. | Schoenfeld, Ogborn & Krieger 2017, *J Sports Sci* (meta-analysis). Pelland et al. 2024/25, *Sports Med* (meta-regression) finds gains continue past 10 but flatten. | Track hard sets per muscle per week. Floor of 10, default target 12–18, flag above 20. |
| Training a muscle 2×/week beats 1×/week at matched volume. | Schoenfeld, Ogborn & Krieger 2016, *Sports Med*. | Program templates hit every muscle at least twice a week. |
| Load (heavy vs light) matters little for hypertrophy if sets are taken near failure. Heavy loads are better for 1RM strength. | Schoenfeld et al. 2017, *J Strength Cond Res* (meta-analysis). | Rep ranges are per-goal: 3–6 for strength lifts, 6–12 for hypertrophy, 12–20 for isolation. All are valid; the engine progresses whichever you use. |
| Closer proximity to failure gives more hypertrophy; strength gains are largely insensitive to it. Stopping 1–3 reps short is close enough for growth. | Robinson et al. 2024, *Sports Med* (meta-regression). | Target RPE 7–9 (1–3 reps in reserve). Going to RPE 10 on every set is not required and is flagged if it coincides with stalling. |
| The RPE / reps-in-reserve scale is a valid, reliable way to gauge set difficulty, especially for trained lifters. | Zourdos et al. 2016, *J Strength Cond Res*; Helms et al. 2016, *Strength Cond J*. | Log RPE on every working set. It drives progression decisions. |
| Estimated 1RM from submaximal sets is accurate for low reps and gets unreliable above ~10 reps. | Epley 1985; Brzycki 1993; validation reviews (e.g. LeSuer et al. 1997, *J Strength Cond Res*). | Compute e1RM = weight × (1 + reps/30), only from sets of ≤10 reps. Use it for trend charts and for RPE-based load selection. |
| Evidence that *scheduled* deloads help is weak; a recent RCT found no difference over 9 weeks with vs without one. | Coleman et al. 2024, *PeerJ*. Bell et al. 2022 survey of coaches. | No calendar deloads. Deload is triggered by stalling plus fatigue signals (§2.3). |
| Short sleep impairs strength and recovery, though effect sizes vary. | Knowles et al. 2018, *J Sci Med Sport* (systematic review). | Sleep is a readiness input with a small, capped effect (§2.4). |

### 2.2 Data captured per set

- Exercise, weight, reps, RPE (6–10 in 0.5 steps). RPE is required on working sets.
- Set type: warm-up or working. Only working sets count toward volume.
- Each exercise maps to one or more muscles with a weighting (bench: chest 1.0, triceps 0.5,
  front delt 0.5). Weekly volume is the weighted sum of working sets.

### 2.3 Progression rules (per exercise)

Each exercise has: a rep range (low–high), a load increment, a set count, and an RPE cap
(default 9).

After every session the exercise gets a verdict:

| Verdict | Condition |
|---|---|
| **Progressed** | Every working set reached the top of the rep range at or below the RPE cap. |
| **Held** | Every set within range, but not all at the top, or RPE above cap. |
| **Failed** | Any working set below the bottom of the range. |

Next-session prescription:

| Last verdict | Next load |
|---|---|
| Progressed | Previous load + increment. |
| Held | Same load. Chase reps. |
| Failed | Same load once. Two consecutive fails → see stall. |

**Stall and deload.** Three consecutive sessions without a *Progressed* verdict on a lift
marks it stalled. The app then:

1. Checks weekly volume for that muscle. If under 10 hard sets, it suggests +1 set before
   touching load.
2. Checks readiness (§2.4). If readiness has been low for most of those sessions, it
   suggests fixing sleep/soreness before deloading.
3. Otherwise it prescribes a 10% load reduction and resets the stall counter.
   The next three sessions use the normal rules to climb back.

This keeps deloads rare and earned, which matches the evidence that they are not needed
on a fixed schedule.

**Increments.** Defaults: 2.5 kg upper-body barbell, 5 kg lower-body barbell, smallest
available dumbbell step, 1 plate / ~5% on machines. All editable per exercise.

### 2.4 Readiness

Optional daily check-in: sleep hours (from HealthKit if available), and soreness 1–5 on
the muscles trained today.

- Sleep < 6 h or soreness ≥ 4 on a target muscle → today's prescribed loads × 0.95,
  with a one-line explanation. The rep targets do not change.
- The effect is deliberately small and capped at 5%, because the evidence supports
  "sleep matters" much better than any specific magnitude.
- Readiness never *raises* loads. It only pulls a bad day back.

### 2.5 Volume guardrails (per muscle per week)

| Weekly hard sets | App behaviour |
|---|---|
| < 10 | "Under the evidence-based minimum" — suggest +1–2 sets on a lift for that muscle. |
| 10–20 | Normal. |
| > 20 | Shown in amber. If the muscle's lifts are also stalling, suggest −2 sets. |

Numbers come from the Schoenfeld 2017 and Pelland 2024 dose–response work. The upper
band is a prompt, not a hard stop; some people respond well above 20.

### 2.6 Program templates

Shipped defaults, all hitting each muscle ≥ 2×/week:

- Upper / Lower, 4 days
- Push / Pull / Legs, 6 days (or 3 days rotating)
- Full body, 3 days

Each template is just a list of exercises with rep ranges, set counts and increments.
The engine is the same for all of them, so you can edit freely.

---

## 3. Nutrition

### 3.1 What the science says

| Finding | Evidence | Design consequence |
|---|---|---|
| Protein for muscle gain plateaus around 1.6 g/kg/day; the upper confidence bound is ~2.2 g/kg. | Morton et al. 2018, *Br J Sports Med* (meta-analysis, 49 studies). | Default protein 1.8 g/kg bodyweight. Range 1.6–2.2. |
| In a deficit, higher protein (2.3–3.1 g/kg fat-free mass) and fat at 15–30% of calories best preserves lean mass. | Helms, Aragon & Fitschen 2014, *J Int Soc Sports Nutr* (review). | During a cut, protein target rises to 2.2 g/kg. Fat floor 0.7 g/kg. Carbs are the flexible macro. |
| Slower weight loss (~0.7%/week) preserves more lean mass and strength than faster loss (~1.4%/week) in athletes. | Garthe et al. 2011, *Int J Sport Nutr Exerc Metab* (RCT). | Default cut rate 0.5%/week; max selectable 1.0%/week. |
| The "3500 kcal per pound / 7700 kcal per kg" rule overstates loss over time because expenditure falls as you lose weight. | Hall 2008, *Int J Obes*; Hall et al. 2011, *Lancet*. | Used only as the conversion inside the adaptive estimate, which re-measures every two weeks and therefore self-corrects. Never used to predict the future. |
| Consumer wearables measure energy expenditure poorly (errors commonly > 25%). | Shcherbina et al. 2017, *J Pers Med*. | Watch/phone calorie burn is **not** an input. Expenditure is inferred from intake vs weight change instead. |
| Daily scale weight fluctuates 1–2% from water, glycogen and gut contents. | Widely documented; e.g. Bhutani et al. 2017, *Obesity*. | Decisions use an exponentially smoothed trend, never a single weigh-in. |

### 3.2 Adaptive expenditure (the core of the nutrition engine)

Inputs: daily intake (kcal), daily morning bodyweight.

1. **Trend weight.** Exponential moving average, α = 0.1. Today's trend =
   0.1 × today's weight + 0.9 × yesterday's trend.
2. **Expenditure estimate** over the last 14 days:
   `TDEE ≈ mean daily intake − (7700 × Δtrend_kg) / 14`
   Missing intake days are excluded from the mean and the window extends to keep 14
   logged days. Fewer than 10 logged days → estimate shown as "low confidence".
3. **Calibration period.** For the first 14 days the target comes from Mifflin–St Jeor ×
   activity factor and is labelled provisional.

### 3.3 Weekly adjustment

Every 7 days, compare the trend's rate of change to the goal rate.

| Situation | Adjustment |
|---|---|
| Within ±0.15%/week of goal | Hold. |
| Losing/gaining slower than goal | ±100 kcal toward goal. |
| Losing/gaining faster than goal | ∓100 kcal. |
| Off by more than 0.5%/week | ±150 kcal, and a note to check logging accuracy. |

Adjustments are capped at 150 kcal per week so one odd week cannot swing the plan.

### 3.4 Macro targets

- Protein: 1.8 g/kg maintaining or gaining; 2.2 g/kg cutting.
- Fat: floor 0.7 g/kg; default 25% of calories.
- Carbs: whatever remains. When calories change, carbs change first.
- Fibre: shown as a soft target of 14 g per 1000 kcal (USDA guideline), not enforced.

### 3.5 Goal presets

| Goal | Rate | Notes |
|---|---|---|
| Cut | −0.5%/week (max −1.0%) | Protein to 2.2 g/kg. |
| Maintain | 0 | |
| Lean gain | +0.25%/week (max +0.5%) | Faster than this is mostly fat in trained lifters. |

---

## 4. What the app shows (readability)

**Today screen**

- One line: today's session name and the single most important change
  ("Bench: 82.5 kg × 3 sets of 6–8, up from 80").
- One line: calorie and protein target with progress bar.
- Readiness check-in if not done (two taps).

**During a workout**

- Prescribed weight × reps for the current set, big.
- Last session's result for the same set, small, underneath.
- RPE picker inline. No menus.

**Progress screens**

- Per lift: e1RM trend line with sessions as dots. 4-week and 12-week change in bold.
- Per muscle: weekly hard sets as a bar chart against the 10 / 20 bands.
- Bodyweight: trend line over raw dots, with the goal slope drawn as a reference.
- Expenditure: current estimate, confidence, and how it has moved.

**Rules of thumb**

- No table has more than four columns on a phone.
- Every number has a unit and a comparison (last time, last week, goal).
- Jargon is translated: "RPE 8" is shown as "RPE 8 · 2 reps left".

---

## 5. Data model (summary)

```
Exercise          id, name, muscles [(muscle, weight)], repRange, increment, setCount, rpeCap
WorkoutSession    id, date, templateDayId, readiness (sleepHours, soreness[muscle])
SetEntry          id, sessionId, exerciseId, order, weight, reps, rpe, isWarmup
BodyweightEntry   date, kg
IntakeEntry       id, date, name, kcal, protein, carbs, fat, fibre
Settings          units, goal, goalRate, proteinPerKg, fatFloorPerKg
```

Derived, never stored as truth: e1RM per set, weekly volume per muscle, trend weight,
TDEE estimate, verdicts, prescriptions. They are recomputed from the entries so a logging
correction fixes everything downstream.

---

## 6. Tech

- SwiftUI + SwiftData, iOS 26 target, iCloud sync via CloudKit.
- Swift Charts for all trend views.
- HealthKit: read sleep and bodyweight, write workouts.
- No server. No account. Export to CSV from day one.

---

## 7. Open questions

1. Default units: kg or lb?
2. Starting split and goal (decides the first template and the macro preset).
3. Any existing data to import (Strong, Hevy, MacroFactor export)?
4. Is a food database needed in v1, or are saved meals plus manual entry enough to start?

---

## References

- Bell L, et al. (2022). "Why do athletes deload?" *Sports Med Open*.
- Bhutani S, et al. (2017). Daily weight fluctuation. *Obesity*.
- Brzycki M. (1993). Strength testing — predicting a one-rep max from reps-to-fatigue. *JOPERD*.
- Coleman M, et al. (2024). Deload vs no deload over 9 weeks. *PeerJ*.
- Epley B. (1985). *Poundage Chart*. Boyd Epley Workout.
- Garthe I, et al. (2011). Effect of two different weight-loss rates on body composition and strength. *Int J Sport Nutr Exerc Metab*.
- Hall KD. (2008). What is the required energy deficit per unit weight loss? *Int J Obes*.
- Hall KD, et al. (2011). Quantification of the effect of energy imbalance on bodyweight. *Lancet*.
- Helms ER, Aragon AA, Fitschen PJ. (2014). Evidence-based recommendations for natural bodybuilding contest preparation. *J Int Soc Sports Nutr*.
- Helms ER, et al. (2016). Application of the repetitions in reserve-based RPE scale. *Strength Cond J*.
- Knowles OE, et al. (2018). Inadequate sleep and muscle strength. *J Sci Med Sport*.
- LeSuer DA, et al. (1997). Accuracy of prediction equations for 1RM. *J Strength Cond Res*.
- Morton RW, et al. (2018). Protein supplementation and resistance-training gains. *Br J Sports Med*.
- Pelland JC, et al. (2024/2025). Resistance training dose–response meta-regressions. *Sports Med*.
- Robinson ZP, et al. (2024). Proximity to failure, strength and hypertrophy. *Sports Med*.
- Schoenfeld BJ, Ogborn D, Krieger JW. (2016). Training frequency and hypertrophy. *Sports Med*.
- Schoenfeld BJ, Ogborn D, Krieger JW. (2017). Weekly volume dose–response. *J Sports Sci*.
- Schoenfeld BJ, et al. (2017). Low- vs high-load resistance training. *J Strength Cond Res*.
- Shcherbina A, et al. (2017). Accuracy of wrist-worn devices. *J Pers Med*.
- Zourdos MC, et al. (2016). RIR-based RPE scale. *J Strength Cond Res*.

Citations are from memory and should be spot-checked before anything is published.
