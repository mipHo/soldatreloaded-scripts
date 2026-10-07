-- Lets the names given hold the game and skip the map from the chat: /hold, /go and
-- /skip (docs/scripting.md). A name is anyone's to take, so for real admins see the
-- config's `admins` and `admin_password` (the server's own /pause, /unpause and /nextmap
-- are theirs); this is for a game among friends. Copy it into the server's
-- scripts/ and it runs as the server starts (or at script_reload).

local options = {
    names = {"Major"}, -- who may
}

local allowed = {}
for _, name in ipairs(options.names) do allowed[name] = true end

server.on("command", function(slot, text)
    local p = server.player(slot)
    if not (p and allowed[p.name]) then return end
    if text == "hold" then
        server.pause()
        return true
    elseif text == "go" then
        server.unpause()
        return true
    elseif text == "skip" then
        server.next_map()
        return true
    end
end)
