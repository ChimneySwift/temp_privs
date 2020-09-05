local function load_data(filename)
    local file = io.open(filename, "r")
    if file then
        local table = minetest.deserialize(file:read("*all"))
        file:close()
        if type(table) == "table" then
            return table
        else
            return {}
        end
    end
end

local function save_data(filename, data)
    local file = io.open(filename, "w")
    if file then
        file:write(minetest.serialize(data))
        file:close()
    end
end

local db_filename = minetest.get_worldpath().."/temp_privs_db.txt"
local db = load_data(db_filename) or {} -- loads file if it exists, or makes empty table

local unit_to_secs = {
    s = 1, m = 60, h = 3600,
    D = 86400, W = 604800, M = 2592000, Y = 31104000,
}

local function parse_time(t) --> secs
    if not t then return false end
    local secs = 0
    for num, unit in t:gmatch("(%d+)([smhDWMY]?)") do
        secs = secs + (tonumber(num) * (unit_to_secs[unit] or 1))
    end
    if secs == 0 then return false end
    return secs
end

local function revoke_privs(player, privstring, revokeall)
    if revokeall then
        minetest.set_player_privs(player, {})
    end
    local revokeprivs = minetest.string_to_privs(privstring)
    local privs = minetest.get_player_privs(player)
    for priv, _ in pairs(revokeprivs) do
        privs[priv] = nil
    end
    minetest.set_player_privs(player, privs)
end

local function grant_privs(player, privstring)
    local grantprivs = minetest.string_to_privs(privstring)
    local privs = minetest.get_player_privs(player)
    for priv, _ in pairs(grantprivs) do
        privs[priv] = true
    end
    minetest.set_player_privs(player, privs)
end

local function handle_privs_command(caller, name, privstring, grantorrevoke, timestr)
    if not parse_time(timestr) and timestr then
        privstring = timestr .. privstring
        timestr = nil
    end
    local caller_privs = minetest.get_player_privs(caller)
    if not (caller_privs.privs or caller_privs.basic_privs) then
        return false, "Your privileges are insufficient."
    end

    if not minetest.player_exists(name) then
        return false, "Player " .. name .. " does not exist."
    end

    local privs = minetest.string_to_privs(privstring)
    if privstring == "all" then
        privs = minetest.registered_privileges
    end

    local basic_privs = minetest.string_to_privs(minetest.settings:get("basic_privs") or "interact,shout")
    if grantorrevoke == "grant" then
        local privs_unknown = ""
        for priv, _ in pairs(privs) do
            if not basic_privs[priv] and not caller_privs.privs then
                return false, "Your privileges are insufficient."
            end
            if not minetest.registered_privileges[priv] then
                privs_unknown = privs_unknown .. "Unknown privilege: " .. priv .. "\n"
            end
        end
        if privs_unknown ~= "" then
            return false, privs_unknown
        end
        grant_privs(name, minetest.privs_to_string(privs))
    elseif grantorrevoke == "revoke" then
        local currentprivs = minetest.get_player_privs(name)
        for priv, _ in pairs(privs) do
            if not basic_privs[priv] and not caller_privs.privs then
                return false, "Your privileges are insufficient."
            end
            for p, i in pairs(privs) do
                if not currentprivs[p] then
                    privs[p] = nil
                end
            end
        end
        if privstring == "all" then
            revoke_privs(name, minetest.privs_to_string(privs), true)
        else
            revoke_privs(name, minetest.privs_to_string(privs))
        end
    end

    if timestr then
        local time_from_now = parse_time(timestr)
        local time = os.time() + time_from_now
        db[name] = {}
        table.insert(db[name], {
            time = time,
            privs = minetest.privs_to_string(privs),
            revoke_or_grant = grantorrevoke,
        })
        save_data(db_filename, db)
        timestr = " for: "..timestr
    else
        timestr = " for: indefinitely"
    end
    if grantorrevoke == "grant" then
        minetest.log("action", caller..' granted ('..minetest.privs_to_string(privs, ', ')..') privileges to '..name..timestr)
        if name ~= caller then
            minetest.chat_send_player(name, caller.." granted you privileges: "..minetest.privs_to_string(privs, ' ')..timestr)
        end
        return true, "Privileges of "..name..": "..minetest.privs_to_string(minetest.get_player_privs(name), ' ')..timestr
    elseif grantorrevoke == "revoke" then
        minetest.log("action", name..' revoked ('..minetest.privs_to_string(privs, ', ')..') privileges from '..name..timestr)
        if name ~= caller then
            minetest.chat_send_player(name, caller.." revoked privileges from you: "..minetest.privs_to_string(privs, ' ')..timestr)
        end
        return true, "Privileges of "..name .. ": "..minetest.privs_to_string(minetest.get_player_privs(name), ' ')..timestr
    end
end

minetest.override_chatcommand("grant", {
    params = "<name> [time] <privilege>|all",
    func = function(name, param)
        local grantname, timestr, grantprivstr = string.match(param, "([^ ]+) ([^ ]+) (.+)")
        if not grantprivstr then
            grantname, grantprivstr = string.match(param, "([^ ]+) (.+)")
        end
        if not grantname or not grantprivstr then
            return false, "Invalid parameters (see /help grant)"
        end
        return handle_privs_command(name, grantname, grantprivstr, "grant", timestr)
    end,
})

minetest.override_chatcommand("grantme", {
    params = "[time] <privilege>|all",
    func = function(name, param)
    local timestr, grantprivstr = string.match(param, "([^ ]+) (.+)")
        if not revokeprivstr then
            grantprivstr = param
        end
        if not grantprivstr then
            return false, "Invalid parameters (see /help grantme)"
        end
        return handle_privs_command(name, name, grantprivstr, "grant", timestr)
    end,
})

minetest.override_chatcommand("revoke", {
    params = "<name> [time] <privilege>|all",
    func = function(name, param)
        local revokename, timestr, revokeprivstr = string.match(param, "([^ ]+) ([^ ]+) (.+)")
        if not revokeprivstr then
            revokename, revokeprivstr = string.match(param, "([^ ]+) (.+)")
        end
        if not revokename or not revokeprivstr then
            return false, "Invalid parameters (see /help revoke)"
        end
        return handle_privs_command(name, revokename, revokeprivstr, "revoke", timestr)
    end,
})

local function update_privs()
    local now = os.time()
    for n in pairs(db) do
        for i, l in ipairs(db[n]) do
            if l.time <= now then
                if l.revoke_or_grant == "grant" then
                    revoke_privs(n, l.privs)
                    if minetest.get_player_by_name(n) then
                        minetest.log("action", 'Revoked ('..l.privs..') privileges from '..n.." (expired)")
                        minetest.chat_send_player(n, "Revoked privileges from you: "..l.privs.." (expired)")
                    end
                elseif l.revoke_or_grant == "revoke" then
                    grant_privs(n, l.privs)
                    if minetest.get_player_by_name(n) then
                        minetest.log("action", 'Granted ('..l.privs..') privileges to '..n.." (expired)")
                        minetest.chat_send_player(n, "Granted you privileges: "..l.privs.." (expired)")
                    end
                end
                table.remove(db[n], i)
                save_data(db_filename, db)
            end
        end
        if next(db[n]) == nil then
            db[n] = nil
            save_data(db_filename, db)
        end
    end
    minetest.after(1, update_privs)
end

minetest.after(1, update_privs)
