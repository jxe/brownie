# .med File Syntax

A `.med` file is a plain-text meditation script. The app parses it into timed steps: spoken text, pauses, and countdowns. Files are stored in iCloud and synced to the app.

## Title

The first `#` line becomes the meditation title.

```
# Morning Prayer
```

Additional `#` lines are treated as comments and ignored.

## Tags

Tags can appear on the title line itself:

```
# Morning Prayer #prayer #morning
```

Or on a separate `#` line immediately after the title (the line must contain only `#tag` words):

```
# Morning Prayer
#prayer #morning
```

Tags are used by the meditation list to filter and group meditations.

### Eras

Some tags are **eras**: periods of practice, usually named with an emoji (`#🎸`, `#🔥🔥`). A meditation can belong to several eras. `eras.json`, next to the `.med` files, lists which tags are eras, newest first; the first one is the current era:

```json
[{"tag": "🎸", "started": "2026-09-19"}, {"tag": "🔥🔥", "started": "2026-06-21"}]
```

`#timeless` marks meditations that are always shown, whatever era is selected. The list shows only era tags; other tags stay in the file but are hidden.

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

**Define** with `~ name` or `~name` at the start of a line, followed by indented items:

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

Pool items themselves can reference other pools — references are resolved recursively when the item is drawn.

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
×3 I feel ~f=fears. 20″ I breathe with ~f. 10″
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

The first item has weight 1, the second has weight 2, and the third has weight 3. Weighted pools still avoid drawing the same item twice in a row whenever another item is available, including when the pool refills for a new cycle.

## Repeats

Use `×` (multiplication sign) to repeat lines or blocks.

### Simple repeat: `×N text...`

Repeats the line N times:

```
×4 I'm with ~person, not making progress. · Is it better ~why? 12″
```

This runs the line 4 times. Any trailing pause (the `12″`) naturally separates each repetition.

### Stanza block: `×N𝄐REST`

Repeats an indented body N times with REST seconds of silence between stanzas. The app automatically says "Rest." / "Again." between stanzas and "One last time." before the final one. `𝄐` is the fermata sign (U+1D110).

```
×5𝄐28″
  I'm with someone, not making progress. · It's ~why. 12″
```

This runs the body 5 times with 28s rest between each.

### Nested repeats

Body lines inside a stanza block can themselves use `×N` for inner repetition:

```
×5𝄐28″
  ×4 I'm with ~person, not making progress. · Is it better ~why? 12″
```

This means: 5 stanzas, each containing 4 repetitions of the line. The `12″` at the end of the line acts as the pause between inner cycles. 28s rest between stanzas.

### One-liner

The whole structure can be on a single line:

```
×5𝄐28″ ×4 I'm with ~person, not making progress. · Is it better ~why? 12″
```

The inner repeat can also be written in block form:

```
×5𝄐28″
  ×4
    I'm with ~person, not making progress. · Is it better ~why? 12″
```

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

×3𝄐28″ ×5 ~fbs ·· Feel 22″ Done. 6″
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
| `~name` (line start) | Tilde + name | Pool definition (followed by indented items). Space after `~` optional. | — |
| `~name` (inline) | Tilde + name | Pool reference (or a remembered pick, if `name` was bound) | — |
| `~name=pool` | Tilde + name = pool | Draw from `pool` and remember it as `name` | — |
| `×` | Multiplication (U+00D7) | Repeat count (`×5 text` or `×5𝄐28″`) | `x` (e.g. `x5`) |
| `𝄐` | Fermata (U+1D110) | Rest between stanzas (`×5𝄐28″`) | `\|` (e.g. `x5\|28"`) |
| `♀` | Female sign (U+2640) | Female gender on pool item | — |
| `♂` | Male sign (U+2642) | Male gender on pool item | — |
| `🪨` | Rock (U+1FAA8) | Extra weight on pool item | — |

All-ASCII example equivalent to `×5𝄐28″ ×4 ~x ~y 11″`:

```
x5|28" x4 ~x ~y 11"
```
