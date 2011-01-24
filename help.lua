--[[ Lua "help" module
allows setting docstrings for Lua objects,
and optionally forwarding help calls
to other subsystems that have introspective
information about objects (Luabind, osgLua
included)
]]

--[[ Original Author: Ryan Pavlik <rpavlik@acm.org> <abiryan@ryand.net>
Copyright 2011 Iowa State University.
Distributed under the Boost Software License, Version 1.0.

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
]]

local mt = {}
help = setmetatable({}, mt)
local docstrings = setmetatable({}, {__mode = "k"})
local helpExtensions = {}

local function callWithIntegersFirst(t, func)
	local keys = {}
	for i, v in ipairs(t) do
		keys[i] = true
		func(i, v)
	end
	for k, v in pairs(t) do
		if not keys[k] then
			func(k, v)
		end
	end
end

local function tableExtend(dest, src)
	local applied = {}
	if type(src) ~= "table" then
		src = {src}
	end

	-- Integer keys: add them to the list
	for i, v in ipairs(src) do
		table.insert(dest, v)
		applied[i] = true
	end

	-- non-integer keys: set or append
	for k,v in pairs(src) do
		if not applied[k] then
			if type(dest[k]) == "table" then
				-- if dest is a table, either
				if type(v) == "table" then
					-- recurse
					tableExtend(dest[k], v)
				else
					-- or just append
					table.insert(dest[k], v)
				end
			else
				-- just set if it's not a table
				dest[k] = v
			end
		end
	end

end

function mt:__call(...)
	local arg = {...}
	if #arg == 0 then
		print("help(obj) - call to learn information about a particular object or value.")
		return
	end
	for i,obj in ipairs(arg) do
		local helpContent = help.lookup(obj)
		local helpHeader
		if i == 1 then
			helpHeader = "Help:\t"
		else
			print("")
			helpHeader = string.format("Help (#%d):\t", i)
		end
		if helpContent then
			print(helpHeader .. help.formatHelp(helpContent))
		else
			print(helpHeader .. "type(obj) = " .. type(obj))
			print("No further help available!")
		end
	end
end

function help.formatHelp(h)
	if type(h) == "string" then
		return h
	elseif type(h) == "table" then
		local keys = {}
		local str = ""
		for i, v in ipairs(h) do
			keys[i] = true
			str = str .. "\n" .. v
		end
		for k,v in pairs(h) do
			if not keys[k] then
				if type(v) == "table" then
					str = string.format("%s\n%s = {", str, k)
					for _, val in ipairs(v) do
						str = str .. "\n\t" .. tostring(val)
					end
					str = str .. "\n}\n"
				else
					str = str .. string.format("\n%s = %s", k, tostring(v))
				end
			end
		end
		return str
	else
		return h
	end
end

function help.lookup(obj)
	if docstrings[obj] then
		 return docstrings[obj]
	end
	for _, v in ipairs(helpExtensions) do
		local helpContent = v(obj)
		if helpContent then
			return helpContent
		end
	end
	return nil
end

function help.docstring(docs)
	local mt = {}

	-- Helper function to merge documentation
	local function mergeDocs(obj)
		local origHelp = help.lookup(obj)
		if origHelp == nil then
			-- No existing help - just set
			docstrings[obj] = docs
		else
			-- wrap bare strings if appending
			if type(origHelp) == "string" then
				origHelp = { origHelp }
			end

			-- Extend existing help
			tableExtend(origHelp, docs)
			docstrings[obj] = origHelp
		end
	end

	-- For return value: handle the .. operator for inline documentation
	function mt.__concat(_, obj)
		mergeDocs(obj)
		return obj
	end

	-- For return value: handle a call to applyTo() for after-the-fact docs
	local ret = {}
	function ret.applyTo(obj)
		mergeDocs(obj)
		return ret
	end

	-- For return value: Also just let them tack on () to apply
	function mt:__call(obj)
		mergeDocs(obj)
		return self
	end
	return setmetatable(ret, mt)
end

function help.addHelpExtension(func)
	table.insert(helpExtensions, func)
end

--[[ Luabind support ]]
local function luabindHelp(obj)
	local knownTypes = {
		["userdata"] = true,
		["table"] = true,
		["string"] = true,
		["number"] = true,
		["function"] = true,
		["thread"] = true,
		["nil"] = true
	}
	local h = class_info(obj)
	-- don't claim to know about basic types
	if knownTypes[h.name] then
		return nil
	else
		return { class = h.name,
			methods = h.methods,
			attributes = h.attributes
		}
	end
end

function help.supportLuabind()
	if not class_info then
		error("Cannot load help Luabind support: must register class_info from the C++ side", 2)
	end
	help.addHelpExtension(luabindHelp)
	help.supportLuabind = function()
		print("Luabind help support already enabled!")
	end
end

--[[ osgLua support ]]
local function osgLuaHelp(obj)
	local c = osgLua.getTypeInfo(obj)
	if c then
	 	local ret = {class = c.name}
		if #(c.constructors) > 0 then
			ret.constructors = {}
			for _,v in ipairs(c.constructors) do
				 table.insert(ret.constructors,v)
			end
		end
		if #(c.methods) > 0 then
			ret.methods = {}
			for _,v in ipairs(ret.methods) do
				 table.insert(ret.methods,v)
			end
		end
		return ret
	else
		return nil
	end
end

function help.supportOsgLua()
	if not osgLua then
		error("Cannot load help osgLua support: osgLua not found.", 2)
	end
	help.addHelpExtension(osgLuaHelp)
	help.supportOsgLua = function()
		print("osgLua help support already enabled!")
	end
end

--[[ HTML output ]]
do
	local function hasListPart(t)
		for _, v in ipairs(t) do
			return true
		end
		return false
	end
	
	local function hasDictPart(t)
		local seen = {}
		for i, v in ipairs(t) do
			seen[i] = true
		end
		for k, v in pairs(t) do
			if not seen[k] then
				return true
			end
		end
		return false
	end
	
	local function formatDefList(t)
		local ret = {"<dl>"}
		for k, v in pairs(t) do
			table.insert(ret, string.format("<dt>%s</dt><dd>%s</dd>", k, v))
		end
		table.insert(ret, "</dl>")
		return table.concat(ret, "\n")
	end
	
	local function formatUnorderedList(t)
		local ret = {"<ul>"}
		for _, v in ipairs(t) do
			table.insert(ret, string.format("<li>%s</li>", v))
		end
		table.insert(ret, "</ul>")
		return table.concat(ret, "\n")
	end
	
	local function formatParagraph(v)
		return string.format("<p>%s</p>", v)
	end
	
	function formatHeadings(level, t)
		local ret = {}
		for k, v in pairs(t) do
			table.insert(ret, string.format("<h%d>%s</h%d>", level, k, level))
			if type(v) == "string" then
				table.insert(ret, formatParagraph(v))
			elseif hasDictPart(v) then
				table.insert(ret, formatDefList(v))
			elseif hasListPart(v) then
				table.insert(ret, formatUnorderedList(v))
			else
				error("No idea how to format this!")
			end
		end
		return table.concat(ret, "\n")
	end
	
	
	
	
	
	local function formatAsHTML(h, level)
		if type(h) == "nil" then
			return "<p>No documentation available.</p>"
		elseif type(h) == "string" then
			return formatParagraph(h)
		elseif type(h) == "table" then
			local keys = {}
			local lines = {}
			local str = ""
			for i, v in ipairs(h) do
				keys[i] = true
				table.insert(lines, formatParagraph(tostring(v)))
			end
			
			-- See if we do headings or straight definition lists.
			local headings = false
			local named = {}
			for k,v in pairs(h) do
				if not keys[k] then
					named[k] = v
					if type(v) == "table" then
						headings = true
					end
				end
			end
			
			if headings then
				table.insert(lines, formatHeadings(level or 2, named))
			else
				table.insert(lines, formatDefList(named))
			end
			return table.concat(lines, "\n")
		else
			return h
		end
	end
	help.html = {}
	function help.html.recursive(name, entity, level)
		local level = level or 1
		local ret = {}
		
		print(string.format("Documenting %s at level %d", name, level))
		
		table.insert(ret, string.format("<h%d>%s</h%d>", level, name, level))
		table.insert(ret, formatAsHTML(help.lookup(entity), level + 1))
		if type(entity) == "table" then
			for k, v in pairs(entity) do
				table.insert(ret, help.html.recursive(string.format("%s.%s", name, k), v, level + 1))		
			end
		end
		return table.concat(ret, "\n")
	end
	
	function help.writeToHtml(filename, ...)
		local arg = {"<html><body>", ..., "</body></html>"}
		local file = io.open(filename, "w")
		if io.type(file) == "file" then
			file:write(table.concat(arg, "\n"))
			file:close()
		else
			error("Could not open file to write: " .. filename)
		end	
	
	end
end

--[[ Auto-enable Support for Luabind and osgLua ]]

-- Assume that a class_info method means that luabind has been
-- opened in this state and that class_info has been registered
if class_info then
	help.supportLuabind()
end

-- If there's something called osgLua, assume it is osgLua the
-- introspection-based OpenSceneGraph-wrapper
if osgLua then
	help.supportOsgLua()
end

--[[ Self-Documentation ]]

-- Docstring for the help function
-- because you know somebody will try help(help)
help.docstring{
	[==[
Display as much helpful information as possible about the argument.
There will be more information if you define docstrings for
your objects. Try help(help.docstring) for info.
]==],
	functions = {
		"docstring",
		"lookup",
		"addHelpExtension",
		"formatHelp",
		"supportLuabind",
		"supportOsgLua"
	},

}.applyTo(help)

-- Document help extensions
help.docstring[==[
Add a function to lookup help in other systems, not help.docstring.

Accepts a function that, given a lua object, either returns
a table with data like that passed to help.docstring, or nil
if it doesn't know anything special about the object.
]==].applyTo(help.addHelpExtension)

-- Document formatHelp
help.docstring[==[
Convert a value, such as that returned by help.lookup, into some
formatted string.  The default implementation, used by help(),
is optimized for on-screen display.
]==].applyTo(help.formatHelp)

-- Document lookup
help.docstring[==[
Perform a documentation lookup and return the raw documentation.
This may be a table, rather than a string - help() handles this
with a call to help.formatHelp.
]==].applyTo(help.lookup)

-- Gets a bit weird here - documentation for help.docstring
help.docstring[==[
Define documentation for an object.

You can pass just a string:
 help.docstring[[
	Help goes here free-form.
 ]]
or provide more structured help:
 help.docstring{
	[[
	Help goes here.
	]],
	args = {"this", "that", "the other"},
	methods = {"doThis", "doThat", "doOther"}
 }

No particular structure/requirement for the arguments
you pass - just make them useful.

If setting a variable, like
	a = function() code goes here end
you can call
	a = help.docstring[[your docs]] .. function() code goes here end.

If you are documenting some object a "after the fact", you can tack on a call
to .applyTo(yourObj) (or multiple calls!) after help.docstring:
	help.docstring[[your docs]].applyTo(a)
	help.docstring[[your docs]].applyTo(c).applyTo(d)
or even just parentheses for calling:
	help.docstring[[your docs]](a)


Quoting strings are somewhat flexible: see this web page for
the full details: http://www.lua.org/manual/5.1/manual.html#2.1
]==].applyTo(help.docstring)

-- Luabind support
help.docstring[==[
If you have Luabind opened on this Lua state, and you've registered class_info
(see luabind/class_info.hpp), this will enable luabind-based introspection into
classes in the help lookup.

Note that if these conditions are met when you require("help"), this function
is called automatically.
]==].applyTo(help.supportLuabind)

-- osgLua support
help.docstring[==[
If you have osgLua loaded in this Lua state, this will enable introspection into
OpenSceneGraph objects in the help lookup.

Note that if these conditions are met when you require("help"), this function
is called automatically.
]==].applyTo(help.supportOsgLua)
