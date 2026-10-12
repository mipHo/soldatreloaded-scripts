-- Run mode: each player runs the map's course against the clock, and each player's best
-- time on each map is kept, by the machine's hardware ID. A course is checkpoints from a
-- start to a finish: the map's own, as its admins made it, or else from the alpha team's
-- spawn to the bravo flag and back to the alpha flag. Every runner is placed at the start,
-- and timed from there to the finish; a run ends at a death, and the runner is killed at
-- the finish, so the next run begins at the respawn. Everyone runs on alpha, where nobody
-- hurts anybody else. The checkpoints are shown in the world, each runner's next one in
-- its own colour, for it alone, and each runner's time on its screen as it runs.
--
-- In the chat: !fail ends the run and starts another (bind it to a taunt), !top [map],
-- !best and !help. An admin makes the map's course with /cpadd (a checkpoint where it
-- stands), /cpdel, /cpclear, /cpswap a b and /cpsave, or /cpdefault for the map's own
-- again; /cphelp lists them.
--
-- For a run server: no bots, a long time_limit, a capture_limit far out of reach (9999),
-- as the default course takes the bravo flag home, max_grenades 0 (no grenades, nor their
-- kits), respawn_time 0 (the next run at once), and only run maps in the rotation.
-- vote_next.lua beside it lets the runners !vote.
--
-- What it keeps is in an SQLite database (runmode.db, by the server): each player's best
-- on each map, every run finished, and the admins' courses. Records kept by an older
-- runmode in runmode_records.json and runmode_courses.json are taken in at its first
-- start, the files then renamed .imported.

local options = {
    database = "runmode.db",          -- where the times and the courses are kept, from the server's folder
    radius = 30,                      -- how near a checkpoint a runner passes it, as the original's
    top = 10,                         -- the times !top shows
    kill_on_finish = true,            -- the runner killed at the finish, for the next run's respawn
    layer = 0,                        -- the first world text layer the checkpoints are shown on, one each
    scale = 0.8,                      -- their size, of the big messages' lettering
    color = "FF4040",                 -- a checkpoint's colour
    next_color = "40FF40",            -- the runner's next one's
    timer = {x = 320, y = 400, scale = 0.6, color = "FFFFFF", layer = 0,
             finish_y = 365, finish_color = "FFD700", finish_layer = 1},
                                      -- the runner's time on its screen (in the 640 by 480 view),
                                      -- the last run's time above it a while, and the screen text
                                      -- layers they are on; nil for none
}

local TICK_RATE = 60

local course = {}   -- the checkpoints, {x, y} each: the start first, the finish last; none for no run map
local runs = {}     -- slot -> {start = tick, next = the checkpoint ahead, x, y = where it was a tick ago}
local store = nil   -- the database
local shown = 0     -- the checkpoints shown in the world, on as many layers

-- ---------------------------------------------------------------------------------
-- The records, by map in lower case, so a map asked for is found however it is written

local SCHEMA = [[
CREATE TABLE IF NOT EXISTS times (    -- each player's best on each map
    map TEXT NOT NULL, hwid TEXT NOT NULL, name TEXT NOT NULL,
    ticks INTEGER NOT NULL, date INTEGER NOT NULL,
    PRIMARY KEY (map, hwid));
CREATE INDEX IF NOT EXISTS times_rank ON times (map, ticks, date);
CREATE TABLE IF NOT EXISTS runs (     -- every run finished; hwid NULL for a game that sent none
    id INTEGER PRIMARY KEY, map TEXT NOT NULL, hwid TEXT, name TEXT NOT NULL,
    ticks INTEGER NOT NULL, date INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS runs_map ON runs (map, date);
CREATE TABLE IF NOT EXISTS courses (  -- the admins' courses: each map's checkpoints, in order from 1
    map TEXT NOT NULL, n INTEGER NOT NULL, x REAL NOT NULL, y REAL NOT NULL,
    PRIMARY KEY (map, n));
]]

local function key(map)
    return map:lower()
end

-- The time kept if it is the player's first on the map, or better than its best.
local function keep_best(d, map, hwid, name, ticks, date)
    d:exec([[INSERT INTO times VALUES (?, ?, ?, ?, ?)
             ON CONFLICT (map, hwid) DO UPDATE SET name = excluded.name, ticks = excluded.ticks, date = excluded.date
             WHERE excluded.ticks < times.ticks]], key(map), hwid, name, ticks, date)
end

local function best_of(map, hwid)
    return store:first("SELECT name, ticks, date FROM times WHERE map = ? AND hwid = ?", key(map), hwid)
end

local function record_of(map)
    return store:first("SELECT hwid, name, ticks FROM times WHERE map = ? ORDER BY ticks, date LIMIT 1", key(map))
end

-- The map's best `n` times, best first.
local function top_of(map, n)
    return store:query("SELECT name, ticks, date FROM times WHERE map = ? ORDER BY ticks, date LIMIT ?", key(map), n)
end

-- The player's place among the map's times: one more than those faster, or as fast
-- and sooner.
local function rank_of(map, hwid)
    return store:first([[SELECT COUNT(*) + 1 AS rank FROM times t JOIN times me ON me.map = t.map AND me.hwid = ?
                         WHERE t.map = ? AND (t.ticks < me.ticks OR (t.ticks = me.ticks AND t.date < me.date))]],
        hwid, key(map)).rank
end

-- The checkpoints the admins saved for the map, or none.
local function saved_course(map)
    local course = {}
    for _, cp in ipairs(store:query("SELECT x, y FROM courses WHERE map = ? ORDER BY n", key(map))) do
        course[#course + 1] = {x = cp.x, y = cp.y}
    end
    return course
end

-- `course` the map's from now on; none, the map's own again.
local function save_course(map, course)
    store:transaction(function(d)
        d:exec("DELETE FROM courses WHERE map = ?", key(map))
        for i, cp in ipairs(course) do
            d:exec("INSERT INTO courses VALUES (?, ?, ?, ?)", key(map), i, cp.x, cp.y)
        end
    end)
end

-- An older runmode's JSON file, taken in by `take` and renamed .imported, if it is there.
local function import_json(path, take)
    local file = io.open(path, "r")
    if not file then return end
    local text = file:read("a")
    file:close()
    local ok, decoded = pcall(json.decode, text)
    if not ok or type(decoded) ~= "table" then
        server.print("runmode: " .. path .. " isn't JSON; left as it is")
        return
    end
    store:transaction(function(d) take(d, decoded) end)
    os.rename(path, path .. ".imported")
    server.print("runmode: " .. path .. " taken into " .. options.database)
end

local function open_store()
    store = assert(db.open(options.database))
    store:exec(SCHEMA)
    import_json("runmode_records.json", function(d, records)
        for map, players in pairs(records) do
            for hwid, r in pairs(players) do keep_best(d, map, hwid, r.name, r.ticks, r.date) end
        end
    end)
    import_json("runmode_courses.json", function(d, courses)
        for map, checkpoints in pairs(courses) do
            for i, cp in ipairs(checkpoints) do d:exec("INSERT OR REPLACE INTO courses VALUES (?, ?, ?, ?)", key(map), i, cp.x, cp.y) end
        end
    end)
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

-- The map's course: the one its admins saved, else the alpha spawn, the bravo flag and
-- the alpha flag. None for a map without the three, which isn't a run map.
local function course_of_map()
    local saved = saved_course(server.map())
    if #saved >= 2 then return saved end
    local spawns = server.spawns()
    local start, turn, finish = spawn_of(spawns, "alpha"), spawn_of(spawns, "bravo_flag"), spawn_of(spawns, "alpha_flag")
    if not (start and turn and finish) then return {} end
    return {start, turn, finish}
end

-- A course is run from its start to its finish: two checkpoints at least.
local function runnable()
    return #course >= 2
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

-- What checkpoint `i` says: the start, the finish, or its number between them.
local function label(i)
    if i == 1 then return "Start" end
    if i == #course then return "Finish" end
    return tostring(i - 1)
end

-- Checkpoint `i` in the world, in `color`: to everyone, or to `slot` alone.
local function show_checkpoint(i, color, slot)
    local cp = course[i]
    local style = {color = color, scale = options.scale}
    if slot then
        server.world_text_to(slot, options.layer + i - 1, label(i), cp.x, cp.y, style)
    else
        server.world_text(options.layer + i - 1, label(i), cp.x, cp.y, style)
    end
end

-- The runner's next checkpoint shown as the next, or as any other again.
local function mark_next(slot, run, marked)
    if not course[run.next] then return end
    show_checkpoint(run.next, marked and options.next_color or options.color, slot)
end

-- The runner's time on its screen: counting from the run's start (its game counts it), or
-- (none) taken away.
local function show_timer(slot, start)
    local t = options.timer
    if not t then return end
    if start then
        server.screen_text_to(slot, t.layer, "", t.x, t.y, {clock = start, scale = t.scale, color = t.color})
    else
        server.screen_text_to(slot, t.layer, "")
    end
end

-- A run's time, above the timer for a few seconds: the next run's begins below it at once.
local function show_finish(slot, ticks)
    local t = options.timer
    if t then server.screen_text_to(slot, t.finish_layer, show_time(ticks), t.x, t.finish_y, {seconds = 3, scale = t.scale, color = t.finish_color}) end
end

-- The run over: its next checkpoint as any other again, and its timer gone, for a runner
-- still on.
local function end_run(slot)
    local run = runs[slot]
    if not run then return end
    runs[slot] = nil
    if not server.player(slot) then return end
    mark_next(slot, run, false)
    show_timer(slot)
end

-- Where the player in `slot` is placed: at the start, on a course that can be run.
local function place_at_start(slot)
    if runnable() then
        server.set_spawn(slot, course[1].x, course[1].y)
    else
        server.set_spawn(slot)
    end
end

-- The course as it is now, to everyone: every run ended, the checkpoints shown (and
-- those no longer on it taken away), everyone placed at its start.
local function course_changed()
    for slot in pairs(runs) do end_run(slot) end
    for i = 1, #course do show_checkpoint(i, options.color) end
    for i = #course + 1, shown do server.world_text(options.layer + i - 1, "") end
    shown = #course
    for _, p in ipairs(server.players()) do place_at_start(p.slot) end
end

local function set_course()
    runs = {}
    shown = 0 -- a new round shows nothing of the last
    course = course_of_map()
    if #course == 0 then
        server.print(("runmode: %s has no course of its own, nor alpha spawn, bravo flag and alpha flag"):format(server.map()))
    end
    course_changed()
end

-- ---------------------------------------------------------------------------------
-- The runs

local function finish(slot, p, ticks)
    local map = server.map()
    show_finish(slot, ticks)
    if options.kill_on_finish then server.kill(slot) end
    store:exec("INSERT INTO runs (map, hwid, name, ticks, date) VALUES (?, ?, ?, ?, ?)", key(map), p.hwid, p.name, ticks, os.time())
    if not p.hwid then
        server.say(("%s %s"):format(p.name, show_time(ticks)), rank_color(0))
        server.say_to(slot, "Your game sent no hardware ID: the time isn't kept")
        return
    end

    local record = record_of(map)
    local mine = best_of(map, p.hwid)
    if mine and ticks >= mine.ticks then
        server.say_to(slot, ("%s, %s slower than your best"):format(show_time(ticks), show_diff(ticks - mine.ticks)))
        return
    end

    keep_best(store, map, p.hwid, p.name, ticks, os.time())
    local rank = rank_of(map, p.hwid)
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

-- The runner placed: at the start, the run begins; elsewhere (as a new round places
-- everyone before the course is known), killed, to be placed at the start.
server.on("spawn", function(slot)
    local p = server.player(slot)
    end_run(slot)
    if not runnable() or not p or p.team ~= "alpha" then return end
    local dx, dy = p.x - course[1].x, p.y - course[1].y
    if dx * dx + dy * dy > options.radius * options.radius then
        place_at_start(slot)
        server.kill(slot)
        return
    end
    local run = {start = server.tick(), next = 2, x = p.x, y = p.y}
    runs[slot] = run
    mark_next(slot, run, true)
    show_timer(slot, run.start)
end)

server.on("tick", function(tick)
    if not runnable() then return end
    for slot, run in pairs(runs) do
        local p = server.player(slot)
        if not p or not p.alive then
            end_run(slot)
        else
            local cp = course[run.next]
            if passes(cp, run.x, run.y, p.x, p.y) then
                local ticks = tick - run.start
                if run.next == #course then
                    end_run(slot)
                    finish(slot, p, ticks)
                else
                    server.say_to(slot, ("Checkpoint %d/%d  %s"):format(run.next, #course, show_time(ticks)), "6495ED")
                    mark_next(slot, run, false)
                    run.next = run.next + 1
                    mark_next(slot, run, true)
                end
            end
            run.x, run.y = p.x, p.y
        end
    end
end)

server.on("kill", function(killer, victim) end_run(victim) end)
server.on("leave", function(slot) runs[slot] = nil end)
server.on("round_end", function() runs = {} end)
server.on("round_start", function() set_course() end)

-- Everyone on alpha: the team menu's bravo is taken back within the second.
server.on("join", function(slot, name, player)
    place_at_start(slot)
    if player.bot then return end
    server.say_to(slot, "Run mode: from the start through the checkpoints to the finish, against the clock. !help for more.", "6495ED")
end)

server.on("second", function()
    for _, p in ipairs(server.players()) do
        if not p.bot and p.team == "bravo" then server.set_team(p.slot, "alpha") end
    end
end)

-- ---------------------------------------------------------------------------------
-- The commands

local function say_top(slot, map)
    local list = top_of(map, options.top)
    if #list == 0 then
        server.say_to(slot, "No times on " .. map)
        return
    end
    server.say_to(slot, ("%s, the best %d:"):format(map, #list), "6495ED")
    for i, r in ipairs(list) do
        server.say_to(slot, ("[%d] %s %s, %s"):format(i, r.name, show_time(r.ticks), os.date("%Y-%m-%d", r.date)), rank_color(i))
    end
end

-- ---------------------------------------------------------------------------------
-- The admins' course: changed as they go, shown to everyone at once, and the map's from
-- /cpsave on; unsaved, the next round has the saved one again.

local COURSE_HELP = {
    "/cpadd - a checkpoint where you stand, after the last (the first is the start, the last the finish)",
    "/cpdel - the last checkpoint taken away; /cpclear - all of them, to begin again",
    "/cpswap a b - checkpoints a and b change places, counted from 1 at the start",
    "/cpsave - this course kept as the map's; /cpdefault - the map's own again (alpha spawn, bravo flag, alpha flag)",
}

local function tell(slot, text)
    server.say_to(slot, text, "6495ED")
end

local function course_told(slot, what)
    course_changed()
    local state = runnable() and "" or " (not run until it has a start and a finish)"
    tell(slot, ("%s: %d checkpoints%s. /cpsave keeps it."):format(what, #course, state))
end

-- What each command does, given the admin's player and the rest of its line.
local course_commands = {
    cphelp = function(slot)
        for _, line in ipairs(COURSE_HELP) do tell(slot, line) end
    end,
    cpadd = function(slot, p)
        if not p.alive then return tell(slot, "Stand where the checkpoint goes: you're not alive") end
        course[#course + 1] = {x = p.x, y = p.y}
        course_told(slot, "Checkpoint " .. #course .. " added")
    end,
    cpdel = function(slot)
        if #course == 0 then return tell(slot, "No checkpoints to take away") end
        course[#course] = nil
        course_told(slot, "The last checkpoint taken away")
    end,
    cpclear = function(slot)
        course = {}
        course_told(slot, "All checkpoints taken away")
    end,
    cpswap = function(slot, p, rest)
        local a, b = rest:match("^(%d+)%s+(%d+)$")
        a, b = tonumber(a), tonumber(b)
        if not (a and b and course[a] and course[b]) then
            return tell(slot, ("/cpswap a b, each from 1 to %d"):format(#course))
        end
        course[a], course[b] = course[b], course[a]
        course_told(slot, ("Checkpoints %d and %d swapped"):format(a, b))
    end,
    cpsave = function(slot)
        if not runnable() then return tell(slot, "A course needs a start and a finish, two checkpoints at least") end
        save_course(server.map(), course)
        tell(slot, ("The course of %d checkpoints is %s's now"):format(#course, server.map()))
    end,
    cpdefault = function(slot)
        save_course(server.map(), {})
        course = course_of_map()
        course_told(slot, "The map's own course again")
    end,
}

server.on("command", function(slot, text)
    local word, rest = text:match("^(%S+)%s*(.-)%s*$")
    local command = word and course_commands[word:lower()]
    if not command then return end
    local p = server.player(slot)
    if not p.admin then
        tell(slot, "The course is the admins' to change: /login first")
        return true
    end
    command(slot, p, rest)
    return true
end)

server.on("chat", function(slot, text)
    local word, rest = text:match("^!(%S+)%s*(.-)%s*$")
    if not word then return end
    if word == "fail" then
        -- the run given up: the runner killed, and placed at the start again for the next.
        -- The line is kept from everyone, as a key bound to it may say it often.
        server.kill(slot)
        return true
    elseif word == "top" then
        say_top(slot, rest ~= "" and rest or server.map())
    elseif word == "best" then
        local p = server.player(slot)
        local map = server.map()
        local mine = p.hwid and best_of(map, p.hwid)
        if mine then
            local rank = rank_of(map, p.hwid)
            server.say_to(slot, ("Your best on %s: [%d] %s"):format(map, rank, show_time(mine.ticks)), rank_color(rank))
        else
            server.say_to(slot, "No time of yours on " .. map)
        end
    elseif word == "help" then
        server.say_to(slot, "Run from the start through each checkpoint, in order, to the finish; the clock starts as you're placed.", "6495ED")
        server.say_to(slot, "A death ends the run; the next starts at the respawn. Your best is kept by your machine.", "6495ED")
        server.say_to(slot, "!fail - give up the run and start again (bind it to a taunt)", "6495ED")
        server.say_to(slot, "!top [map] - the best times, !best - your own on this map", "6495ED")
        local p = server.player(slot)
        if p and p.admin then server.say_to(slot, "/cphelp - the commands that make this map's course", "6495ED") end
    end
end)

open_store()
set_course()
