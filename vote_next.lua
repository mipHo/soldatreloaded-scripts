-- !vote in the chat: a vote to move on to another map, picked at random from the server's
-- list. When more than half the players have voted (half and one), the round ends and
-- that map is played. A vote lasts until the round ends or its player leaves; !vote
-- again takes it back. Bots don't vote, nor count.

local options = {
    word = "vote", -- the command, said in the chat as !vote
}

local votes = {} -- slot -> true

-- The players who may vote: every person on, watching or playing.
local function voters()
    local n = 0
    for _, p in ipairs(server.players()) do
        if not p.bot then n = n + 1 end
    end
    return n
end

local function needed()
    return voters() // 2 + 1
end

local function count()
    local n = 0
    for _ in pairs(votes) do n = n + 1 end
    return n
end

-- Another of the server's maps, at random; nil when the one on is all there is.
local function random_map()
    local current = server.map():lower()
    local others = {}
    for _, name in ipairs(server.maps()) do
        if name:lower() ~= current then others[#others + 1] = name end
    end
    if #others == 0 then return nil end
    return others[math.random(#others)]
end

-- The vote passed, if enough have voted: the round ends, and a map at random is next.
local function check()
    local have = count()
    if have == 0 or have < needed() then return end
    votes = {}
    local map = random_map()
    if map and server.next_map(map) then
        server.say("The vote passed: next, " .. map, "FFD700")
    else
        server.say("The vote passed: the next map", "FFD700")
        server.next_map()
    end
end

server.on("chat", function(slot, text)
    if text:lower() ~= "!" .. options.word then return end
    local p = server.player(slot)
    if not p or p.bot then return end
    votes[slot] = not votes[slot] or nil
    server.say(("%s %s a vote for the next map (%d/%d). Say !%s to vote."):format(
        p.name, votes[slot] and "made" or "took back", count(), needed(), options.word), "FFD700")
    check()
end)

-- A player gone takes its vote, and leaves fewer to pass it: the others' may be enough.
server.on("leave", function(slot)
    votes[slot] = nil
    check()
end)

server.on("round_start", function() votes = {} end)
