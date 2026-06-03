--////////////////////////////////////////////////////////////
-- OBJECT FRAMEWORK
-- by [you]
--
-- public API surface - require this in your scripts
-- internal logic lives in Core.luau and Signal.luau
--
-- USAGE:
--   local Object = require(path.to.Object)
--
--   local Enemy = Object.New("Enemy")
--   Enemy.NewVar("Health", 100)
--   Enemy.NewFunc("TakeDamage", function(self, dmg) self.Health -= dmg end)
--   Enemy.SetMain(function(self) print(self.Adornee.Name .. " spawned!") end)
--
--   local Zombie = Enemy:Extend("Zombie")
--   Zombie.NewVar("Infection", 0.5)
--
--   local goblin = Zombie.New(workspace.ZombieRig)
--////////////////////////////////////////////////////////////

local Core = require(script.Core)

local Object = {}

-- creates a new root class with no parent
function Object.New(className: string): Core.Class
	return Core.buildClass(className, nil)
end

-- returns any existing class by name from anywhere in your codebase
function Object.GetClass(className: string): Core.Class?
	local class = Core.Objects[className]
	if not class then
		warn("Object.GetClass: class '" .. className .. "' does not exist")
		return nil
	end
	return class
end

return Object
