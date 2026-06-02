local Object = {}
local Objects = {}

--////////////////////////////////////////////////////////////
-- DEEP COPY HELPER
-- only copies actual plain tables
-- skips: primitives (already value types), Instances (should be referenced), functions (live on Methods)
--////////////////////////////////////////////////////////////
local function deepCopy(original: any): any
	if typeof(original) == "table" then
		local copy = {}
		for key, value in pairs(original) do
			copy[key] = deepCopy(value)
		end
		return copy
	end
	return original
end

--////////////////////////////////////////////////////////////
-- TYPES
--////////////////////////////////////////////////////////////

export type Adornee = Instance

export type MainFunction = (any) -> ()

export type Template = {
	Main: MainFunction,
	[string]: any
}

export type InstanceObject = {
	Adornee: Adornee,
	IsDestroyed: boolean,
	Destroy: (self: any) -> (),
	[string]: any
}

export type Class = {
	Template: Template,
	NewVar: (name: string, value: any) -> (),
	NewFunc: (name: string, func: (...any) -> ()) -> (),
	SetMain: (func: MainFunction) -> (),
	New: (Adornee) -> InstanceObject,
	Extend: (self: any, className: string) -> Class,
}

--////////////////////////////////////////////////////////////
-- INTERNAL CLASS BUILDER
-- used by both Object.New and Class:Extend
-- parentClass is nil for root classes, set for inherited ones
--////////////////////////////////////////////////////////////
local function buildClass(className: string, parentClass: any?): any

	-- DUPLICATE CLASS PROTECTION
	if Objects[className] then
		error("Object: class '" .. className .. "' already exists! Did you define it twice?")
	end

	local ClassTable = {}
	Objects[className] = ClassTable

	--////////////////////////////////////////////////////////////
	-- INTERNAL STORAGE
	-- Variables = data   → deep copied per instance
	-- Methods   = logic  → shared via metatable chain
	--////////////////////////////////////////////////////////////
	ClassTable.Variables = {}
	ClassTable.Methods = {}
	ClassTable.ClassName = className
	ClassTable.Parent = parentClass

	-- INHERITANCE SETUP
	if parentClass then
		-- inherit default variable values from parent
		for key, value in pairs(parentClass.Variables) do
			ClassTable.Variables[key] = deepCopy(value)
		end

		-- method chain: this class → parent class → grandparent → ...
		-- if a method isnt found here, Lua walks up automatically
		setmetatable(ClassTable.Methods, {
			__index = parentClass.Methods
		})

		-- inherit parent Main by default (can be overridden with SetMain)
		ClassTable.Main = parentClass.Main
	else
		ClassTable.Main = function() end
	end

	-- Template points at Variables for API compatibility
	ClassTable.Template = ClassTable.Variables

	--////////////////////////////////////////////////////////////
	-- NewVar
	--////////////////////////////////////////////////////////////
	ClassTable.NewVar = function(name: string, value: any)
		if typeof(name) ~= "string" then
			warn("NewVar [" .. className .. "]: name must be a string")
			return
		end
		if typeof(value) == "function" then
			warn("NewVar [" .. className .. "]: value cannot be a function, use NewFunc instead")
			return
		end
		ClassTable.Variables[name] = value
	end

	--////////////////////////////////////////////////////////////
	-- NewFunc
	--////////////////////////////////////////////////////////////
	ClassTable.NewFunc = function(name: string, func: (...any) -> ())
		if name == "Main" then
			warn("NewFunc [" .. className .. "]: 'Main' is reserved. Use SetMain instead.")
			return
		end
		if typeof(name) ~= "string" or typeof(func) ~= "function" then
			warn("NewFunc [" .. className .. "]: invalid name or function")
			return
		end
		ClassTable.Methods[name] = func
	end

	--////////////////////////////////////////////////////////////
	-- SetMain
	--////////////////////////////////////////////////////////////
	ClassTable.SetMain = function(func: MainFunction)
		if typeof(func) == "function" then
			ClassTable.Main = func
		else
			warn("SetMain [" .. className .. "]: Main must be a function")
		end
	end

	--////////////////////////////////////////////////////////////
	-- Extend
	-- creates a child class that inherits everything from this one
	-- usage: local Zombie = Enemy:Extend("Zombie")
	--////////////////////////////////////////////////////////////
	ClassTable.Extend = function(_self: any, childName: string)
		return buildClass(childName, ClassTable)
	end

	--////////////////////////////////////////////////////////////
	-- New (INSTANCE CREATION)
	--////////////////////////////////////////////////////////////
	ClassTable.New = function(Adornee: Adornee): InstanceObject

		local object = {}
		object.Adornee = Adornee
		object.IsDestroyed = false

		-- copy Variables into instance (deepCopy only triggers on plain tables)
		for key, value in pairs(ClassTable.Variables) do
			object[key] = deepCopy(value)
		end

		-- METATABLE
		-- missing keys walk up the method chain automatically
		setmetatable(object, {
			__index = ClassTable.Methods
		})

		-- DESTROY
		local function destroy()
			if object.IsDestroyed then return end
			object.IsDestroyed = true
			for key in pairs(object) do
				object[key] = nil
			end
			setmetatable(object, nil)
		end

		object.Destroy = destroy

		-- ADORNEE BINDING
		Adornee.Destroying:Connect(destroy)

		-- AUTO RUN MAIN (pcall so one broken instance doesnt kill the system)
		local ok, err = pcall(ClassTable.Main, object)
		if not ok then
			warn("Object [" .. className .. "] Main error: " .. tostring(err))
		end

		return object
	end

	return ClassTable
end

--////////////////////////////////////////////////////////////
-- PUBLIC API
--////////////////////////////////////////////////////////////

-- creates a root class with no parent
function Object.New(className: string): Class
	return buildClass(className, nil)
end

-- returns any existing class by name from anywhere in your codebase
function Object.GetClass(className: string): Class?
	local class = Objects[className]
	if not class then
		warn("Object.GetClass: class '" .. className .. "' does not exist")
		return nil
	end
	return class
end

return Object
