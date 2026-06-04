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
-- subclasses are stored as "ParentName.SubName"
-- preventing name collisions across different parent classes
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
	-- Variables       = { [name] = { value, mode } }
	--   mode "copy"       (default) = deep copied per instance
	--   mode "ref"                  = shared reference, never copied, can overwrite
	--   mode "immutable"            = shared reference, never copied, overwrite errors
	-- Methods         = shared via metatable chain (registered via NewFunc)
	-- SuperMethods    = { [name] = true } methods using arg-style super (NewSuperFunc)
	-- HyperMethods    = { [name] = targetClassName } methods using arg-style hyper (NewHyperFunc)
	-- Signals         = { [name] = true } signal names, instances get own Signal objects
	-- HyperSyncs      = { [signalName] = wrappedConditionFunc }
	--   condition is pre-wrapped once at registration — no pcall in hot path
	-- Subs            = { [subName] = subClassName } registered subclasses
	--   instances get a proxy table per sub for gen-tracked spawning
	-- ActiveInstances = weak-keyed table { [instance] = true }
	--   weak keys mean GC can collect instances even if Destroy was never called
	--   prevents memory leaks from forgotten references
	-- _adornee        = single class adornee template (SetAdornee)
	-- _pool           = list of adornee templates (AddAdornee)
	-- _adorneeParent  = where cloned adornees get parented (default workspace)
	-- _cleanup        = optional developer-defined cleanup callback
	-- _adorneeMode    = "single" | "pool" | nil
	-- _sealed         = true after first New() call, errors on further class mutation
	--////////////////////////////////////////////////////////////
	ClassTable.Variables       = {}
	ClassTable.Methods         = {}
	ClassTable.SuperMethods    = {}
	ClassTable.HyperMethods    = {}
	ClassTable.Signals         = {}
	ClassTable.HyperSyncs      = {}
	ClassTable.Subs            = {} -- { [subName] = fullSubClassName }
	ClassTable.ClassName       = className
	ClassTable.Parent          = parentClass
	ClassTable._adornee        = nil
	ClassTable._pool           = nil
	ClassTable._adorneeParent  = workspace
	ClassTable._cleanup        = nil
	ClassTable._adorneeMode    = nil
	ClassTable._sealed         = false

	-- WEAK ACTIVE INSTANCES
	ClassTable.ActiveInstances = setmetatable({}, { __mode = "k" })

	-- INHERITANCE SETUP
	if parentClass then
		for name, entry in pairs(parentClass.Variables) do
			ClassTable.Variables[name] = { value = entry.value, mode = entry.mode }
		end
		for name in pairs(parentClass.Signals) do
			ClassTable.Signals[name] = true
		end
		for name, wrappedCond in pairs(parentClass.HyperSyncs) do
			ClassTable.HyperSyncs[name] = wrappedCond
		end
		setmetatable(ClassTable.Methods, {
			__index = parentClass.Methods
		})
		for name in pairs(parentClass.SuperMethods) do
			ClassTable.SuperMethods[name] = true
		end
		for name, target in pairs(parentClass.HyperMethods) do
			ClassTable.HyperMethods[name] = target
		end
		ClassTable.Main     = parentClass.Main
		ClassTable._cleanup = parentClass._cleanup
	else
		ClassTable.Main = function() end
	end

	ClassTable.Template = ClassTable.Variables

	--////////////////////////////////////////////////////////////
	-- SEAL GUARD
	--////////////////////////////////////////////////////////////
	local function sealGuard(method: string)
		if ClassTable._sealed then
			error(className .. "." .. method .. ": class is sealed. You cannot mutate a class after New() has been called.")
		end
	end

	--////////////////////////////////////////////////////////////
	-- NewVar
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
		ClassTable.SuperMethods[name] = true
	end

	--////////////////////////////////////////////////////////////
	-- NewHyperFunc
	--////////////////////////////////////////////////////////////
	ClassTable.NewHyperFunc = function(name: string, targetClassName: string, func: (...any) -> ())
		sealGuard("NewHyperFunc")
		if name == "Main" then
			warn("NewHyperFunc [" .. className .. "]: 'Main' is reserved. Use SetMain instead.")
			return
		end
		if typeof(name) ~= "string" or typeof(targetClassName) ~= "string" or typeof(func) ~= "function" then
			warn("NewHyperFunc [" .. className .. "]: invalid arguments")
			return
		end
		ClassTable.Methods[name]      = func
		ClassTable.HyperMethods[name] = targetClassName
	end

	--////////////////////////////////////////////////////////////
	-- NewSignal
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
	-- HyperSync
	--////////////////////////////////////////////////////////////
	ClassTable.HyperSync = function(signalName: string, conditionFunc: (any) -> boolean)
		sealGuard("HyperSync")
		if typeof(signalName) ~= "string" then
			warn("HyperSync [" .. className .. "]: signalName must be a string")
			return
		end
		if typeof(conditionFunc) ~= "function" then
			warn("HyperSync [" .. className .. "]: condition must be a function")
			return
		end
		local wrappedCondition = function(instance)
			local ok, result = pcall(conditionFunc, instance)
			if not ok then
				warn("HyperSync [" .. className .. "] condition error: " .. tostring(result))
				return false
			end
			return result
		end
		ClassTable.HyperSyncs[signalName] = wrappedCondition
		ClassTable.Signals[signalName]    = true
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
	--////////////////////////////////////////////////////////////
	ClassTable.SetAdorneeParent = function(parent: Instance)
		sealGuard("SetAdorneeParent")
		ClassTable._adorneeParent = parent
	end

	--////////////////////////////////////////////////////////////
	-- Include (MIXINS)
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
	-- Sub
	-- creates a namespaced subclass owned by this class
	-- stored in registry as "ParentName.SubName"
	-- prevents name collisions — two classes can both have a "Shrapnel" sub
	-- instances of this class get instance.SubName proxy table
	-- instance.SubName.New() spawns with full gen tracking:
	--   GenParent = the spawning instance
	--   Gen       = spawning instance's Gen + 1
	-- subs can have their own subs — nesting works indefinitely
	--
	-- usage:
	--   local GrenadeShrapnel = Grenade.Sub("Shrapnel")
	--   GrenadeShrapnel.NewVar("Damage", 25)
	--
	--   -- inside Grenade's Main or methods:
	--   self.Shrapnel.New() -- gen tracked, parented to this grenade instance
	--////////////////////////////////////////////////////////////
	ClassTable.Sub = function(subName: string)
		sealGuard("Sub")
		if typeof(subName) ~= "string" then
			error("Sub [" .. className .. "]: subName must be a string")
		end

		-- namespace the sub under the parent class name
		local fullSubName = className .. "." .. subName

		-- build the sub as a normal class — full API, full features
		local SubClass = buildClass(fullSubName, nil)

		-- register sub name on this class so instances know about it
		ClassTable.Subs[subName] = fullSubName

		return SubClass
	end

	--////////////////////////////////////////////////////////////
	-- GetAll
	--////////////////////////////////////////////////////////////
	ClassTable.GetAll = function(): { any }
		local list = {}
		for instance in pairs(ClassTable.ActiveInstances) do
			table.insert(list, instance)
		end
		return list
	end

	--////////////////////////////////////////////////////////////
	-- DestroyAll
	--////////////////////////////////////////////////////////////
	ClassTable.DestroyAll = function()
		local snapshot = ClassTable.GetAll()
		for _, instance in ipairs(snapshot) do
			if not instance.IsDestroyed then
				instance:Destroy()
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
	-- INTERNAL SPAWN
	-- used by Class.New(), instance.New() (generations), instance.SubName.New() (subs)
	--////////////////////////////////////////////////////////////
	local function spawnInstance(adornee: any?, genParent: any?, genNumber: number?)

		ClassTable._sealed = true

		local resolvedAdornee = adornee
		local ownsAdornee     = false

		-- ADORNEE RESOLUTION
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
				error("Object.New [" .. className .. "]: no adornee provided and no class adornee set.")
			end
		end

		local object           = {}
		object.Adornee         = resolvedAdornee
		object.IsDestroyed     = false

		-- GENERATIONS
		object.Gen         = genNumber or 1
		object.GenParent   = genParent or nil
		object.GenChildren = {}
		object.GenSiblings = genParent and genParent.GenChildren or nil

		if genParent then
			table.insert(genParent.GenChildren, object)
		end

		-- SMART STATE COPY
		local immutableKeys    = {}
		local hyperSyncTripped = {}

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

		-- SIGNALS + HYPER EVENTS
		object.Events      = {}
		object.HyperEvents = {}
		for name in pairs(ClassTable.Signals) do
			object.Events[name] = Signal.new()
			if ClassTable.HyperSyncs[name] then
				object.HyperEvents[name] = Signal.new()
			end
		end

		--////////////////////////////////////////////////////////////
		-- SUB PROXIES
		-- for each registered sub, attach a proxy table to the instance
		-- instance.SubName.New(adornee?) spawns a sub instance with:
		--   GenParent = this instance
		--   Gen       = this instance's Gen + 1
		-- this is cross-class gen tracking — different class, same lineage graph
		--////////////////////////////////////////////////////////////
		for subName, fullSubName in pairs(ClassTable.Subs) do
			local SubClass = Objects[fullSubName]
			if SubClass then
				local subSpawn = SubClass._spawnInstance
				object[subName] = {
					New = function(subAdornee: any?)
						return subSpawn(subAdornee, object, object.Gen + 1)
					end
				}
			end
		end

		--////////////////////////////////////////////////////////////
		-- SUPER PROXY
		--////////////////////////////////////////////////////////////
		local parentMethods = getmetatable(ClassTable.Methods) and getmetatable(ClassTable.Methods).__index
		local SuperProxy    = {}

		for name, method in pairs(ClassTable.Methods) do

			if ClassTable.HyperMethods[name] then
				local targetName  = ClassTable.HyperMethods[name]
				local targetClass = Objects[targetName]
				if not targetClass then
					error("NewHyperFunc [" .. className .. "]: target class '" .. targetName .. "' not found in registry")
				end
				local targetMethod = targetClass.Methods[name]
				if not targetMethod then
					error("NewHyperFunc [" .. className .. "]: method '" .. name .. "' not found on class '" .. targetName .. "'")
				end
				local boundHyper = function()
					return targetMethod(object)
				end
				SuperProxy[name] = function(s, ...)
					return method(s, boundHyper, ...)
				end

			elseif ClassTable.SuperMethods[name] then
				local parentMethod = parentMethods and parentMethods[name]
				if parentMethod then
					local boundSuper = function()
						return parentMethod(object)
					end
					SuperProxy[name] = function(s, ...)
						return method(s, boundSuper, ...)
					end
				else
					SuperProxy[name] = method
				end

			else
				local parentMethod = parentMethods and parentMethods[name]
				if parentMethod then
					local boundSuper = function()
						return parentMethod(object)
					end
					SuperProxy[name] = function(s, ...)
						local previousSuper = rawget(s, "Super")
						rawset(s, "Super", boundSuper)
						local results = table.pack(method(s, ...))
						rawset(s, "Super", previousSuper)
						return table.unpack(results, 1, results.n)
					end
				else
					SuperProxy[name] = method
				end
			end
		end

		setmetatable(SuperProxy, { __index = ClassTable.Methods })

		-- METATABLE
		setmetatable(object, {
			__index    = SuperProxy,
			__newindex = function(t, key, value)
				if immutableKeys[key] then
					error("Object [" .. className .. "]: attempt to overwrite immutable field '" .. key .. "' — write blocked")
				end

				rawset(t, key, value)

				for signalName, wrappedCondition in pairs(ClassTable.HyperSyncs) do
					local result = wrappedCondition(t)
					if result and not hyperSyncTripped[signalName] then
						hyperSyncTripped[signalName] = true
						if t.HyperEvents and t.HyperEvents[signalName] then
							t.HyperEvents[signalName]:Fire()
						end
					elseif not result then
						hyperSyncTripped[signalName] = false
					end
				end
			end
		})

		-- INSTANCE TRACKING
		ClassTable.ActiveInstances[object] = true

		-- instance.New() — same class gen spawn
		object.New = function(newAdornee: any?)
			return spawnInstance(newAdornee, object, object.Gen + 1)
		end

		-- DESTROY
		local adorneeConnection
		local function destroy()
			if object.IsDestroyed then return end
			object.IsDestroyed = true

			ClassTable.ActiveInstances[object] = nil

			if object.GenParent and object.GenParent.GenChildren then
				for i, child in ipairs(object.GenParent.GenChildren) do
					if child == object then
						table.remove(object.GenParent.GenChildren, i)
						break
					end
				end
			end

			if ClassTable._cleanup then
				local ok, err = pcall(ClassTable._cleanup, object)
				if not ok then
					warn("Object [" .. className .. "] cleanup error: " .. tostring(err))
				end
			end

			if adorneeConnection then
				adorneeConnection:Disconnect()
				adorneeConnection = nil
			end

			if ownsAdornee then
				if typeof(resolvedAdornee) == "Instance" then
					resolvedAdornee:Destroy()
				else
					resolvedAdornee = nil
				end
			end

			if object.Events then
				for _, signal in pairs(object.Events) do
					signal:DisconnectAll()
				end
			end
			if object.HyperEvents then
				for _, signal in pairs(object.HyperEvents) do
					signal:DisconnectAll()
				end
			end

			for key in pairs(object) do
				object[key] = nil
			end
			setmetatable(object, nil)
		end

		object.Destroy = destroy

		if typeof(resolvedAdornee) == "Instance" then
			adorneeConnection = resolvedAdornee.Destroying:Connect(destroy)
		end

		local ok, err = pcall(ClassTable.Main, object)
		if not ok then
			warn("Object [" .. className .. "] Main error: " .. tostring(err))
		end

		return object
	end

	-- expose spawnInstance so Sub proxies can call it cross-class
	ClassTable._spawnInstance = spawnInstance

	ClassTable.New = function(adornee: any?)
		return spawnInstance(adornee, nil, 1)
	end

	return ClassTable
end

return {
	buildClass = buildClass,
	Objects    = Objects,
}
