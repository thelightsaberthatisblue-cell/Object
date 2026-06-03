# Object Framework (Roblox LuaU)

A lightweight, structured object runtime system for Roblox LuaU that provides class-like behavior, lifecycle management, signals, inheritance, and controlled state handling.

It is designed for mid-scale games that need clean architecture without heavy ECS complexity.

---

# 📦 Features

* Class-based object system (OOP-style API)
* Inheritance via `Extend`
* Instance lifecycle (`Main` → runtime → `Destroy` → `Cleanup`)
* Per-instance signals (event system)
* Variable modes:

  * `copy` (deep copied per instance)
  * `ref` (shared reference)
  * `immutable` (read-only shared reference)
* Method system with optional super support
* Adornee system for instance binding (optional Roblox Instances)
* Class sealing after first instantiation (prevents runtime mutation bugs)
* Central registry for global class access

---

# 📥 Installation

Place the module in your Roblox project and require it:

```lua
local Object = require(path.to.Object)
```

---

# 🚀 Quick Start

```lua
local Object = require(path.to.Object)

local Enemy = Object.New("Enemy")

Enemy.NewVar("Health", 100)

Enemy.NewFunc("TakeDamage", function(self, dmg)
	self.Health -= dmg
end)

Enemy.SetMain(function(self)
	print(self.Adornee.Name .. " spawned!")
end)

local Zombie = Enemy:Extend("Zombie")
Zombie.NewVar("Infection", 0.5)

local zombie = Zombie.New(workspace.ZombieRig)
```

---

# 🧠 Core Concepts

## 📌 Class Creation

```lua
local Class = Object.New("ClassName")
```

Creates a new root class.

---

## 📌 Variables

```lua
Class.NewVar(name, value, mode?)
```

Modes:

* `"copy"` → deep copied per instance (default)
* `"ref"` → shared reference
* `"immutable"` → shared reference, cannot be overwritten

---

## 📌 Methods

```lua
Class.NewFunc("MethodName", function(self, ...)
end)
```

Methods are shared across all instances.

---

## 📌 Super Calls

If a method exists in a parent class, you can call it using:

```lua
self:Super()
```

Used inside overridden methods.

---

## 📌 Super Argument Mode (Optional)

```lua
Class.NewSuperFunc("MethodName", function(self, super, ...)
	super()
end)
```

Avoids instance mutation overhead.

---

## 📌 Signals

```lua
Class.NewSignal("Died")
```

Usage:

```lua
local conn = instance.Events.Died:Connect(function()
	print("Dead")
end)

instance.Events.Died:Fire()
```

---

## 📌 Main (Lifecycle Entry)

```lua
Class.SetMain(function(self)
	-- runs on instance creation
end)
```

This is the primary behavior entry point for each instance.

---

## 📌 Cleanup (Lifecycle Exit)

```lua
Class.SetCleanup(function(self)
	-- runs before Destroy
end)
```

Used for cleaning up connections, loops, and runtime state.

---

## 📌 Inheritance

```lua
local Child = Parent:Extend("Child")
```

Child classes inherit:

* Variables
* Methods
* Signals
* Cleanup logic

---

## 📌 Adornee System (Optional)

Bind instances to Roblox objects:

```lua
Class.SetAdornee(workspace.Model)
```

or:

```lua
Class.AddAdornee(workspace.Model1)
Class.AddAdornee(workspace.Model2)
```

Instances can automatically clone and bind to these.

---

## 📌 Instance Creation

```lua
local obj = Class.New(optionalAdornee)
```

---

## 📌 Destroy

```lua
obj:Destroy()
```

Cleans up:

* signals
* adornee (if owned)
* cleanup function
* instance state

---

# ⚙️ Design Philosophy

This framework is built around:

> “Each object has one lifecycle and one behavior entry point.”

* `Main` defines behavior
* Methods define reusable actions
* Signals define communication
* Cleanup ensures safe teardown

---

# ⚠️ Notes

* Class mutation after first `New()` call is restricted (sealed behavior)
* Designed for structured gameplay systems, not high-frequency ECS simulation
* Performance scales best with controlled AI/update loops

---
