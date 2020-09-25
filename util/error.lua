local id = require "util.id";

-- Library configuration (see configure())
local auto_inject_traceback = false;
local display_tracebacks = false;


local error_mt = { __name = "error" };

function error_mt:__tostring()
	if display_tracebacks and self.context.traceback then
		return ("error<%s:%s:%s:%s>"):format(self.type, self.condition, self.text or "", self.context.traceback);
	end
	return ("error<%s:%s:%s>"):format(self.type, self.condition, self.text or "");
end

local function is_err(e)
	return getmetatable(e) == error_mt;
end

local function configure(opt)
	if opt.display_tracebacks ~= nil then
		display_tracebacks = opt.display_tracebacks;
	end
	if opt.auto_inject_traceback ~= nil then
		auto_inject_traceback = opt.auto_inject_traceback;
	end
end

-- Do we want any more well-known fields?
-- Or could we just copy all fields from `e`?
-- Sometimes you want variable details in the `text`, how to handle that?
-- Translations?
-- Should the `type` be restricted to the stanza error types or free-form?
-- What to set `type` to for stream errors or SASL errors? Those don't have a 'type' attr.

local function new(e, context, registry, source)
	local template = (registry and registry[e]) or e or {};
	context = context or {};

	if auto_inject_traceback then
		context.traceback = debug.traceback("error stack", 2);
	end

	local error_instance = setmetatable({
		instance_id = id.short();

		type = template.type or "cancel";
		condition = template.condition or "undefined-condition";
		text = template.text;
		code = template.code;

		context = context;
		source = source;
	}, error_mt);

	return error_instance;
end

local function init(source, registry)
	return {
		new = function (e, context)
			return new(e, context, registry, source);
		end;
	};
end

local function coerce(ok, err, ...)
	if ok or is_err(err) then
		return ok, err, ...;
	end

	local new_err = setmetatable({
		native = err;

		type = "cancel";
		condition = "undefined-condition";
	}, error_mt);
	return ok, new_err, ...;
end

local function from_stanza(stanza, context)
	local error_type, condition, text = stanza:get_error();
	return setmetatable({
		type = error_type or "cancel";
		condition = condition or "undefined-condition";
		text = text;

		context = context or { stanza = stanza };
	}, error_mt);
end

return {
	new = new;
	init = init;
	coerce = coerce;
	is_err = is_err;
	from_stanza = from_stanza;
	configure = configure;
}
