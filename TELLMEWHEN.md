# Using DoesItDie with TellMeWhen (WoW Forever)

This fork adds two things to DoesItDie:

1. **`DoesItDieAPI`**, a global table with the addon's DoT estimates, for TellMeWhen Lua conditions (or WeakAuras, macros, other addons).
2. **On-screen icons** (`/did screen`): a kill icon and a row of DoT icons you can drag anywhere, or pin onto a TellMeWhen icon.

## The one thing TellMeWhen can't do

On Forever, the target's health is a **secret value**. Addon code can't compare it or do math with it, and that includes TellMeWhen's conditions. So no Lua condition can return "my DoTs will kill it" as true or false, and nothing in this fork claims to. DoesItDie's kill icon gets around this without comparing anything: it's a 10,000px StatusBar whose max is the target's health and whose value is the DoT damage. The icon rides the end of the fill and only comes into view inside a small clipped window when the bar is full.

So for "show an icon when my DoTs will kill the target":

- **Option A (recommended):** `/did screen only`, then drag the kill icon where you want it (`/did screen unlock` … `/did screen lock`).
- **Option B:** pin that kill icon on top of a TellMeWhen icon: `/did screen anchor TellMeWhen_Group1_Icon1`. TMW icon frames are named `TellMeWhen_Group<g>_Icon<i>` (profile groups) or `TellMeWhen_GlobalGroup<g>_Icon<i>` (global groups). Hover an icon and run `/fstack` if you're unsure. The DoT row can be pinned under a frame the same way with `/did screen dotsanchor <FrameName>`.

Everything else (amounts, counts, timers, which DoTs are up) is a plain number and works fine in TMW conditions.

## API (all plain values, safe to compare)

`unit` defaults to `"target"` (pass `nil` to use the default). `spell` is a name (any case) or a spell ID. On Forever each rank has its own ID, so names are usually better.

| Call | Returns |
|---|---|
| `DoesItDieAPI.GetRemaining(unit)` | damage your DoTs still have to deal, number of DoTs counted (the same number the target-frame marker shows) |
| `DoesItDieAPI.HasDot(unit, spell)` | `true` if that DoT of yours is on the unit |
| `DoesItDieAPI.DotTimeLeft(unit, spell)` | seconds left, `0` if missing |
| `DoesItDieAPI.DotDamage(unit, spell)` | damage that DoT still has to deal, `0` if missing |
| `DoesItDieAPI.CountDots(unit)` | number of your DoTs on the unit |
| `DoesItDieAPI.GetDots(unit)` | list of `{ name, spellID, school, appliedAt, duration, expiresAt, timeLeft, damage, waiting, ticksSeen, confident }`, oldest first |
| `DoesItDieAPI.GetDot(unit, spell)` | one of those entries, or `nil` |
| `DoesItDieAPI.GetKillBar(unit)` | damage, **secret** health. Only for StatusBars; never compare the second value |

Note: TMW's own debuff icons and conditions read the target's auras, and Forever blocks that in combat. DoesItDie tracks your DoTs from your casts and the damage events instead, so `HasDot` / `DotTimeLeft` also work as a replacement for "is my DoT up".

## TellMeWhen recipes

Add these in an icon's **Conditions** tab: **+ → Miscellaneous → Lua (Advanced)**, and paste the expression.

Each one starts with `DoesItDieAPI and`, so it returns false instead of throwing an error if DoesItDie isn't loaded.

**Corruption missing on the target** (a reminder icon): use a Condition Icon type showing the Corruption texture.

```lua
DoesItDieAPI and UnitCanAttack("player", "target") and not DoesItDieAPI.HasDot("target", "Corruption")
```

**Refresh Immolate soon** (under 3 s left, but still up):

```lua
DoesItDieAPI and DoesItDieAPI.HasDot("target", "Immolate") and DoesItDieAPI.DotTimeLeft("target", "Immolate") < 3
```

**Stop dotting: your DoTs already have a lot of damage queued.** This is a fixed amount, not a kill check, since health is secret:

```lua
DoesItDieAPI and DoesItDieAPI.GetRemaining() >= 1500
```

**All three of my DoTs are up:**

```lua
DoesItDieAPI and DoesItDieAPI.CountDots() >= 3
```

To show the remaining damage as a number or bar, use a Lua Value icon (below). Its `[Value]` DogTag prints the number.

### Lua Value icon: a "kill bar" inside TellMeWhen (experimental)

Icon type **Lua Value (Advanced)**, view **Bar**, function body:

```lua
return DoesItDieAPI.GetKillBar("target")
```

The bar is full when your DoTs will kill the target. TellMeWhen's bar module accepts secret values on Forever. One part is untested: the Lua Value icon type runs `tonumber()` on the returned values. If the icon only says "Unusable result", the client is rejecting the secret there; use Option A/B above instead. For a plain-number bar that always works, try:

```lua
return DoesItDieAPI.GetRemaining("target"), 3000   -- remaining DoT damage on a 0-3000 scale
```

## `/did screen` commands

```
/did screen                 toggle on/off
/did screen unlock | lock   drag the icons (preview shown while unlocked)
/did screen only            on-screen icons on, target-frame marker and kill icon off
/did screen frame on|off    the original target-frame display
/did screen kill on|off     the kill icon
/did screen dots on|off     the DoT icon row
/did screen size <px>       kill icon size     /did screen dotsize <px>   DoT icon size
/did screen anchor <Frame>  pin the kill icon on a frame (e.g. TellMeWhen_Group1_Icon1); 'anchor off' to unpin
/did screen dotsanchor <Frame>  pin the DoT row under a frame
/did screen unit target|focus
/did screen reset
```

The kill icon uses the icon you picked in `/did` (Kill icon tab).
