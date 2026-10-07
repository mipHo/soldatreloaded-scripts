-- Greets whoever joins, and says each map as it begins (docs/scripting.md). Copy it into
-- the server's scripts/ and it runs as the server starts (or at script_reload).

local options = {
    welcome = "Welcome, %s.", -- what a player is told as they join, %s their name
}

server.on("join", function(slot, name)
    server.say_to(slot, options.welcome:format(name), "7FD6FF")
end)

server.on("leave", function(slot, name)
    server.print(name .. " left slot " .. slot)
end)

server.on("round_start", function(map)
    server.say("Now playing " .. map)
end)
