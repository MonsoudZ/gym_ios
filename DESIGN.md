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
| Hypertrophy rises with weekly hard sets per muscle (graded dose–response), with diminishing returns at higher volumes. | Schoenfeld, Ogborn & Krieger 2017, *J Sports Sci* (meta-regression: +0.37% gain per extra weekly set; the <5 / 5–9 / 10+ categorical comparison was only a trend, p = 0.074). Pelland et al. 2026 (online Dec 2025), *Sports Med* (67 studies; hypertrophy keeps rising with volume, with diminishing returns). | Track hard sets per muscle per week. Floor of 10, default target 12–18, flag above 20. *Verification note: neither paper reports 10 or 20 as a threshold; they are practical heuristics, not cut-offs from the data. Evidence is weaker than "10+ beats fewer" implies, and gains may continue above 20.* |
| Training a muscle 2×/week beat 1×/week in a 2016 meta-analysis (10 studies), including on a volume-equated basis. | Schoenfeld, Ogborn & Krieger 2016, *Sports Med*. Later work is less supportive: Schoenfeld, Grgic & Krieger 2019, *J Sports Sci* (25 studies) found no frequency effect when volume was equated; Pelland et al. 2026 finds frequency's effect on hypertrophy compatible with negligible. | Program templates hit every muscle at least twice a week. *Verification note: evidence is weaker than stated. The 2×/week rule is better justified as a way to spread weekly volume across sessions than as a frequency effect in itself.* |
| 3 min rest between sets beat 1 min for strength and for anterior-thigh hypertrophy in trained men. A systematic review found the evidence equivocal overall, with a possible advantage for long (>60 s) rests in trained participants. | Schoenfeld et al. 2016, *J Strength Cond Res* (21 resistance-trained men, 8 weeks, 3 × 8–12 RM, 1 vs 3 min; 1RM squat and bench and anterior-thigh thickness greater with 3 min, triceps a trend at p = 0.06). Grgic et al. 2017, *Eur J Sport Sci* (systematic review, 6 studies comparing ≤60 s with >60 s; both may work, long rests possibly better in trained lifters, more research called for). | Each exercise carries a rest interval, default 3 min for rep ranges topping out at ≤10 reps and 2 min above that, editable from 0:30 to 10:00. Ticking a set done starts a countdown. *Verification note: the trial only compared 1 and 3 min, and the review is equivocal. The 3 min / 2 min split by rep range is a design choice; the evidence supports "not 1 min", not those exact values.* |
| Load (heavy vs light) matters little for hypertrophy when sets are taken to failure. Heavy loads are better for 1RM strength. | Schoenfeld, Grgic, Ogborn & Krieger 2017, *J Strength Cond Res* (meta-analysis, 21 studies; all included sets were to momentary failure; low-load ≤60% 1RM). | Rep ranges are per-goal: 3–6 for strength lifts, 6–12 for hypertrophy, 12–20 for isolation. All are valid; the engine progresses whichever you use. |
| Closer proximity to failure gives more hypertrophy; strength gains are largely insensitive to it. | Robinson et al. 2024, *Sports Med* (meta-regression; exploratory, reps in reserve estimated from study descriptions). | Target RPE 7–9 (1–3 reps in reserve). Going to RPE 10 on every set is not required and is flagged if it coincides with stalling. *Verification note: the paper reports a continuous trend toward failure for hypertrophy, not a "1–3 RIR is close enough" cut-off. That band is a judgement call trading growth against fatigue and is not directly supported by the paper.* |
| The RIR-based RPE scale is a practical way to gauge set difficulty; ratings track bar velocity in the squat. Accuracy is better close to failure and in lower-rep sets. | Zourdos et al. 2016, *J Strength Cond Res* (29 squatters; RPE inversely related to velocity, r = −0.77 to −0.88). Helms et al. 2016, *Strength Cond J* (practical guide, not a validation study). Zourdos et al. 2021, *J Strength Cond Res* (RIR predictions 2–5 reps off when far from failure or in high-rep sets). | Log RPE on every working set. It drives progression decisions. *Verification note: "valid and reliable" is stronger than the evidence (one exercise, small samples); RPE below ~7 is the least accurate, which is why the design leans on RPE 7–9 and on the rep-range rules as well.* |
| Estimated 1RM from submaximal sets is reasonably accurate for low reps and degrades at higher reps (≤10 reps recommended for linear equations). | Epley 1985 (the formula source; not a journal article); Brzycki 1993, *JOPERD*; Reynolds, Gordon & Robergs 2006, *J Strength Cond Res* (1/5/10/20RM in 70 adults: "no more than 10 repetitions should be used in linear equations"); LeSuer et al. 1997, *J Strength Cond Res* (7 equations, 67 students; accuracy differed by lift, and per secondary sources all underestimated deadlift, abstract not verifiable); Nuzzo et al. 2024, *Sports Med* (reps possible at a given %1RM vary a lot between individuals). | Compute e1RM = weight × (1 + reps/30), only from sets of ≤10 reps. Use it for trend charts and for RPE-based load selection. |
| Dividing strength by bodyweight (ratio scaling) is the simplest way to normalise for body size, but it is biased: between individuals it systematically favours lighter people, because strength scales with body mass to a power below 1 (allometric scaling, exponent about 2/3, is the better between-person model). | Jaric 2002, *Sports Med* (narrative review of normalisation methods; ratio, allometric and regression scaling compared across strength tests). | Each lift's history also shows e1RM ÷ trend bodyweight ("1.52× bodyweight"), next to the raw e1RM and as a chart toggle, so a lifter who is cutting can see whether strength is being kept as weight falls. *Verification note: the ratio is only used to follow one person over time, where the body-size bias between individuals does not apply and the ratio directly answers "am I keeping strength per kg". It is never used to compare lifters or to drive any engine decision. Allometric scaling (e1RM ÷ bodyweight^0.67) would be the alternative; it was not used because the exponent is population-derived and adds nothing for a single lifter's trend.* |
| Evidence that *scheduled* deloads help is weak. One RCT (39 trained lifters, 9 weeks) found a 1-week mid-programme deload (full rest) made no difference to lower-body hypertrophy, and the continuous group gained more lower-body strength. | Coleman et al. 2024, *PeerJ*. Bell et al. 2022, *Front Sports Act Living* (coach perceptions and practices, qualitative; opinion, not outcome evidence). Bell et al. 2023, *Sports Med Open* (Delphi consensus of expert opinion). | No calendar deloads. Deload is triggered by stalling plus fatigue signals (§2.3). *Verification note: one small RCT of a single full-rest week; it shows scheduled deloads are not needed, not that autoregulated 10% deloads work. That trigger is expert-opinion based.* |
| Restricted sleep can reduce maximal strength in multi-joint lifts; total sleep deprivation had little effect on strength. | Knowles et al. 2018, *J Sci Med Sport* (systematic review, 17 studies, all rated moderate or weak quality; strength outcomes only, hormonal results conflicting). | Sleep is a readiness input with a small, capped effect (§2.4). *Verification note: the review does not identify a 6 h threshold or a 5% load effect; both are design choices.* |
| Prescribing hard training only on mornings when HRV sat within or above the athlete's own rolling baseline improved endurance performance more than a fixed plan in two small trials. | Vesterinen et al. 2016, *Med Sci Sports Exerc* (40 recreational runners, 8 weeks; the HRV-guided group did fewer moderate- and high-intensity sessions and improved 3000 m time more than the pre-planned group). Javaloyes et al. 2019, *Int J Sports Physiol Perform* (17 well-trained cyclists, 8 weeks; HRV-guided training improved peak power and 40 km time-trial performance more than traditional periodisation). | HRV and resting heart rate from Health are a readiness input with the same small, capped effect as sleep and soreness (§2.4): a morning more than one SD off the lifter's trailing 7-day baseline makes the day 5% lighter and never heavier. *Verification note: both trials are endurance training, used the natural log of RMSSD with a 7-day rolling average and a smallest-worthwhile-change band, and prescribed intensity rather than load. There is no comparable trial in resistance training. Using SDNN (what Health stores), the one-SD rule, the 4-day minimum, resting heart rate as a second signal and the 5% effect are all design choices.* |

### 2.2 Data captured per set

- Exercise, weight, reps, RPE (6–10 in 0.5 steps). RPE is required on working sets.
- Set type: warm-up or working. Only working sets count toward volume. A "Warm-up sets" button
  ramps to the working weight at 50 / 70 / 90 % for 8 / 5 / 2 reps (one 60 % set under 40 kg,
  none under an empty bar). The ladder is coaching convention, not a study result. Any set can
  be flipped between warm-up and working.
- Sets and exercises can be added during the workout; the plan is a starting point, not a cage.
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

Optional daily check-in: sleep hours, soreness 1–5 on the muscles trained today, and, when
turned on in Settings, this morning's heart rate variability (SDNN) and resting heart rate
read from Health.

Sleep can also be filled from Health (off by default; `SleepRule`): the asleep stages between
18:00 yesterday and 14:00 today, clipped to now, with overlapping samples from two sources
merged so a night is never counted twice. A value typed by the lifter always wins, and a
Health-filled sleep on its own is not a check-in: the Today tab still asks. The 18:00 and
14:00 bounds are design choices (any bedtime, a late lie-in, no afternoon nap).

- Sleep < 6 h or soreness ≥ 4 on a target muscle → today's prescribed loads × 0.95,
  with a one-line explanation. The rep targets do not change.
- Heart reading: the baseline is the mean and sample SD of each metric over the 7 days
  before today, needing at least 4 days with a reading (days without one are skipped,
  not zero). The morning is low when HRV is more than one SD below its mean or resting
  heart rate more than one SD above its mean (`HeartRateRule`). Low → the same × 0.95.
  The reading and the baseline it was judged against are stored on the day's entry and
  copied to the session, so the flag can be explained after Health's numbers move.
- The effect is deliberately small and capped at 5%, because the evidence supports
  "sleep matters" and "HRV-guided training can work" much better than any specific
  magnitude (§2.1). Any one low input makes the day low; they never stack.
- Readiness never *raises* loads. It only pulls a bad day back. A high HRV or a low
  resting heart rate changes nothing.
- Health is read only after the lifter turns the feature on, which is what asks for
  permission. Health does not say whether reading was allowed; the Today tab just shows
  that no reading arrived.

### 2.5 Volume guardrails (per muscle per week)

| Weekly hard sets | App behaviour |
|---|---|
| < 10 | "Under the evidence-based minimum" — suggest +1–2 sets on a lift for that muscle. |
| 10–20 | Normal. |
| > 20 | Shown in amber. If the muscle's lifts are also stalling, suggest −2 sets. |

The dose–response direction comes from Schoenfeld 2017 and Pelland 2026; the 10 and 20
set bands themselves are practical heuristics, not thresholds reported in those papers.
The upper band is a prompt, not a hard stop; some people respond well above 20.

### 2.6 Program templates

Shipped defaults, all hitting each muscle ≥ 2×/week:

- Upper / Lower, 4 days
- Push / Pull / Legs, 6 days (or 3 days rotating)
- Full body, 3 days

Each template is just a list of exercises with rep ranges, set counts and increments.
The engine is the same for all of them, so you can edit freely.

**Exercise guide.** Every library exercise has a detail screen: a two-line summary, the
equipment, four cues, a two-frame stick-figure diagram of the movement (`MovementPattern`;
43 patterns shared across the 95 exercises) and a front-and-back muscle map shaded by the
exercise's muscle weightings. Custom exercises get the muscle map and targets only. It opens
from a program day, the picker's info button, the workout's exercise menu and a lift's
progress screen. The cues are coaching convention, not study results.

**Exercise library.** About 95 exercises ship with the app, grouped by main muscle in the
picker, each with muscle weightings, a rep range by its role (3–6 heavy barbell, 6–12
compound, 12–20 isolation) and a plate-step increment. Entries added to the library in a
later version are inserted on launch; an exercise the lifter already has under the same
name is left alone, edits and all. Custom exercises can still be created from the picker.

---

## 3. Nutrition

### 3.1 What the science says

| Finding | Evidence | Design consequence |
|---|---|---|
| In resistance-trained adults, extra gains in fat-free mass from protein supplementation plateau at ~1.6 g/kg/day total intake (95% CI 1.03–2.20). | Morton et al. 2018, *Br J Sports Med* (meta-analysis of 49 RCTs, 1863 participants; break-point from 42 arms, itself not statistically significant, p = 0.079; authors suggest ~2.2 g/kg/day to be safe). | Default protein 1.8 g/kg bodyweight. Range 1.6–2.2. |
| In a deficit, lean athletes are advised 2.3–3.1 g/kg of lean body mass of protein ("most but not all"), 15–30% of calories from fat, and the rest carbohydrate, with weight loss of ~0.5–1%/week. | Helms, Aragon & Fitschen 2014, *J Int Soc Sports Nutr* (narrative review for contest-prep bodybuilders; recommendations, not trial results). | During a cut, protein target rises to 2.2 g/kg. Fat floor 0.7 g/kg. Carbs are the flexible macro. *Verification note: Helms' range is per kg lean mass in very lean athletes; 2.2 g/kg of total bodyweight is a conservative translation for typical users, and the 0.7 g/kg fat floor is not from this paper.* |
| Slower weight loss (targeted 0.7%/week) gave better lean-mass and 1RM outcomes than faster loss (targeted 1.4%/week) in athletes. | Garthe et al. 2011, *Int J Sport Nutr Exerc Metab* (randomised trial, 24 elite athletes; achieved rates were ~0.7% vs ~1.0%/week; lean mass rose 2.1% on the slow plan, unchanged on the fast plan). | Default cut rate 0.5%/week; max selectable 1.0%/week. *Verification note: small sample, elite athletes, and the studied rates were 0.7 and 1.0 achieved; the 0.5% default is extrapolated and 1.0% matches Helms 2014's upper bound.* |
| The "3500 kcal per pound / 7700 kcal per kg" rule is an approximation. The energy needed per unit of weight lost depends on starting body fat (the rule fits obese people and overestimates the deficit needed for lean people), and over months it overpredicts loss because expenditure falls as weight falls. | Hall 2008, *Int J Obes* (body-composition effect); Hall et al. 2011, *Lancet* (dynamic model of falling expenditure). | Used only as the conversion inside the adaptive estimate, which re-measures every two weeks and therefore self-corrects. Never used to predict the future. |
| Consumer wrist wearables estimate energy expenditure poorly: none of 7 devices tested achieved EE error below 20%, while heart rate was adequate. | Shcherbina et al. 2017, *J Pers Med* (60 volunteers, lab protocol; devices were 2016 models). | Watch/phone calorie burn is **not** an input. Expenditure is inferred from intake vs weight change instead. |
| Scale weight follows short-term rhythms (e.g. higher after weekends, lower mid-week) on top of the real trend. | Orsama et al. 2014, *Obes Facts* (80 adults, 4657 weigh-ins); Turicchi et al. 2020, *PLOS ONE* (1421 adults, mean within-week fluctuation 0.35%). *Verification note: the original Bhutani 2017 citation could not be found and was removed. Neither paper quantifies individual daily swings or attributes them to water, glycogen and gut contents; the "1–2%" figure is unsupported here.* | Decisions use an exponentially smoothed trend, never a single weigh-in. |

### 3.2 Adaptive expenditure (the core of the nutrition engine)

Inputs: daily intake (kcal), daily morning bodyweight.

Bodyweight can be filled from Health (off by default; `BodyweightImport`): the earliest sample
of each day over the last 60 days is the morning weigh-in. A day the lifter typed a weight for
is never touched; a day Health filled is updated when Health's number for it changes. A smart
scale that writes to Health then removes the daily typing entirely.

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

**First launch**

- One sheet: units, goal (with the rate and protein each implies), starting split, and an
  optional 8-week demo history. Everything on it is also in Settings. Existing installs skip it.

**Today screen**

- The day's name is a menu of every day in the program. The next in rotation is the default;
  picking another plans that day instead, and once it is completed the rotation carries on
  from it. An unfinished workout can be discarded from here to start a different day.
- One line: today's session name and the single most important change
  ("Bench: 82.5 kg × 3 sets of 6–8, up from 80").
- One line: calorie and protein target with progress bar.
- Readiness check-in if not done (two taps).

**During a workout**

- Prescribed weight × reps for the current set, big.
- Last session's result for the same set, small, underneath.
- Weight and reps are − / + steppers: weight moves by the lift's plate step (5 lb on a
  barbell, 2.5 kg, 2 kg on dumbbells) and snaps to that grid, reps by one, and holding a
  button repeats. The number is still tappable to type, with a Done bar on the keyboard.
  Stepping up from an empty field starts at this session's last set, else last session's
  top set, else the rep target, so a set is usually one or two taps from logged.
- RPE is a menu whose entries say reps left ("RPE 8 · 2 left"), never a bare number.
- The set number at the start of the row is the done button: it fills green once tapped.
- Ticking a set done dims the row and starts the exercise's rest countdown in a bar at the
  bottom: time left, +30 s, skip. A haptic marks the end of the rest. Warm-ups start no timer.
  A local notification fires at zero when the phone is locked (asked for on the first rest).
- "Add set" under each exercise, "Add exercise" at the end, swipe right to mark a warm-up.
- Tapping an exercise's name (or **How to do it** in its ⋯ menu) opens its guide as a sheet:
  the animated movement diagram, cues, muscle map and a History tab. The rest countdown keeps
  running underneath and nothing typed is lost; the sheet is a window onto the exercise, not
  a different screen. A long press on a lift in the Today plan opens the same sheet.
- Each exercise has a ⋯ menu for today only; the program is never edited. **Swap** replaces
  its unlogged sets with another exercise (same-muscle ones listed first) at the weight that
  exercise's own history prescribes. **Skip** drops its unlogged sets. Sets already logged
  stay. A skipped lift leaves no sets, so it gets no verdict and cannot count as a miss.

**Progress screens**

- Per lift: e1RM trend line with sessions as dots. 4-week and 12-week change in bold.
  Once a bodyweight has been logged, the latest e1RM is shown beside its multiple of trend
  bodyweight ("1.52× bodyweight"), the chart can be switched to that ratio, and the change
  rows carry the ratio's change too (§2.1, Jaric 2002). Sessions before the first weigh-in
  have no ratio and are left out of the relative chart.
  Deload sessions carry an orange diamond on the line, and their row says what happened:
  "Deloaded 10%: 80 → 72.5 kg, after stalling 3 sessions". Rows at or past the stall
  threshold say "Stalled N sessions", so the Today card's decision can be traced back.
- Per lift, History tab (on the exercise's guide sheet, so it is also one tap from a workout):
  three personal records, each with the set that produced it and the date, and a comparison to
  the latest session: best e1RM ("120 kg · 100 kg × 5 @ RPE 8 · 3 Mar · latest 115 kg"), the
  heaviest set inside the exercise's rep range, and the most reps at the heaviest weight ever
  lifted. Warm-ups never count. Under them, the last five sessions with their sets and verdicts;
  tapping one opens the session editor, so a mistyped set can be corrected and the record goes
  with it. The trend chart lives on the Progress tab only.
- Per muscle: weekly hard sets as a bar chart against the 10 / 20 bands.
- Bodyweight: trend line over raw dots, with the goal slope drawn as a reference.
- Expenditure: current estimate, confidence, and how it has moved. A "Past checks" row
  unfolds the last six applied adjustments with the trend-vs-goal that drove each one and
  the running total after it.

- Correcting history: a lift's session rows, and the Last session card, open the session
  for editing: weight, reps, RPE, warm-up flag, add or delete sets, the date, or delete the
  whole workout. Verdicts, stall streaks and the next prescription are recomputed, so a
  mistyped set stops poisoning them. Clearing a set's reps drops it on leaving; a session
  left with no sets is removed.

**Importing history**

- Settings → Data → Import from Strong or Hevy reads either app's CSV export (one row per
  set). Workouts come in as finished sessions, so every chart, verdict and personal record
  includes them. Each exercise name in the file is matched onto the library ("Bench Press
  (Barbell)" → Barbell Bench Press); names the matcher is not sure of are shown in orange
  and the lifter picks an exercise, keeps them as a new custom exercise, or skips them. A
  guess is never silently applied: a wrong match would poison a lift's history. Strong's
  current export carries no unit, so the screen asks which the account used. Sessions keep
  the file's key, so importing the same export twice adds nothing.

**Rules of thumb**

- No table has more than four columns on a phone.
- Every number has a unit and a comparison (last time, last week, goal).
- Jargon is translated: "RPE 8" is shown as "RPE 8 · 2 reps left".

---

## 5. Data model (summary)

```
Exercise          id, name, muscles [(muscle, weight)], repRange, increment, setCount, rpeCap, restSeconds
WorkoutSession    id, date, programDayId (+ day name for display), readiness (sleepHours, soreness[muscle], heart reading + baseline)
ReadinessEntry    date (one per day), sleepHours, soreness[muscle], hrvMs, restingHeartRate, each metric's baseline mean/SD/days   — today's check-in, copied onto the session
SetEntry          id, sessionId, exerciseId, order, weight, reps, rpe, isWarmup
BodyweightEntry   date, kg
IntakeEntry       id, date, name, kcal, protein, carbs, fat, fibre
Settings          units, goal, goalRate, proteinPerKg, fatFloorPerKg
AdjustmentEntry   date, kcal, trendRate, goalRate, cumulativeAfter, note   — each applied weekly check
```

Derived, never stored as truth: e1RM per set, weekly volume per muscle, trend weight,
TDEE estimate, verdicts, prescriptions. They are recomputed from the entries so a logging
correction fixes everything downstream.

---

## 6. Tech

- SwiftUI + SwiftData, iOS 26 target, iCloud sync via CloudKit.
- Swift Charts for all trend views.
- HealthKit, each opt-in in Settings: read HRV and resting heart rate, sleep and bodyweight;
  write finished workouts as strength training (deleted with the session).
- No server. No account. Export to CSV from day one.

---

## 7. Open questions

1. ~~Default units: kg or lb?~~ Pounds by default; asked on first launch.
2. ~~Starting split and goal.~~ Asked on first launch; Upper / Lower and Maintain by default.
3. ~~Any existing data to import (Strong, Hevy, MacroFactor export)?~~ Strong and Hevy workout
   exports import from Settings (§4). Nutrition history (MacroFactor) still does not.
4. Is a food database needed in v1, or are saved meals plus manual entry enough to start?

---

## References

DOIs resolve at `https://doi.org/<DOI>`.

- Bell L, Nolan D, Immonen V, Helms E, Dallamore J, Wolf M, et al. (2022). "You can't shoot another bullet until you've reloaded the gun": coaches' perceptions, practices and experiences of deloading in strength and physique sports. *Front Sports Act Living* 4:1073223. doi:10.3389/fspor.2022.1073223
- Bell L, Strafford BW, Coleman M, Androulakis Korakakis P, Nolan D. (2023). Integrating deloading into strength and physique sports training programmes: an international Delphi consensus approach. *Sports Med Open* 9:87. doi:10.1186/s40798-023-00633-0
- Brzycki M. (1993). Strength testing — predicting a one-rep max from reps-to-fatigue. *JOPERD* 64(1):88–90. doi:10.1080/07303084.1993.10606684
- Coleman M, Burke R, Augustin F, Piñero A, Maldonado J, Fisher JP, et al. (2024). Gaining more from doing less? The effects of a one-week deload period during supervised resistance training on muscular adaptations. *PeerJ* 12:e16777. doi:10.7717/peerj.16777
- Epley B. (1985). *Poundage Chart*. Lincoln, NE: Boyd Epley Workout. No DOI (non-journal publication).
- Garthe I, Raastad T, Refsnes PE, Koivisto A, Sundgot-Borgen J. (2011). Effect of two different weight-loss rates on body composition and strength and power-related performance in elite athletes. *Int J Sport Nutr Exerc Metab* 21(2):97–104. doi:10.1123/ijsnem.21.2.97
- Grgic J, Lazinica B, Mikulic P, Krieger JW, Schoenfeld BJ. (2017). The effects of short versus long inter-set rest intervals in resistance training on measures of muscle hypertrophy: a systematic review. *Eur J Sport Sci* 17(8):983–993. doi:10.1080/17461391.2017.1340524
- Hall KD. (2008). What is the required energy deficit per unit weight loss? *Int J Obes* 32(3):573–576. doi:10.1038/sj.ijo.0803720
- Hall KD, Sacks G, Chandramohan D, Chow CC, Wang YC, Gortmaker SL, Swinburn BA. (2011). Quantification of the effect of energy imbalance on bodyweight. *Lancet* 378(9793):826–837. doi:10.1016/S0140-6736(11)60812-X
- Helms ER, Aragon AA, Fitschen PJ. (2014). Evidence-based recommendations for natural bodybuilding contest preparation: nutrition and supplementation. *J Int Soc Sports Nutr* 11:20. doi:10.1186/1550-2783-11-20
- Helms ER, Cronin J, Storey A, Zourdos MC. (2016). Application of the repetitions in reserve-based rating of perceived exertion scale for resistance training. *Strength Cond J* 38(4):42–49. doi:10.1519/SSC.0000000000000218
- Jaric S. (2002). Muscle strength testing: use of normalisation for body size. *Sports Med* 32(10):615–631. doi:10.2165/00007256-200232100-00002
- Javaloyes A, Sarabia JM, Lamberts RP, Moya-Ramon M. (2019). Training prescription guided by heart-rate variability in cycling. *Int J Sports Physiol Perform* 14(1):23–32. doi:10.1123/ijspp.2018-0122
- Knowles OE, Drinkwater EJ, Urwin CM, Lamon S, Aisbett B. (2018). Inadequate sleep and muscle strength: implications for resistance training. *J Sci Med Sport* 21(9):959–968. doi:10.1016/j.jsams.2018.01.012
- LeSuer DA, McCormick JH, Mayhew JL, Wasserstein RL, Arnold MD. (1997). The accuracy of prediction equations for estimating 1-RM performance in the bench press, squat, and deadlift. *J Strength Cond Res* 11(4):211–213. doi:10.1519/00124278-199711000-00001
- Morton RW, Murphy KT, McKellar SR, Schoenfeld BJ, Henselmans M, Helms E, et al. (2018). A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength in healthy adults. *Br J Sports Med* 52(6):376–384 (online 2017; erratum 2020). doi:10.1136/bjsports-2017-097608
- Nuzzo JL, Pinto MD, Nosaka K, Steele J. (2024). Maximal number of repetitions at percentages of the one repetition maximum: a meta-regression and moderator analysis of sex, age, training status, and exercise. *Sports Med* 54:303–321. doi:10.1007/s40279-023-01937-7
- Orsama AL, Mattila E, Ermes M, van Gils M, Wansink B, Korhonen I. (2014). Weight rhythms: weight increases during weekends and decreases during weekdays. *Obes Facts* 7(1):36–47. doi:10.1159/000356147
- Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC. (2026; online 4 Dec 2025). The resistance training dose response: meta-regressions exploring the effects of weekly volume and frequency on muscle hypertrophy and strength gains. *Sports Med* 56(2):481–505. doi:10.1007/s40279-025-02344-w
- Reynolds JM, Gordon TJ, Robergs RA. (2006). Prediction of one repetition maximum strength from multiple repetition maximum testing and anthropometry. *J Strength Cond Res* 20(3):584–592. doi:10.1519/R-15304.1
- Robinson ZP, Pelland JC, Remmert JF, Refalo MC, Jukic I, Steele J, Zourdos MC. (2024). Exploring the dose-response relationship between estimated resistance training proximity to failure, strength gain, and muscle hypertrophy: a series of meta-regressions. *Sports Med* 54(9):2209–2231. doi:10.1007/s40279-024-02069-2
- Schoenfeld BJ, Ogborn D, Krieger JW. (2016). Effects of resistance training frequency on measures of muscle hypertrophy: a systematic review and meta-analysis. *Sports Med* 46(11):1689–1697. doi:10.1007/s40279-016-0543-8
- Schoenfeld BJ, Ogborn D, Krieger JW. (2017). Dose-response relationship between weekly resistance training volume and increases in muscle mass: a systematic review and meta-analysis. *J Sports Sci* 35(11):1073–1082 (online 2016). doi:10.1080/02640414.2016.1210197
- Schoenfeld BJ, Grgic J, Ogborn D, Krieger JW. (2017). Strength and hypertrophy adaptations between low- vs. high-load resistance training: a systematic review and meta-analysis. *J Strength Cond Res* 31(12):3508–3523. doi:10.1519/JSC.0000000000002200
- Schoenfeld BJ, Grgic J, Krieger J. (2019). How many times per week should a muscle be trained to maximize muscle hypertrophy? A systematic review and meta-analysis of studies examining the effects of resistance training frequency. *J Sports Sci* 37(11):1286–1295. doi:10.1080/02640414.2018.1555906
- Schoenfeld BJ, Pope ZK, Benik FM, Hester GM, Sellers J, Nooner JL, et al. (2016). Longer interset rest periods enhance muscle strength and hypertrophy in resistance-trained men. *J Strength Cond Res* 30(7):1805–1812. doi:10.1519/JSC.0000000000001272
- Shcherbina A, Mattsson CM, Waggott D, Salisbury H, Christle JW, Hastie T, Wheeler MT, Ashley EA. (2017). Accuracy in wrist-worn, sensor-based measurements of heart rate and energy expenditure in a diverse cohort. *J Pers Med* 7(2):3. doi:10.3390/jpm7020003
- Vesterinen V, Nummela A, Heikura I, Laine T, Hynynen E, Botella J, Häkkinen K. (2016). Individual endurance training prescription with heart rate variability. *Med Sci Sports Exerc* 48(7):1347–1354. doi:10.1249/MSS.0000000000000910
- Turicchi J, O'Driscoll R, Horgan G, Duarte C, Palmeira AL, Larsen SC, Heitmann BL, Stubbs RJ. (2020). Weekly, seasonal and holiday body weight fluctuation patterns among individuals engaged in a European multi-centre behavioural weight loss maintenance intervention. *PLOS ONE* 15(4):e0232152. doi:10.1371/journal.pone.0232152
- Zourdos MC, Klemp A, Dolan C, Quiles JM, Schau KA, Jo E, et al. (2016). Novel resistance training-specific rating of perceived exertion scale measuring repetitions in reserve. *J Strength Cond Res* 30(1):267–275. doi:10.1519/JSC.0000000000001049
- Zourdos MC, Goldsmith JA, Helms ER, Trepeck C, Halle JL, Mendez KM, et al. (2021). Proximity to failure and total repetitions performed in a set influences accuracy of intraset repetitions in reserve-based rating of perceived exertion. *J Strength Cond Res* 35(S2):S158–S165. doi:10.1519/JSC.0000000000002995

References checked against Crossref, PubMed and Europe PMC on 2026-10-18; citations marked "Verification note" above are where the paper supports the direction of a rule but not its exact numbers.
