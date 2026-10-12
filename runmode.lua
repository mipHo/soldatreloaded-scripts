-- Run mode: each player runs the map's course against the clock, and each player's best
-- time on each map is kept, by the machine's hardware ID. The course runs from the alpha
-- team's spawn to the bravo flag and back to the alpha flag, the run timed from the spawn
-- to the alpha flag; a run ends at a death, and the runner is killed at the finish, so the
-- next run begins at the respawn. Everyone runs on alpha, where nobody hurts anybody else.
-- !top [map], !best and !help in the chat.
--
-- For a run server: no bots, a long time_limit, a capture_limit far out of reach (9999),
-- as the course takes the bravo flag home, and only run maps in the rotation.

local options = {
    records = "runmode_records.json", -- the file the best times are kept in, from the server's folder
    radius = 30,                      -- how near a checkpoint a runner passes it, as the original's
    top = 10,                         -- the times !top shows
    kill_on_finish = true,            -- the runner killed at the finish, for the next run's respawn
}

local TICK_RATE = 60

local course = nil  -- the checkpoints, {x, y} each: the start first, the finish last; nil for no run map
local runs = {}     -- slot -> {start = tick, next = the checkpoint ahead, x, y = where it was a tick ago}
local records = {}  -- map -> hwid -> {name, ticks, date}

-- ---------------------------------------------------------------------------------
-- The records

local function load_records()
    local file = io.open(options.records, "r")
    if not file then return end
    local text = file:read("a")
    file:close()
    local ok, decoded = pcall(json.decode, text)
    if ok and type(decoded) == "table" then
        records = decoded
    else
        server.print("runmode: " .. options.records .. " couldn't be read, the records start empty")
    end
end

-- Written whole, beside the file and then over it, so a crash leaves the old one.
local function save_records()
    local temp = options.records .. ".tmp"
    local file, err = io.open(temp, "w")
    if not file then
        server.print("runmode: the records couldn't be written: " .. tostring(err))
        return
    end
    file:write(json.encode(records))
    file:close()
    os.remove(options.records)
    os.rename(temp, options.records)
end

-- The map's times, best first: {hwid, name, ticks, date} each.
local function ranking(map)
    local list = {}
    for hwid, r in pairs(records[map] or {}) do
        list[#list + 1] = {hwid = hwid, name = r.name, ticks = r.ticks, date = r.date}
    end
    table.sort(list, function(a, b)
        if a.ticks ~= b.ticks then return a.ticks < b.ticks end
        return a.date < b.date
    end)
    return list
end

local function rank_of(list, hwid)
    for i, r in ipairs(list) do
        if r.hwid == hwid then return i end
    end
end

-- ---------------------------------------------------------------------------------
-- Times

local function show_time(ticks)
    local ms = math.floor(ticks * 1000 / TICK_RATE + 0.5)
    local minutes, rest = ms // 60000, ms % 60000
    if minutes > 0 then return ("%d:%06.3f"):format(minutes, rest / 1000) end
    return ("%.3f"):format(rest / 1000)
end

local function show_diff(ticks)
    return (ticks < 0 and "-" or "+") .. show_time(math.abs(ticks))
end

local RANK_COLORS = {"FFD700", "C0C0C0", "F4A460"}

local function rank_color(rank)
    return RANK_COLORS[rank] or "6495ED"
end

-- ---------------------------------------------------------------------------------
-- The course

-- The first spawn point of `kind`, as a checkpoint.
local function spawn_of(spawns, kind)
    for _, sp in ipairs(spawns) do
        if sp.kind == kind then return {x = sp.x, y = sp.y} end
    end
end

-- The map's course: the alpha spawn, the bravo flag, the alpha flag. Nil for a map
-- without the three, which isn't a run map.
local function course_of_map()
    local spawns = server.spawns()
    local start, turn, finish = spawn_of(spawns, "alpha"), spawn_of(spawns, "bravo_flag"), spawn_of(spawns, "alpha_flag")
    if not (start and turn and finish) then return nil end
    return {start, turn, finish}
end

-- Whether the path from (ax, ay) to (bx, by) comes within the radius of `cp`: a runner
-- fast enough to cross a checkpoint between two ticks passes it still.
local function passes(cp, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local length2 = dx * dx + dy * dy
    local t = 0
    if length2 > 0 then
        t = math.max(0, math.min(1, ((cp.x - ax) * dx + (cp.y - ay) * dy) / length2))
    end
    local px, py = ax + t * dx - cp.x, ay + t * dy - cp.y
    return px * px + py * py <= options.radius * options.radius
end

local function set_course()
    runs = {}
    course = course_of_map()
    if not course then
        server.print(("runmode: %s has no alpha spawn, bravo flag or alpha flag: no course"):format(server.map()))
    end
end

-- ---------------------------------------------------------------------------------
-- The runs

local function finish(slot, p, ticks)
    local map = server.map()
    if options.kill_on_finish then server.kill(slot) end
    if not p.hwid then
        server.say(("%s %s"):format(p.name, show_time(ticks)), rank_color(0))
        server.say_to(slot, "Your game sent no hardware ID: the time isn't kept")
        return
    end

    local before = ranking(map)
    local record = before[1]
    local mine = records[map] and records[map][p.hwid]
    if mine and ticks >= mine.ticks then
        server.say_to(slot, ("%s, %s slower than your best"):format(show_time(ticks), show_diff(ticks - mine.ticks)))
        return
    end

    records[map] = records[map] or {}
    records[map][p.hwid] = {name = p.name, ticks = ticks, date = os.time()}
    save_records()

    local rank = rank_of(ranking(map), p.hwid)
    local against = {}
    if mine then against[#against + 1] = "best " .. show_diff(ticks - mine.ticks) end
    if record and record.hwid ~= p.hwid then
        against[#against + 1] = "record " .. show_diff(ticks - record.ticks)
    end
    local line = ("[%d] %s %s"):format(rank, p.name, show_time(ticks))
    if rank == 1 then line = line .. (record and ", a new record" or ", the first on " .. map) end
    if #against > 0 then line = line .. " (" .. table.concat(against, ", ") .. ")" end
    server.say(line, rank_color(rank))
end

server.on("spawn", function(slot)
    local p = server.player(slot)
    if not course or not p or p.team ~= "alpha" then
        runs[slot] = nil
        return
    end
    -- the start is where the runner spawns: the alpha spawn, checkpoint 1
    runs[slot] = {start = server.tick(), next = 2, x = p.x, y = p.y}
end)

server.on("tick", function(tick)
    if not course then return end
    for slot, run in pairs(runs) do
        local p = server.player(slot)
        if not p or not p.alive then
            runs[slot] = nil
        else
            local cp = course[run.next]
            if passes(cp, run.x, run.y, p.x, p.y) then
                local ticks = tick - run.start
                if run.next == #course then
                    runs[slot] = nil
                    finish(slot, p, ticks)
                else
                    server.say_to(slot, ("Checkpoint %d/%d  %s"):format(run.next, #course, show_time(ticks)), "6495ED")
                    run.next = run.next + 1
                end
            end
            run.x, run.y = p.x, p.y
        end
    end
end)

server.on("kill", function(killer, victim) runs[victim] = nil end)
server.on("leave", function(slot) runs[slot] = nil end)
server.on("round_end", function() runs = {} end)
server.on("round_start", function() set_course() end)

-- Everyone on alpha: the team menu's bravo is taken back within the second.
server.on("join", function(slot, name, player)
    if player.bot then return end
    server.say_to(slot, "Run mode: from your spawn to the bravo flag and home to yours, against the clock. !help for more.", "6495ED")
end)

server.on("second", function()
    for _, p in ipairs(server.players()) do
        if not p.bot and p.team == "bravo" then server.set_team(p.slot, "alpha") end
    end
end)

-- ---------------------------------------------------------------------------------
-- The commands

local function say_top(slot, map)
    local list = ranking(map)
    if #list == 0 then
        server.say_to(slot, "No times on " .. map)
        return
    end
    server.say_to(slot, ("%s, the best %d:"):format(map, math.min(#list, options.top)), "6495ED")
    for i = 1, math.min(#list, options.top) do
        local r = list[i]
        server.say_to(slot, ("[%d] %s %s, %s"):format(i, r.name, show_time(r.ticks), os.date("%Y-%m-%d", r.date)), rank_color(i))
    end
end

server.on("chat", function(slot, text)
    local word, rest = text:match("^!(%S+)%s*(.-)%s*$")
    if not word then return end
    if word == "top" then
        say_top(slot, rest ~= "" and rest or server.map())
    elseif word == "best" then
        local p = server.player(slot)
        local map = server.map()
        local mine = p.hwid and records[map] and records[map][p.hwid]
        if mine then
            local rank = rank_of(ranking(map), p.hwid)
            server.say_to(slot, ("Your best on %s: [%d] %s"):format(map, rank, show_time(mine.ticks)), rank_color(rank))
        else
            server.say_to(slot, "No time of yours on " .. map)
        end
    elseif word == "help" then
        server.say_to(slot, "Run from your spawn to the bravo flag and home to your own flag; the clock starts as you spawn.", "6495ED")
        server.say_to(slot, "A death ends the run; the next starts at the respawn. Your best is kept by your machine.", "6495ED")
        server.say_to(slot, "!top [map] - the best times, !best - your own on this map", "6495ED")
    end
end)

load_records()
set_course()
