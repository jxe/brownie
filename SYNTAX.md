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

### Gendered Pools

Pool items can have a gender marker (`♀` or `♂`). When a gendered item is drawn, pronouns in subsequent text on the same line are resolved (they/them/their become she/her/hers or he/him/his):

```
~ person
  Stephanie ♀
  Ryan ♂

I'm with ~person. · I appreciate them for their kindness.
# If "Stephanie" is drawn: "I appreciate her for her kindness."
```

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
| `~name` (inline) | Tilde + name | Pool reference | — |
| `×` | Multiplication (U+00D7) | Repeat count (`×5 text` or `×5𝄐28″`) | `x` (e.g. `x5`) |
| `𝄐` | Fermata (U+1D110) | Rest between stanzas (`×5𝄐28″`) | `\|` (e.g. `x5\|28"`) |
| `♀` | Female sign (U+2640) | Female gender on pool item | — |
| `♂` | Male sign (U+2642) | Male gender on pool item | — |

All-ASCII example equivalent to `×5𝄐28″ ×4 ~x ~y 11″`:

```
x5|28" x4 ~x ~y 11"
```
