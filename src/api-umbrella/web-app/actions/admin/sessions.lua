local Admin = require "api-umbrella.web-app.models.admin"
local ApiUser = require "api-umbrella.web-app.models.api_user"
local array_includes = require "api-umbrella.utils.array_includes"
local build_url = require "api-umbrella.utils.build_url"
local csrf = require "api-umbrella.web-app.utils.csrf"
local flash = require "api-umbrella.web-app.utils.flash"
local is_empty = require("pl.types").is_empty
local json_null_default = require "api-umbrella.web-app.utils.json_null_default"
local json_response = require "api-umbrella.web-app.utils.json_response"
local login_admin = require "api-umbrella.web-app.utils.login_admin"
local require_admin = require "api-umbrella.web-app.utils.require_admin"
local respond_to = require "api-umbrella.web-app.utils.respond_to"
local t = require("api-umbrella.web-app.utils.gettext").gettext
local username_label = require "api-umbrella.web-app.utils.username_label"

local _M = {}

local function define_view_helpers(self)
  self.external_providers = {}
  if config["app_env"] == "development" then
    table.insert(self.external_providers, {
      strategy = "developer",
      name = t("dummy login (development only)"),
    })
  end
  for _, strategy in ipairs(config["web"]["admin"]["auth_strategies"]["enabled"]) do
    local provider = {}

    provider["strategy"] = strategy
    if strategy == "cas" then
      provider["name"] = t("CAS")
    elseif strategy == "facebook" then
      provider["name"] = t("Facebook")
      provider["not_configured"] = is_empty(config["web"]["admin"]["auth_strategies"]["facebook"]["client_id"])
    elseif strategy == "github" then
      provider["name"] = t("GitHub")
      provider["not_configured"] = is_empty(config["web"]["admin"]["auth_strategies"]["github"]["client_id"])
    elseif strategy == "gitlab" then
      provider["name"] = t("GitLab")
      provider["not_configured"] = is_empty(config["web"]["admin"]["auth_strategies"]["gitlab"]["client_id"])
    elseif strategy == "google" then
      provider["strategy"] = "google_oauth2"
      provider["name"] = t("Google")
      provider["not_configured"] = is_empty(config["web"]["admin"]["auth_strategies"]["google"]["client_id"])
    elseif strategy == "ldap" then
      if config["web"]["admin"]["auth_strategies"]["_only_ldap_enabled?"] then
        provider = nil
      else
        provider["name"] = t("LDAP")
      end
    elseif strategy == "max.gov" then
      provider["name"] = t("MAX.gov")
    elseif strategy == "local" then
      provider = nil
    else
      error("Unknown authentication strategy enabled in config: " .. (strategy or ""))
    end

    if provider then
      table.insert(self.external_providers, provider)
    end
  end

  self.username_label = username_label()

  self.display_no_admin_alert = false
  if not config["web"]["admin"]["auth_strategies"]["_enabled"]["local"] and Admin:count() == 0 then
    self.display_no_admin_alert = true
  end

  self.display_login_form_local = false
  if config["web"]["admin"]["auth_strategies"]["_enabled"]["local"] then
    self.display_login_form_local = true
  end

  self.display_login_form_ldap = false
  if config["web"]["admin"]["auth_strategies"]["_only_ldap_enabled?"] then
    self.display_login_form_ldap = true
  end

  self.display_login_form = false
  if self.display_login_form_local or self.display_login_form_ldap then
    self.display_login_form = true
  end

  self.display_external_provider_buttons = false
  if #self.external_providers > 0 then
    self.display_external_provider_buttons = true
  end

  self.display_no_auth_alert = false
  if not self.display_external_provider_buttons and not self.display_login_form then
    self.display_no_auth_alert = true
  end
end

function _M.new(self)
  self.admin_params = {}
  define_view_helpers(self)
  return { render = "admin.sessions.new" }
end

function _M.create(self)
  local admin
  local admin_params = _M.admin_params(self)
  if admin_params then
    local username = admin_params["username"]
    local password = admin_params["password"]
    if not is_empty(username) and not is_empty(password) then
      local match = Admin:find_for_login(username)
      if match and match:is_valid_password(password) then
        admin = match
      end
    end
  end

  if admin then
    return { redirect_to = login_admin(self, admin, "local") }
  else
    self.admin_params = admin_params
    define_view_helpers(self)
    if config["web"]["admin"]["username_is_email"] then
      flash.now(self, "warning", t("Invalid email or password."))
    else
      flash.now(self, "warning", t("Invalid username or password."))
    end
    return { render = "admin.sessions.new" }
  end
end

function _M.destroy(self)
  self:init_session_db()
  self.session_db:open()
  self.session_db:destroy()

  flash.session(self, "info", t("Signed out successfully."))
  return { status = 204, layout = false }
end

function _M.auth(self)
  local response = {
    authenticated = false,
  }

  local current_admin = self.current_admin
  if current_admin then
    local admin = current_admin:as_json()
    local api_user = ApiUser:select("WHERE email = ? ORDER BY created_at LIMIT 1", "web.admin.ajax@internal.apiumbrella")[1]

    local local_auth_enabled = false
    if config["web"]["admin"]["auth_strategies"]["_enabled"]["local"] then
      local_auth_enabled = true
    end

    response["authenticated"] = true
    response["analytics_timezone"] = json_null_default(config["analytics"]["timezone"])
    response["enable_beta_analytics"] = (config["analytics"]["adapter"] == "kylin" or (config["analytics"]["outputs"] and array_includes(config["analytics"]["outputs"], "kylin")))
    response["username_is_email"] = json_null_default(config["web"]["admin"]["username_is_email"])
    response["local_auth_enabled"] = json_null_default(local_auth_enabled)
    response["password_length_min"] = json_null_default(config["web"]["admin"]["password_length_min"])
    response["api_umbrella_version"] = json_null_default(API_UMBRELLA_VERSION)
    response["admin"] = {}
    response["admin"]["email"] = json_null_default(admin["email"])
    response["admin"]["id"] = json_null_default(admin["id"])
    response["admin"]["superuser"] = json_null_default(admin["superuser"])
    response["admin"]["username"] = json_null_default(admin["username"])
    response["admin"]["permissions"] = {}
    response["admin"]["permissions"]["analytics"] = json_null_default(current_admin:allows_permission("analytics"))
    response["admin"]["permissions"]["user_view"] = json_null_default(current_admin:allows_permission("user_view"))
    response["admin"]["permissions"]["user_manage"] = json_null_default(current_admin:allows_permission("user_manage"))
    response["admin"]["permissions"]["admin_manage"] = json_null_default(current_admin:allows_permission("admin_manage"))
    response["admin"]["permissions"]["backend_manage"] = json_null_default(current_admin:allows_permission("backend_manage"))
    response["admin"]["permissions"]["backend_publish"] = json_null_default(current_admin:allows_permission("backend_publish"))
    response["api_key"] = json_null_default(api_user:api_key_decrypted())
    response["admin_auth_token"] = json_null_default(current_admin:authentication_token_decrypted())
  end

  return json_response(self, response)
end

function _M.admin_params(self)
  local params = {}
  if self.params and self.params["admin"] then
    local input = self.params["admin"]
    params = {
      username = input["username"],
      password = input["password"],
    }
  end

  return params
end

function _M.first_time_setup_check(self)
  if Admin.needs_first_account() then
    return self:write({ redirect_to = build_url("/admins/signup") })
  end
end

return function(app)
  local create = nil
  if config["web"]["admin"]["auth_strategies"]["_enabled"]["local"] then
    create = csrf.validate_token_filter(_M.create)
  end

  app:match("/admin/login(.:format)", respond_to({
    before = function(self)
      _M.first_time_setup_check(self)
      if self.current_admin then
        return self:write({ redirect_to = build_url("/admin/") })
      end
    end,
    GET = _M.new,
    POST = create,
  }))
  app:delete("/admin/logout(.:format)", csrf.validate_token_or_admin_filter(require_admin(_M.destroy)))
  app:get("/admin/auth(.:format)", _M.auth)
end