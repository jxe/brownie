# .med File Syntax

A `.med` file is a plain-text meditation script. The app parses it into timed steps: spoken text, pauses, and countdowns. Files are stored in iCloud and synced to the app.

## Title

The first `#` line becomes the meditation title.

```
# Morning Prayer
```

Additional `#` lines are treated as comments and ignored.

## Tags (old)

Older scripts may have `#tags` on the title line (`# Morning Prayer #prayer`) or on a `#` line just after it. The app no longer uses them: they stay in the file as they are and mean nothing. Evergreen and eras live outside the script, in folders and the library index.

## The library folder

Scripts live in folders that say where they show up:

```
eras.json           the eras, newest first
2026-11-21/         an era's folder, named by the day it started: what belongs to that era,
                    when it's the latest era it belongs to
2026-09-19/
Evergreen/          shown in every era
Older/              made before the first era and never brought along
Archive/            put away
```

Files are named `yyyy-MM-dd-title-slug.med`, from the day it was made and its title, with `-2` (etc.) when another script in any folder has the name. The filename is how the app keeps a meditation's listening stats and store link (on each device), so renaming one in Finder or Files starts its stats over; renaming it in the app carries them along. Moving a file between folders is fine.

**Eras** are stretches of time, from the day one is started until the next one. A meditation belongs to the era it was made in (by its filename's date), and to any later era it was brought along to; its file sits in the folder of the latest one, so the newest era's folder holds what that era shows. Bringing one along moves its file there. When a meditation belongs to an era that neither its date nor its folder says (brought along twice, or Evergreen or archived after being brought along), that era's `kept` lists it:

```json
[{"id": "…", "started": "2026-11-21", "kept": []},
 {"id": "🎸", "started": "2026-09-19", "kept": ["2026-06-30-morning"]}]
```

A `.med` dropped at the top of the folder (from the Mac, say) joins the current era. Move a file into an era's folder and that becomes its latest era.

## Spoken Text

Any line that isn't a special construct is spoken aloud by the TTS engine.

```
Dear Lord,
Help me connect with the good people.
Amen.
```

## Pauses

**Middle dots** (`·`) pause for 1 second each:

```
Hello · world          # 1s pause between words
Stand still ····       # 4s pause after
```

**Numeric durations** use `″` for seconds and `′` for minutes:

```
Rest. 22″              # 22-second pause after "Rest."
Hold this. 1′          # 60-second pause
Stretch left 10″ right 10″
```

These can be mixed freely on a line with spoken text.

## Countdowns

`⏳` followed by a duration creates a countdown timer (the app announces remaining time):

```
Can I spend 3 minutes, choosing only life? ··· ⏳3′
Stand ···· ⏳40″ ··
```

## Pools

A pool is a named list of items. Each time the pool is referenced, a random item is drawn (shuffled, no repeats until exhausted).

**Define** with `~ name` or `~name` in the first column of a line, followed by indented items. Only that starts a pool: the `~name` line must not be indented, and the line right under it must be.

```
~ fbs
  What if nobody cared if I made progress?
  So tired of nonstop progress.
  If only I'd found the right people.
```

**Reference** with `~name` (no space):

```
~fbs ·· Feel 22″ Done.
```

A `~name` alone on a line with no indented items under it is a reference too, so a whole line can be drawn from a pool:

```
~opening
Breathe in 4″ out 4″
```

Pool items themselves can reference other pools — references are resolved recursively when the item is drawn.

Defining a pool again with the same name replaces it from that point on. Inside the new pool's items, its own name means the pool it replaced, so a pool can build on an earlier one:

```
~ q
  what would be wrong
  what would be right

~q
  If my purpose is just ~purposes, ~q?
  Am I ~actions?
```

Here `~q` inside the second pool draws from the first `~q`, and later script lines draw from the second. A pool never draws from itself: with no earlier pool of that name, the reference is read out as text.

### Remembered Picks

To use the same pick more than once, bind it to a name with `~name=pool`. That draws from `pool` and speaks it like a normal reference, and every later `~name` repeats the same item instead of drawing again:

```
~ fears
  being alone
  being judged

I take 30 seconds to feel my fear of ~x=fears. 30″ I try ~x.
# If "being judged" is drawn: "...my fear of being judged. ... I try being judged."
```

Each `~x=fears` draws fresh and replaces the old pick, so inside a repeat every repetition gets its own pick, reused within that repetition:

```
I feel ~f=fears. 20″ I breathe with ~f. 10″ ×3
```

A binding lasts from where it is made until it is rebound, across lines. It takes precedence over a pool with the same name, and a pick's gender marker carries over to pronouns wherever it is reused.

### Gendered Pools

Pool items can have a gender marker (`♀` or `♂`). When a gendered item is drawn, pronouns in subsequent text on the same line are resolved (they/them/their become she/her/hers or he/him/his):

```
~ person
  Stephanie ♀
  Ryan ♂

I'm with ~person. · I appreciate them for their kindness.
# If "Stephanie" is drawn: "I appreciate her for her kindness."
```

### Weighted Pools

Pool items can include one or more rock markers (`🪨`) to make them more likely to be drawn. Each rock adds one extra selection weight, and rocks are not spoken aloud:

```
~ thought
  I can let this be simple.
  This one has more pull. 🪨
  This one has even more pull. 🪨🪨
```

The first item has weight 1, the second has weight 2, and the third has weight 3. Weighted pools still avoid drawing the same item twice in a row whenever another item is available, including when the pool refills for a new cycle. The one exception is a pool of just two items: when it refills, either item can come first, so it doesn't settle into a fixed back-and-forth, though the same item can then come twice in a row at the turnover.

## Repeats

`×N` (multiplication sign, or `x`) goes **after** what it repeats, so a script reads in the order it plays.

### Repeat a line: `text ×N`

`×N` at the end of a line repeats everything to its left:

```
I'm with ~person, not making progress. · Is it better ~why? 12″ ×4
```

This plays the line 4 times. The trailing `12″` separates each repetition.

### Repeat part of a line, or several lines: `[ … ] ×N`

`×N` right after a `]` repeats just the bracketed group:

```
Neck stretch [left · right ·] ×3 back · forward ·
```

Groups can span lines. Indenting inside them is optional and just for reading:

```
[
  Breathe in ····
  Breathe out ····
] ×5
```

### Breaks between repeats: `‖REST`

`‖` (double vertical line, or `||`) followed by a duration is a **break**. Inside a repeat it rests between rounds and is skipped after the last one. The app says "Rest." / "Again." around each break, "One last time." before the final round, and "End" after it. A break with no duration rests 28″. Outside any repeat, a break is just a pause.

A plain duration like `28″` is a pause that always happens; a break only happens *between* repetitions.

```
~fbs ·· Feel 22″ Done. 6″ ×5 ‖28″ ×3
```

Read left to right: the line five times, a 28-second break, and all of that three times.

The same thing as a block:

```
[
  ~fbs ·· Feel 22″ Done. 6″ ×5
  ‖28″
] ×3
```

### Nesting

Each `×N` repeats everything to its left on its line (or inside its group), including earlier repeats, so they nest outward:

```
~x ~y 11″ ×4 ‖28″ ×5        # 5 rounds of (4 × the line), 28″ breaks between rounds
[left · right ·] ×2 ×3      # the group twice, all of that three times
```

### Old prefix repeats (deprecated)

Older scripts put the count first. These still play, but the editor strikes them through and suggests the new form:

| Old (deprecated) | New |
|---|---|
| `×4 text 12″` | `text 12″ ×4` |
| `×5𝄐28″ ×4 text 11″` | `text 11″ ×4 ‖28″ ×5` |
| `×4` + indented body | `[` body `] ×4` |
| `×5𝄐28″` + indented body | `[` body, then `‖28″` `] ×5` |
| `x5\|28" x4 ~x 11"` | `~x 11" x4 \|\|28" x5` |

`𝄐` (the fermata) only ever meant "rest between stanzas" in the old stanza form; use `‖` instead.

## Complete Examples

### Prayer (linear)

```
# Prayer

Dear Lord, ··

Help me connect with the good people, · and let us ground each other. ····

Please Lord. · Grant me a long life, and a good one. ·

Amen.
```

### HPN (pool + nested repeat)

```
# HPN

~ fbs
  What if people like it when I don't make progress?
  So tired of nonstop progress.
  If only I'd found the right people.

~fbs ·· Feel 22″ Done. 6″ ×5 ‖28″ ×3
```

### Yes to Life (countdown timers)

```
# 3-3-4 Yes to Life

Can I spend 3 minutes, choosing only life? ··· ⏳3′ ·····

Rest. 22″

Can I spend 3 minutes, choosing only life? ··· ⏳3′ ·····

Rest. 22″

Can I spend 4 minutes, choosing only life? ··· ⏳4′ ·····
```

### Movement (sequential with timers)

```
# Tai Chi

Neck stretch left · right · back · forward ·
Neck roll 8″
Reverse 8″
Knees · rotate in first 6″
reverse 6″
Finally, stand ···· ⏳40″ ··
Done!
```

## Special Characters Quick Reference

| Character | Name | Meaning | ASCII alternative |
|-----------|------|---------|-------------------|
| `#` | Hash | Title (first) or comment | — |
| `·` | Middle dot (U+00B7) | 1-second pause (stack for more) | — |
| `″` | Double prime (U+2033) | Seconds unit (e.g. `22″`) | `"` (e.g. `22"`) |
| `′` | Prime (U+2032) | Minutes unit (e.g. `3′`) | `'` (e.g. `3'`) |
| `⏳` | Hourglass (U+23F3) | Countdown timer | — |
| `~name` (column 1, indented items under it) | Tilde + name | Pool definition. Space after `~` optional. Without items under it, a reference | — |
| `~name` (inline) | Tilde + name | Pool reference (or a remembered pick, if `name` was bound) | — |
| `~name=pool` | Tilde + name = pool | Draw from `pool` and remember it as `name` | — |
| `×` | Multiplication (U+00D7) | Repeat what comes before it N times (`text ×5`, `[…] ×5`) | `x` (e.g. `x5`) |
| `[` `]` | Brackets | Group to repeat, on one line or across lines | — |
| `‖` | Double vertical line (U+2016) | Break between repeats (`‖28″`) | `\|\|` (e.g. `\|\|28"`) |
| `𝄐` | Fermata (U+1D110) | Deprecated: old stanza rest (`×5𝄐28″`) | `\|` |
| `♀` | Female sign (U+2640) | Female gender on pool item | — |
| `♂` | Male sign (U+2642) | Male gender on pool item | — |
| `🪨` | Rock (U+1FAA8) | Extra weight on pool item | — |

All-ASCII example equivalent to `~x ~y 11″ ×4 ‖28″ ×5`:

```
~x ~y 11" x4 ||28" x5
```
