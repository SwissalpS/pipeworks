-- flowable node registry: add entries and install ABMs if new flow logic is enabled
-- written 2017 by thetaepsilon



-- use for hooking up ABMs as nodes are registered
local abmregister = pipeworks.flowlogic.abmregister

-- registration functions
pipeworks.flowables.register = {}
local register = pipeworks.flowables.register

-- some sanity checking for passed args, as this could potentially be made an external API eventually
local checkexists = function(nodename)
	if type(nodename) ~= "string" then error("pipeworks.flowables nodename must be a string!") end
	return pipeworks.flowables.list.all[nodename]
end

local insertbase = function(nodename)
	if checkexists(nodename) then error("pipeworks.flowables duplicate registration!") end
	pipeworks.flowables.list.all[nodename] = true
	-- table.insert(pipeworks.flowables.list.nodenames, nodename)
end

local regwarning = function(kind, nodename)
	local tail = ""
	if not pipeworks.toggles.pressure_logic then tail = " but pressure logic not enabled" end
	--pipeworks.logger(kind.." flow logic registry requested for "..nodename..tail)
end

-- Register a node as a simple flowable.
-- Simple flowable nodes have no considerations for direction of flow;
-- A cluster of adjacent simple flowables will happily average out in any direction.
register.simple = function(nodename)
	insertbase(nodename)
	pipeworks.flowables.list.simple[nodename] = true
	table.insert(pipeworks.flowables.list.simple_nodenames, nodename)
	if pipeworks.toggles.pressure_logic then
		abmregister.flowlogic(nodename)
	end
	regwarning("simple", nodename)
end

local checkbase = function(nodename)
	if not checkexists(nodename) then error("pipeworks.flowables node doesn't exist as a flowable!") end
end

local duplicateerr = function(kind, nodename) error(kind.." duplicate registration for "..nodename) end



-- Registers a node as a fluid intake.
-- intakefn is used to determine the water that can be taken in a node-specific way.
-- Expects node to be registered as a flowable (is present in flowables.list.all),
-- so that water can move out of it.
-- maxpressure is the maximum pipeline pressure that this node can drive;
-- if the input's node exceeds this the callback is not run.
-- possible WISHME here: technic-driven high-pressure pumps
register.intake = function(nodename, maxpressure, intakefn)
	-- check for duplicate registration of this node
	local list = pipeworks.flowables.inputs.list
	checkbase(nodename)
	if list[nodename] then duplicateerr("pipeworks.flowables.inputs", nodename) end
	list[nodename] = { maxpressure=maxpressure, intakefn=intakefn }
	regwarning("intake", nodename)
end



-- Register a node as a simple intake:
-- tries to absorb water source nodes from it's surroundings.
-- may exceed limit slightly due to needing to absorb whole nodes.
register.intake_simple = function(nodename, maxpressure)
	register.intake(nodename, maxpressure, pipeworks.flowlogic.check_for_liquids_v2)
end



-- Register a node as an output.
-- Expects node to already be a flowable.
-- upper and lower thresholds have different meanings depending on whether finite liquid mode is in effect.
-- if not (the default unless auto-detected),
-- nodes above their upper threshold have their outputfn invoked (and pressure deducted),
-- nodes between upper and lower are left idle,
-- and nodes below lower have their cleanup fn invoked (to say remove water sources).
-- the upper and lower difference acts as a hysteresis to try and avoid "gaps" in the flow.
-- if finite mode is on, upper is ignored and lower is used to determine whether to run outputfn;
-- cleanupfn is ignored in this mode as finite mode assumes something causes water to move itself.
register.output = function(nodename, upper, lower, outputfn)
	if pipeworks.flowables.outputs.list[nodename] then
		error("pipeworks.flowables.outputs duplicate registration!")
	end
	checkbase(nodename)
	pipeworks.flowables.outputs.list[nodename] = { upper=upper, lower=lower, outputfn=outputfn }
	-- output ABM now part of main flow logic ABM to preserve ordering.
	-- note that because outputs have to be a flowable first
	-- (and the installation of the flow logic ABM is conditional),
	-- registered output nodes for new_flow_logic is also still conditional on the enable flag.
	regwarning("output node", nodename)
end

-- register a simple output:
-- drains pressure by attempting to place water in nearby nodes,
-- which can be set by passing a list of offset vectors.
-- will attempt to drain as many whole nodes as there are positions in the offset list.
-- for meanings of upper and lower, see register.output() above.
-- non-finite mode:
--	above upper pressure: places water sources as appropriate, keeps draining pressure.
--	below lower presssure: removes it's neighbour water sources.
-- finite mode:
--	same as for above pressure in non-finite mode,
--	but only drains pressure when water source nodes are actually placed.
register.output_simple = function(nodename, upper, lower, neighbours)
	local outputfn = pipeworks.flowlogic.helpers.make_neighbour_output_fixed(neighbours)
	register.output(nodename, upper, lower, outputfn)
end
