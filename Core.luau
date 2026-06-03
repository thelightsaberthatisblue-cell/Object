--////////////////////////////////////////////////////////////
-- CORE
-- internal engine of the Object framework
-- handles: deepCopy, class building, registry
-- not meant to be required directly by developers
--////////////////////////////////////////////////////////////

local Signal = require(script.Parent.Signal)

--////////////////////////////////////////////////////////////
-- DEEP COPY HELPER
-- only copies plain tables, guards against circular references
-- skips: primitives (value types), Instances (pass by ref), functions (live on Methods)
--////////////////////////////////////////////////////////////
local function deepCopy(original: any, visited: {}?): any
	if typeof(original) == "table" then
		visited = visited or {}
		if visited[original] then return visited[original] end
		local copy = {}
		visited[original] = copy
		for key, value in pairs(original) do
			copy[key] = deepCopy(value, visited)
		end
		return copy
	end
	return original
end

--////////////////////////////////////////////////////////////
-- REGISTRY
-- all classes live here, keyed by className
-- accessed via Object.GetClass() publicly
--////////////////////////////////////////////////////////////
local Objects = {}

--////////////////////////////////////////////////////////////
-- CLASS BUILDER
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
	-- Variables   = { [name] = { value, mode } }
	--   mode "copy"      (default) = deep copied per instance
	--   mode "ref"                 = shared reference, never copied, can overwrite
	--   mode "immutable"           = shared reference, never copied, overwrite errors
	-- Methods     = shared via metatable chain (registered via NewFunc)
	-- SuperMethods = methods registered via NewSuperFunc
	--   these receive (self, super, ...) instead of (self, ...)
	--   super is passed as a plain argument — zero instance mutation
	-- Signals     = signal names, each instance gets its own Signal objects
	-- _adornee    = single class adornee template (SetAdornee)
	-- _pool       = list of adornee templates (AddAdornee)
	-- _adorneeParent = where cloned adornees get parented (default workspace)
	-- _cleanup    = optional developer-defined cleanup callback
	-- _adorneeMode = "single" | "pool" | nil
	-- _sealed     = true after first New() call, errors on further class mutation
	--////////////////////////////////////////////////////////////
	ClassTable.Variables    = {}
	ClassTable.Methods      = {}
	ClassTable.SuperMethods = {} -- tracks which methods use the arg-style super
	ClassTable.Signals      = {}
	ClassTable.ClassName    = className
	ClassTable.Parent       = parentClass
	ClassTable._adornee     = nil
	ClassTable._pool        = nil
	ClassTable._adorneeParent = workspace
	ClassTable._cleanup     = nil
	ClassTable._adorneeMode = nil
	ClassTable._sealed      = false

	-- INHERITANCE SETUP
	if parentClass then
		for name, entry in pairs(parentClass.Variables) do
			ClassTable.Variables[name] = { value = entry.value, mode = entry.mode }
		end
		for name in pairs(parentClass.Signals) do
			ClassTable.Signals[name] = true
		end
		setmetatable(ClassTable.Methods, {
			__index = parentClass.Methods
		})
		-- inherit which methods are super-arg style
		for name in pairs(parentClass.SuperMethods) do
			ClassTable.SuperMethods[name] = true
		end
		ClassTable.Main     = parentClass.Main
		ClassTable._cleanup = parentClass._cleanup
	else
		ClassTable.Main = function() end
	end

	ClassTable.Template = ClassTable.Variables

	--////////////////////////////////////////////////////////////
	-- SEAL GUARD
	-- errors if developer mutates the class after first New() call
	-- prevents silent instance desync bugs
	--////////////////////////////////////////////////////////////
	local function sealGuard(method: string)
		if ClassTable._sealed then
			error(className .. "." .. method .. ": class is sealed. You cannot mutate a class after New() has been called.")
		end
	end

	--////////////////////////////////////////////////////////////
	-- NewVar
	-- mode: "copy"      (default) = deep copied per instance
	--       "ref"                 = shared reference, overwrite allowed
	--       "immutable"           = shared reference, overwrite blocked
	--////////////////////////////////////////////////////////////
	ClassTable.NewVar = function(name: string, value: any, mode: string?)
		sealGuard("NewVar")
		if typeof(name) ~= "string" then
			warn("NewVar [" .. className .. "]: name must be a string")
			return
		end
		if typeof(value) == "function" then
			warn("NewVar [" .. className .. "]: value cannot be a function, use NewFunc instead")
			return
		end
		local resolvedMode = mode or "copy"
		if resolvedMode ~= "copy" and resolvedMode ~= "ref" and resolvedMode ~= "immutable" then
			warn("NewVar [" .. className .. "]: mode must be 'copy', 'ref', or 'immutable'. Defaulting to 'copy'")
			resolvedMode = "copy"
		end
		ClassTable.Variables[name] = { value = value, mode = resolvedMode }
	end

	--////////////////////////////////////////////////////////////
	-- NewFunc
	-- standard method registration
	-- receives (self, ...)
	-- use self:Super() to call parent version (injection style)
	--////////////////////////////////////////////////////////////
	ClassTable.NewFunc = function(name: string, func: (...any) -> ())
		sealGuard("NewFunc")
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
	-- NewSuperFunc
	-- super-arg style method registration
	-- receives (self, super, ...) — super is a plain argument, not instance state
	-- zero instance mutation, no rawget/rawset during the call
	-- use when overriding a parent method and calling super frequently
	-- parent version is bound at instance creation, not at call time
	--
	-- usage:
	--   Zombie.NewSuperFunc("TakeDamage", function(self, super, dmg)
	--       super()           -- calls Enemy:TakeDamage(self)
	--       self.Health -= dmg
	--   end)
	--////////////////////////////////////////////////////////////
	ClassTable.NewSuperFunc = function(name: string, func: (...any) -> ())
		sealGuard("NewSuperFunc")
		if name == "Main" then
			warn("NewSuperFunc [" .. className .. "]: 'Main' is reserved. Use SetMain instead.")
			return
		end
		if typeof(name) ~= "string" or typeof(func) ~= "function" then
			warn("NewSuperFunc [" .. className .. "]: invalid name or function")
			return
		end
		ClassTable.Methods[name]      = func
		ClassTable.SuperMethods[name] = true -- flag for proxy builder
	end

	--////////////////////////////////////////////////////////////
	-- NewSignal
	-- defines a signal at class level
	-- each instance gets its own independent Signal object on creation
	--////////////////////////////////////////////////////////////
	ClassTable.NewSignal = function(name: string)
		sealGuard("NewSignal")
		if typeof(name) ~= "string" then
			warn("NewSignal [" .. className .. "]: name must be a string")
			return
		end
		ClassTable.Signals[name] = true
	end

	--////////////////////////////////////////////////////////////
	-- SetMain
	--////////////////////////////////////////////////////////////
	ClassTable.SetMain = function(func)
		sealGuard("SetMain")
		if typeof(func) == "function" then
			ClassTable.Main = func
		else
			warn("SetMain [" .. className .. "]: Main must be a function")
		end
	end

	--////////////////////////////////////////////////////////////
	-- SetCleanup
	-- the reverse of Main — runs before the instance gets nuked
	-- use for coroutines, external connections, anything created in Main
	-- self is still fully intact when this runs
	--////////////////////////////////////////////////////////////
	ClassTable.SetCleanup = function(func)
		sealGuard("SetCleanup")
		if typeof(func) == "function" then
			ClassTable._cleanup = func
		else
			warn("SetCleanup [" .. className .. "]: cleanup must be a function")
		end
	end

	--////////////////////////////////////////////////////////////
	-- SetAdornee
	-- sets a single class-level adornee template
	-- every New() call with no argument clones this
	-- mutually exclusive with AddAdornee
	--////////////////////////////////////////////////////////////
	ClassTable.SetAdornee = function(adornee: any)
		sealGuard("SetAdornee")
		if ClassTable._adorneeMode == "pool" then
			error("SetAdornee [" .. className .. "]: cannot use SetAdornee and AddAdornee together")
		end
		ClassTable._adornee     = adornee
		ClassTable._adorneeMode = "single"
	end

	--////////////////////////////////////////////////////////////
	-- AddAdornee
	-- adds to the class adornee pool
	-- every New() call with no argument picks a random one and clones it
	-- mutually exclusive with SetAdornee
	--////////////////////////////////////////////////////////////
	ClassTable.AddAdornee = function(adornee: any)
		sealGuard("AddAdornee")
		if ClassTable._adorneeMode == "single" then
			error("AddAdornee [" .. className .. "]: cannot use SetAdornee and AddAdornee together")
		end
		ClassTable._pool        = ClassTable._pool or {}
		ClassTable._adorneeMode = "pool"
		table.insert(ClassTable._pool, adornee)
	end

	--////////////////////////////////////////////////////////////
	-- SetAdorneeParent
	-- where cloned adornees get parented (default: workspace)
	--////////////////////////////////////////////////////////////
	ClassTable.SetAdorneeParent = function(parent: Instance)
		sealGuard("SetAdorneeParent")
		ClassTable._adorneeParent = parent
	end

	--////////////////////////////////////////////////////////////
	-- Include (MIXINS)
	-- injects a flat table of functions into Methods
	-- instances get mixin methods automatically via metatable
	--////////////////////////////////////////////////////////////
	ClassTable.Include = function(_self: any, mixin: { [string]: (...any) -> () })
		sealGuard("Include")
		if typeof(mixin) ~= "table" then
			warn("Include [" .. className .. "]: mixin must be a table of functions")
			return
		end
		for name, func in pairs(mixin) do
			if typeof(func) == "function" then
				ClassTable.Methods[name] = func
			else
				warn("Include [" .. className .. "]: skipping '" .. tostring(name) .. "' - not a function")
			end
		end
	end

	--////////////////////////////////////////////////////////////
	-- Extend
	--////////////////////////////////////////////////////////////
	ClassTable.Extend = function(_self: any, childName: string)
		return buildClass(childName, ClassTable)
	end

	--////////////////////////////////////////////////////////////
	-- New (INSTANCE CREATION)
	--////////////////////////////////////////////////////////////
	ClassTable.New = function(adornee: any?)

		-- seal class — no further mutation allowed after first spawn
		ClassTable._sealed = true

		local resolvedAdornee = adornee
		local ownsAdornee     = false

		-- ADORNEE RESOLUTION
		-- priority: argument → pool → single class adornee → error
		if resolvedAdornee == nil then
			if ClassTable._adorneeMode == "pool" and ClassTable._pool then
				local template = ClassTable._pool[math.random(1, #ClassTable._pool)]
				if typeof(template) == "Instance" then
					resolvedAdornee        = template:Clone()
					resolvedAdornee.Parent = ClassTable._adorneeParent
				else
					resolvedAdornee = template
				end
				ownsAdornee = true

			elseif ClassTable._adorneeMode == "single" and ClassTable._adornee ~= nil then
				if typeof(ClassTable._adornee) == "Instance" then
					resolvedAdornee        = ClassTable._adornee:Clone()
					resolvedAdornee.Parent = ClassTable._adorneeParent
				else
					resolvedAdornee = ClassTable._adornee
				end
				ownsAdornee = true

			else
				error("Object.New [" .. className .. "]: no adornee provided and no class adornee set. Pass one to New() or call SetAdornee/AddAdornee.")
			end
		end

		local object           = {}
		object.Adornee         = resolvedAdornee
		object.IsDestroyed     = false

		-- SMART STATE COPY
		-- "copy"      = deep copy (full independence)
		-- "ref"       = shared reference (no copy, overwrite allowed)
		-- "immutable" = shared reference (no copy, overwrite blocked via __newindex)
		local immutableKeys = {}
		for name, entry in pairs(ClassTable.Variables) do
			if entry.mode == "copy" then
				object[name] = deepCopy(entry.value)
			else
				object[name] = entry.value
				if entry.mode == "immutable" then
					immutableKeys[name] = true
				end
			end
		end

		-- SIGNALS
		object.Events = {}
		for name in pairs(ClassTable.Signals) do
			object.Events[name] = Signal.new()
		end

		--////////////////////////////////////////////////////////////
		-- SUPER PROXY
		-- built once per instance at creation time
		--
		-- two super styles handled here:
		--
		-- 1. INJECTION STYLE (NewFunc)
		--    self:Super() — Super pre-bound closure set on instance before call
		--    small per-call cost (two rawget/rawset) but familiar syntax
		--
		-- 2. ARGUMENT STYLE (NewSuperFunc)
		--    function(self, super, ...) — super passed as plain argument
		--    zero instance mutation, no rawget/rawset, cleanest runtime behavior
		--    super closure is bound once here at spawn time
		--
		-- methods with no parent version: direct reference, zero overhead
		-- lookup chain: instance → SuperProxy → ClassTable.Methods
		--////////////////////////////////////////////////////////////
		local parentMethods = getmetatable(ClassTable.Methods) and getmetatable(ClassTable.Methods).__index
		local SuperProxy    = {}

		for name, method in pairs(ClassTable.Methods) do
			local parentMethod = parentMethods and parentMethods[name]

			if parentMethod then
				-- pre-bind the parent call once at spawn, not per call
				local boundSuper = function()
					return parentMethod(object)
				end

				if ClassTable.SuperMethods[name] then
					-- ARGUMENT STYLE: super passed as second argument
					-- zero instance mutation during the call
					SuperProxy[name] = function(s, ...)
						return method(s, boundSuper, ...)
					end
				else
					-- INJECTION STYLE: super injected onto instance, restored after
					SuperProxy[name] = function(s, ...)
						local previousSuper = rawget(s, "Super")
						rawset(s, "Super", boundSuper)
						local results = table.pack(method(s, ...))
						rawset(s, "Super", previousSuper)
						return table.unpack(results, 1, results.n)
					end
				end
			else
				-- no parent version — zero overhead, direct reference
				SuperProxy[name] = method
			end
		end

		-- inherited methods not overridden in this class fall through
		setmetatable(SuperProxy, { __index = ClassTable.Methods })

		--////////////////////////////////////////////////////////////
		-- METATABLE
		-- __index    = SuperProxy (direct table lookup, fast)
		-- __newindex = blocks immutable field writes
		--////////////////////////////////////////////////////////////
		setmetatable(object, {
			__index    = SuperProxy,
			__newindex = function(t, key, value)
				if immutableKeys[key] then
					error("Object [" .. className .. "]: attempt to overwrite immutable field '" .. key .. "' — write blocked")
				end
				rawset(t, key, value)
			end
		})

		-- DESTROY
		local adorneeConnection
		local function destroy()
			if object.IsDestroyed then return end
			object.IsDestroyed = true

			-- run developer cleanup first (before anything gets nuked)
			if ClassTable._cleanup then
				local ok, err = pcall(ClassTable._cleanup, object)
				if not ok then
					warn("Object [" .. className .. "] cleanup error: " .. tostring(err))
				end
			end

			-- disconnect adornee binding
			if adorneeConnection then
				adorneeConnection:Disconnect()
				adorneeConnection = nil
			end

			-- destroy cloned adornee if framework owns it
			if ownsAdornee then
				if typeof(resolvedAdornee) == "Instance" then
					resolvedAdornee:Destroy()
				else
					resolvedAdornee = nil
				end
			end

			-- disconnect and clear all signals
			if object.Events then
				for _, signal in pairs(object.Events) do
					signal:DisconnectAll()
				end
			end

			-- nuke instance
			for key in pairs(object) do
				object[key] = nil
			end
			setmetatable(object, nil)
		end

		object.Destroy = destroy

		-- ADORNEE BINDING
		-- only hook Destroying if adornee is a Roblox Instance
		if typeof(resolvedAdornee) == "Instance" then
			adorneeConnection = resolvedAdornee.Destroying:Connect(destroy)
		end

		-- AUTO RUN MAIN
		local ok, err = pcall(ClassTable.Main, object)
		if not ok then
			warn("Object [" .. className .. "] Main error: " .. tostring(err))
		end

		return object
	end

	return ClassTable
end

return {
	buildClass = buildClass,
	Objects    = Objects,
}
