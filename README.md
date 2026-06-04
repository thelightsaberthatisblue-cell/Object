# Object
A reactive OOP entity framework for Roblox Luau.

Object gives you a clean, production-ready class system with inheritance, signals, reactive state, generation trees, and full instance lifecycle management — all with a simple, consistent API.

---

## Installation

Add to your `wally.toml`:

```toml
[dependencies]
Object = "thelightsaberthatisblue-cell/object@1.0.0"
```

Then require it in your script:

```lua
local Object = require(ReplicatedStorage.Packages.Object)
```

---

## Core Concepts

| Concept | What it is |
|---|---|
| **Class** | A blueprint. Defines variables, methods, signals, and lifecycle hooks. |
| **Instance** | A live object created from a class. Has its own independent state. |
| **Adornee** | The object the instance is bound to. Not limited to Roblox Instances. |
| **Main** | Auto-runs when an instance is created. |
| **SetCleanup** | Auto-runs before an instance is destroyed. The reverse of Main. |

---

## Quick Start

```lua
local Object = require(ReplicatedStorage.Packages.Object)

-- define a class
local Enemy = Object.New("Enemy")

Enemy.NewVar("Health", 100)
Enemy.NewVar("Name", "Enemy", "immutable")

Enemy.NewFunc("TakeDamage", function(self, dmg)
    self.Health -= dmg
end)

Enemy.SetMain(function(self)
    print(self.Name .. " spawned with " .. self.Health .. " HP")
end)

-- create an instance
local goblin = Enemy.New(workspace.GoblinPart)
goblin:TakeDamage(25)
print(goblin.Health) -- 75
```

---

## Class Definition API

### `Object.New(className)`
Creates a new root class.
```lua
local Enemy = Object.New("Enemy")
```

### `Class:Extend(childName)`
Creates a child class that inherits everything from the parent.
```lua
local Zombie = Enemy:Extend("Zombie")
local FastZombie = Zombie:Extend("FastZombie")
```

### `Object.GetClass(className)`
Retrieves any class from anywhere in your codebase by name.
```lua
local Enemy = Object.GetClass("Enemy")
```

---

## Variables

### `Class.NewVar(name, value, mode?)`
Defines a variable on the class.

| Mode | Behavior |
|---|---|
| `"copy"` (default) | Deep copied per instance. Each instance gets its own independent value. Use for mutable state like `Health`, cooldowns, position offsets. |
| `"ref"` | Shared reference across all instances. Changes on one instance affect all. Use for shared config tables you want to update globally. |
| `"immutable"` | Shared reference, write-protected. Errors if any instance tries to overwrite it. Use for constants like `MaxHealth`, `Name`, `Damage`. |

```lua
Enemy.NewVar("Health", 100)                    -- copy (default)
Enemy.NewVar("MaxHealth", 100, "immutable")    -- shared, locked
Enemy.NewVar("Config", difficultyTable, "ref") -- shared, mutable
```

---

## Methods

### `Class.NewFunc(name, func)`
Standard method. Receives `(self, ...)`.
Use `self:Super()` to call the parent class version (injection style).
```lua
Enemy.NewFunc("TakeDamage", function(self, dmg)
    self.Health -= dmg
end)
```

### `Class.NewSuperFunc(name, func)`
Super-arg style. Receives `(self, super, ...)`.
`super` is the immediate parent's version of this method, passed as a plain argument.
Zero instance mutation. Preferred over `self:Super()` in performance-sensitive code.
```lua
Zombie.NewSuperFunc("TakeDamage", function(self, super, dmg)
    super()            -- calls Enemy:TakeDamage(self)
    self.Health -= 5   -- zombie takes extra damage
end)
```

### `Class.NewHyperFunc(name, targetClass, func)`
Hyper-arg style. Receives `(self, hyper, ...)`.
`hyper` is a specific ancestor's version, skipping everything in between.
```lua
-- FastZombie wants Enemy's TakeDamage, skipping Zombie's version
FastZombie.NewHyperFunc("TakeDamage", "Enemy", function(self, hyper, dmg)
    hyper()
    self.Health -= dmg
end)
```

### `Class:Include(mixin)`
Injects a flat table of functions into the class as methods.
Useful for shared behavior across unrelated classes (flying, poison, stealth).
```lua
local FlyMixin = {
    Fly = function(self)
        print(self.Adornee.Name .. " is flying!")
    end
}

Zombie:Include(FlyMixin)
goblin:Fly()
```

---

## Lifecycle

### `Class.SetMain(func)`
Runs automatically when an instance is created. `self` is the instance.
```lua
Enemy.SetMain(function(self)
    print("spawned!")
end)
```

### `Class.SetCleanup(func)`
Runs before the instance is destroyed. `self` is still fully intact.
Use this to clean up coroutines, external connections, or anything you created in Main.
```lua
Enemy.SetCleanup(function(self)
    self.AICoroutine:Cancel()
    self.ExternalConnection:Disconnect()
end)
```

---

## Adornee

The adornee is the object an instance is bound to — not strictly limited to Roblox Instances. It can be a Part, Model, ScreenGui, or any runtime value.

When a Roblox Instance adornee is destroyed, the instance is automatically destroyed too. Non-Instance adornees have no auto-destroy binding — the developer manages their lifecycle manually or via `SetCleanup`.

### Manual adornee (developer passes it)
```lua
local goblin = Enemy.New(workspace.GoblinPart)
```

### Class adornee (framework clones it)
```lua
Enemy.SetAdornee(workspace.EnemyTemplate)
Enemy.SetAdorneeParent(workspace.Enemies) -- optional, defaults to workspace

local goblin = Enemy.New() -- clones EnemyTemplate automatically
```

### Adornee pool (random clone per instance)
```lua
Enemy.AddAdornee(workspace.ZombieRig1)
Enemy.AddAdornee(workspace.ZombieRig2)
Enemy.AddAdornee(workspace.ZombieRig3)

local goblin = Enemy.New() -- picks a random one and clones it
```

You can also mix — pass an adornee manually even when a class adornee is set:
```lua
if specialCase then
    Enemy.New(workspace.SpecialRig) -- uses this directly
else
    Enemy.New() -- uses class adornee
end
```

---

## Signals

Signals are per-instance event objects. Firing one instance's signal does not affect any other instance.

**Events are developer-driven. HyperEvents are engine-driven.** See [HyperSync](#hypersync-reactive-state) for the reactive counterpart.

### `Class.NewSignal(name)`
Defines a signal at class level. Each instance gets its own independent Signal object.
```lua
Enemy.NewSignal("Died")
Enemy.NewSignal("TookDamage")
```

### Usage on instances
```lua
local goblin = Enemy.New(workspace.Part)

-- persistent listener
goblin.Events.Died:Connect(function()
    XP:Add(10)
end)

-- fires once then auto-disconnects
goblin.Events.TookDamage:Once(function(dmg)
    print("first hit: " .. dmg)
end)

-- yields until signal fires, returns Fire() args
task.spawn(function()
    local dmg = goblin.Events.TookDamage:Wait()
    print("waited for hit: " .. dmg)
end)

-- developer fires manually inside methods
Enemy.NewFunc("TakeDamage", function(self, dmg)
    self.Health -= dmg
    self.Events.TookDamage:Fire(dmg)

    if self.Health <= 0 then
        self.Events.Died:Fire()
    end
end)
```

---

## HyperSync (Reactive State)

HyperSync automatically fires a signal when a condition becomes true after any instance property mutation.
The condition is only checked after writes, not on a loop.
It fires once per flip — resets when the condition becomes false again.

### `Class.HyperSync(signalName, conditionFunc)`
Auto-registers the signal too — no separate `NewSignal` needed.
```lua
Enemy.HyperSync("Died", function(self)
    return self.Health < 1
end)

Enemy.HyperSync("Critical", function(self)
    return self.Health < 25
end)
```

### Listening to HyperSync signals
HyperSync signals live on `object.HyperEvents`, separate from manual `object.Events`:
```lua
goblin.HyperEvents.Died:Connect(function()
    print("goblin died automatically!")
end)

goblin.HyperEvents.Critical:Once(function()
    print("goblin is critical!")
end)
```

---

## Generations

Instances can spawn new instances of their own class via `self.New()`.
The framework automatically tracks generation data on every instance.

Generations are not limited to spawning enemies — they represent any parent-child runtime lineage. Use them for splitting projectiles, branching dialogue trees, chained ability effects, or anything where instances spawn related instances.

| Property | What it is |
|---|---|
| `self.Gen` | Generation number. `1` for direct class spawns. |
| `self.GenParent` | The instance that spawned this one. `nil` for gen 1. |
| `self.GenChildren` | All instances this one has spawned. |
| `self.GenSiblings` | Other instances spawned by the same parent. Always live. |

```lua
-- when a zombie dies, spawn 2 more if under gen 3
Zombie.SetCleanup(function(self)
    if self.Gen < 3 then
        self.New() -- spawns Zombie with Gen = self.Gen + 1
        self.New()
    end
end)

local zombie = Zombie.New(workspace.ZombiePart)
-- zombie.Gen == 1
-- when it dies → spawns 2x Gen 2 zombies
-- when those die → spawns 2x Gen 3 zombies each
-- Gen 3 zombies die → nothing spawns, chain ends
```

---

## Instance Management

### `Class.GetAll()`
Returns a list of all currently active instances of this class.
```lua
local allEnemies = Enemy.GetAll()
print(#allEnemies .. " enemies alive")
```

### `Class.DestroyAll()`
Destroys all active instances of this class. Safe to call mid-wave.
```lua
Enemy.DestroyAll() -- end of wave cleanup
```

### `instance:Destroy()`
Manually destroys a single instance.
```lua
goblin:Destroy()
```

### `instance.IsDestroyed`
Boolean flag. `true` after the instance has been destroyed.
```lua
if not goblin.IsDestroyed then
    goblin:TakeDamage(10)
end
```

---

## Class Sealing

Once `Class.New()` is called for the first time, the class is **sealed**.
Any attempt to call `NewVar`, `NewFunc`, `SetMain`, `HyperSync`, etc. after that will throw an error.

This prevents silent bugs where instances created before and after a mutation have different shapes.

```lua
local goblin = Enemy.New(workspace.Part)
Enemy.NewVar("Speed", 10) -- ERROR: class is sealed
```

---

## Full Example — Zombie Wave System

```lua
local Object = require(ReplicatedStorage.Packages.Object)

-- BASE CLASS
local Enemy = Object.New("Enemy")
Enemy.NewVar("Health", 100)
Enemy.NewVar("MaxHealth", 100, "immutable")
Enemy.NewSignal("TookDamage")
Enemy.HyperSync("Died", function(self) return self.Health < 1 end)

Enemy.NewFunc("TakeDamage", function(self, dmg)
    self.Health -= dmg
    self.Events.TookDamage:Fire(dmg)
end)

Enemy.SetMain(function(self)
    print(self.Adornee.Name .. " spawned")
end)

-- ZOMBIE (extends Enemy)
local Zombie = Enemy:Extend("Zombie")
Zombie.NewVar("InfectionChance", 0.3)
Zombie.AddAdornee(workspace.ZombieRig1)
Zombie.AddAdornee(workspace.ZombieRig2)
Zombie.SetAdorneeParent(workspace.Enemies)

-- split into 2 on death if under gen 3
Zombie.SetCleanup(function(self)
    if self.Gen < 3 then
        self.New()
        self.New()
    end
end)

-- FAST ZOMBIE (extends Zombie)
local FastZombie = Zombie:Extend("FastZombie")
FastZombie.NewVar("Speed", 30)

-- skips Zombie's TakeDamage, uses Enemy's directly
FastZombie.NewHyperFunc("TakeDamage", "Enemy", function(self, hyper, dmg)
    hyper()
end)

-- SPAWN A WAVE
for i = 1, 10 do
    local zombie = Zombie.New()
    zombie.HyperEvents.Died:Connect(function()
        print("zombie died at gen " .. zombie.Gen)
    end)
end

-- END OF WAVE
task.wait(60)
Zombie.DestroyAll()
FastZombie.DestroyAll()
```

---

## License
MIT
