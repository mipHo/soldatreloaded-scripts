-- Reports each round as it ends, on the console and to a webhook: a Discord one, or any
-- that takes JSON (docs/scripting.md). Copy it into the server's
-- scripts/ and it runs as the server starts (or at script_reload).

local options = {
    url = "", -- where the report goes, "https://discord.com/api/webhooks/..."; empty, it is only printed
}

local function player_line(p)
    return ("%s %d/%d"):format(p.name, p.kills, p.deaths)
end

server.on("round_end", function(stats)
    local lines = {}
    for _, p in ipairs(stats.players) do
        if not p.spectator then lines[#lines + 1] = player_line(p) end
    end
    local report = ("Round %d on %s over (%s): alpha %d, bravo %d. %s"):format(
        stats.round, stats.map, stats.why, stats.scores.alpha, stats.scores.bravo, table.concat(lines, ", "))
    server.print(report)
    if options.url == "" then return end
    http.post(options.url, {content = report}, nil, function(r)
        if r.error then server.print("the webhook failed: " .. r.error)
        elseif r.status >= 300 then server.print("the webhook answered " .. r.status) end
    end)
end)
