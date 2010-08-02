-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local log = require "util.logger".init("auth_cyrus");

local cyrus_service_realm = module:get_option("cyrus_service_realm");
local cyrus_service_name = module:get_option("cyrus_service_name");
local cyrus_application_name = module:get_option("cyrus_application_name");

prosody.unlock_globals(); --FIXME: Figure out why this is needed and
						  -- why cyrussasl isn't caught by the sandbox
local cyrus_new = require "util.sasl_cyrus".new;
prosody.lock_globals();
local new_sasl = function(realm)
	return cyrus_new(
		cyrus_service_realm or realm,
		cyrus_service_name or "xmpp",
		cyrus_application_name or "prosody"
	);
end

function new_default_provider(host)
	local provider = { name = "cyrus" };
	log("debug", "initializing default authentication provider for host '%s'", host);

	function provider.test_password(username, password)
		return nil, "Legacy auth not supported with Cyrus SASL.";
	end

	function provider.get_password(username)
		return nil, "Passwords unavailable for Cyrus SASL.";
	end
	
	function provider.set_password(username, password)
		return nil, "Passwords unavailable for Cyrus SASL.";
	end

	function provider.user_exists(username)
		return true;
	end

	function provider.create_user(username, password)
		return nil, "Account creation/modification not available with Cyrus SASL.";
	end

	function provider.get_sasl_handler()
		local realm = module:get_option("sasl_realm") or module.host;
		return new_sasl(realm);
	end

	return provider;
end

module:add_item("auth-provider", new_default_provider(module.host));

