-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local modulemanager = require "core.modulemanager";
local log = require "util.logger".init("usermanager");
local type = type;
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local jid_prep = require "util.jid".prep;
local config = require "core.configmanager";
local sasl_new = require "util.sasl".new;
local storagemanager = require "core.storagemanager";
local set = require "util.set";

local prosody = _G.prosody;
local hosts = prosody.hosts;

local setmetatable = setmetatable;

local default_provider = "internal_plain";

local _ENV = nil;
-- luacheck: std none

local function new_null_provider()
	local function dummy() return nil, "method not implemented"; end;
	local function dummy_get_sasl_handler() return sasl_new(nil, {}); end
	return setmetatable({name = "null", get_sasl_handler = dummy_get_sasl_handler}, {
		__index = function(self, method) return dummy; end --luacheck: ignore 212
	});
end

local global_admins_config = config.get("*", "admins");
if type(global_admins_config) ~= "table" then
	global_admins_config = nil; -- TODO: factor out moduleapi magic config handling and use it here
end
local global_admins = set.new(global_admins_config) / jid_prep;

local admin_role = { ["prosody:admin"] = true };
local global_authz_provider = {
	get_user_roles = function (user) end; --luacheck: ignore 212/user
	get_jid_roles = function (jid)
		if global_admins:contains(jid) then
			return admin_role;
		end
	end;
};

local provider_mt = { __index = new_null_provider() };

local function initialize_host(host)
	local host_session = hosts[host];

	local authz_provider_name = config.get(host, "authorization") or "internal";

	local authz_mod = modulemanager.load(host, "authz_"..authz_provider_name);
	host_session.authz = authz_mod or global_authz_provider;

	if host_session.type ~= "local" then return; end

	host_session.events.add_handler("item-added/auth-provider", function (event)
		local provider = event.item;
		local auth_provider = config.get(host, "authentication") or default_provider;
		if config.get(host, "anonymous_login") then
			log("error", "Deprecated config option 'anonymous_login'. Use authentication = 'anonymous' instead.");
			auth_provider = "anonymous";
		end -- COMPAT 0.7
		if provider.name == auth_provider then
			host_session.users = setmetatable(provider, provider_mt);
		end
		if host_session.users ~= nil and host_session.users.name ~= nil then
			log("debug", "Host '%s' now set to use user provider '%s'", host, host_session.users.name);
		end
	end);
	host_session.events.add_handler("item-removed/auth-provider", function (event)
		local provider = event.item;
		if host_session.users == provider then
			host_session.users = new_null_provider();
		end
	end);
	host_session.users = new_null_provider(); -- Start with the default usermanager provider
	local auth_provider = config.get(host, "authentication") or default_provider;
	if config.get(host, "anonymous_login") then auth_provider = "anonymous"; end -- COMPAT 0.7
	if auth_provider ~= "null" then
		modulemanager.load(host, "auth_"..auth_provider);
	end

end;
prosody.events.add_handler("host-activated", initialize_host, 100);

local function test_password(username, host, password)
	return hosts[host].users.test_password(username, password);
end

local function get_password(username, host)
	return hosts[host].users.get_password(username);
end

local function set_password(username, password, host, resource)
	local ok, err = hosts[host].users.set_password(username, password);
	if ok then
		prosody.events.fire_event("user-password-changed", { username = username, host = host, resource = resource });
	end
	return ok, err;
end

local function user_exists(username, host)
	if hosts[host].sessions[username] then return true; end
	return hosts[host].users.user_exists(username);
end

local function create_user(username, password, host)
	return hosts[host].users.create_user(username, password);
end

local function delete_user(username, host)
	local ok, err = hosts[host].users.delete_user(username);
	if not ok then return nil, err; end
	prosody.events.fire_event("user-deleted", { username = username, host = host });
	return storagemanager.purge(username, host);
end

local function users(host)
	return hosts[host].users.users();
end

local function get_sasl_handler(host, session)
	return hosts[host].users.get_sasl_handler(session);
end

local function get_provider(host)
	return hosts[host].users;
end

local function get_roles(jid, host)
	if host and not hosts[host] then return false; end
	if type(jid) ~= "string" then return false; end

	jid = jid_bare(jid);
	host = host or "*";

	local actor_user, actor_host = jid_split(jid);
	local roles;

	local authz_provider = (host ~= "*" and hosts[host].authz) or global_authz_provider;

	if actor_user and actor_host == host then -- Local user
		roles = authz_provider.get_user_roles(actor_user);
	else -- Remote user/JID
		roles = authz_provider.get_jid_roles(jid);
	end

	return roles;
end

local function is_admin(jid, host)
	local roles = get_roles(jid, host);
	return roles and roles["prosody:admin"];
end

return {
	new_null_provider = new_null_provider;
	initialize_host = initialize_host;
	test_password = test_password;
	get_password = get_password;
	set_password = set_password;
	user_exists = user_exists;
	create_user = create_user;
	delete_user = delete_user;
	users = users;
	get_sasl_handler = get_sasl_handler;
	get_provider = get_provider;
	get_roles = get_roles;
	is_admin = is_admin;
};
