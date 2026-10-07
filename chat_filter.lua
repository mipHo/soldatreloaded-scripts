-- Keeps lines with the words given out of the chat, and tells whoever said one
-- (docs/scripting.md). A kept line goes no further: not to the players, and not to the
-- handlers of the scripts after this one. Copy it into the server's
-- scripts/ and it runs as the server starts (or at script_reload).

local options = {
    words = {"noob"}, -- what a line may not hold, in any case
}

local words = {}
for _, word in ipairs(options.words) do words[#words + 1] = word:lower() end

server.on("chat", function(slot, text, team)
    local lower = text:lower()
    for _, word in ipairs(words) do
        if lower:find(word, 1, true) then
            server.say_to(slot, "That word stays with you.")
            return true
        end
    end
end)
