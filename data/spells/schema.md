# Spell Database Schema

## `base.json`

Top-level keys:

| Key | Type | Description |
|-----|------|-------------|
| `spells` | Record<spellId, PlayerSpell> | Player spells (interrupts, CC, defensives) |
| `enemySpells.dungeons` | Record<dungeonKey, Record<spellId, EnemySpell>> | Enemy interruptible/notable spells per dungeon |
| `defensives` | Record<class, Record<spec, DefensiveSpell[]>> | Defensive cooldowns by class/spec |
| `drCategories` | Record<categoryName, DrCategory> | Diminishing Returns category definitions |

### PlayerSpell

```json
{
  "name": "Spell Name",
  "class": "WARRIOR",
  "type": "interrupt|cc|defensive|other",
  "interruptible": false,
  "cooldownSec": 15,
  "ccCategory": "stun|incapacitate|disorient|silence|root",
  "durationSec": 6,
  "breakOnDamage": false
}
```

### EnemySpell

```json
{
  "name": "Spell Name",
  "casterId": 12345,
  "casterName": "Boss Name",
  "interruptible": true,
  "castDurationSec": 2.5,
  "priority": "high|medium|low|avoid",
  "notes": "What happens if not interrupted"
}
```

### DefensiveSpell

```json
{
  "spellId": 642,
  "name": "Divine Shield",
  "durationSec": 8,
  "cooldownSec": 300,
  "isExternal": false
}
```

### DrCategory

```json
{
  "resetTimerSec": 18,
  "pvpImmunityAfter": 2,
  "pveImmunityAfter": 3,
  "spells": [408, 853, 1833]
}
```

## Dungeon file naming convention

Dungeon keys match the encounter name lowercased with spaces replaced by hyphens:
- `"Darkflame Cleft"` → `darkflame-cleft`
- `"Priory of the Sacred Flame"` → `priory-of-the-sacred-flame`
