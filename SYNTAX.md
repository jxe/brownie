# .med File Syntax

A `.med` file is a plain-text meditation script. The app parses it into timed steps: spoken text, pauses, and countdowns. Files are stored in iCloud and synced to the app.

## Title

The first `#` line becomes the meditation title.

```
# Morning Prayer
```

Additional `#` lines are treated as comments and ignored.

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

Define with `~` followed by indented items:

```
~ fbs
  What if nobody cared if I made progress?
  So tired of nonstop progress.
  If only I'd found the right people.
```

Reference with `{name}`:

```
{fbs} ·· Feel 22″ Done.
```

### Gendered Pools

Pool items can have a gender marker (`♀` or `♂`). When a gendered item is drawn, pronouns in subsequent text on the same line are resolved (they/them/their become she/her/hers or he/him/his):

```
~ person
  Stephanie ♀
  Ryan ♂

I'm with {person}. · I appreciate them for their kindness.
# If "Stephanie" is drawn: "I appreciate her for her kindness."
```

## Sections

Sections define repeated stanza structures. Two forms:

### Simple: `§COUNT REST`

Runs the indented body COUNT times, with REST seconds of silence between stanzas. The app automatically says "Rest." / "Again." between stanzas and "One last time." before the final one.

```
§5 28″
  I'm with someone, not making progress. · It's {why}. 12″
```

This runs the body 5 times with 28s rest between each.

### Nested: `§OUTER×INNER INNER_DELAY OUTER_REST`

Runs INNER cycles per stanza, with INNER_DELAY between cycles, repeated OUTER stanzas with OUTER_REST between them.

```
§3×5 6″ 28″
  {fbs} ·· Feel 22″ Done.
```

This means: 3 stanzas, each containing 5 cycles of the body. 6s pause between cycles within a stanza, 28s rest between stanzas.

## Complete Examples

### Prayer (linear)

```
# Prayer

Dear Lord, ··

Help me connect with the good people, · and let us ground each other. ····

Please Lord. · Grant me a long life, and a good one. ·

Amen.
```

### HPN (pool + nested section)

```
# HPN

~ fbs
  What if people like it when I don't make progress?
  So tired of nonstop progress.
  If only I'd found the right people.

§3×5 6″ 28″
  {fbs} ·· Feel 22″ Done.
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

| Character | Name | Meaning |
|-----------|------|---------|
| `#` | Hash | Title (first) or comment |
| `·` | Middle dot (U+00B7) | 1-second pause (stack for more) |
| `″` | Double prime (U+2033) | Seconds unit (e.g. `22″`) |
| `′` | Prime (U+2032) | Minutes unit (e.g. `3′`) |
| `⏳` | Hourglass (U+23F3) | Countdown timer |
| `~` | Tilde | Pool definition |
| `{ }` | Braces | Pool reference |
| `§` | Section sign (U+00A7) | Section/stanza block |
| `×` | Multiplication (U+00D7) | Nested section (outer×inner) |
| `♀` | Female sign (U+2640) | Female gender on pool item |
| `♂` | Male sign (U+2642) | Male gender on pool item |
