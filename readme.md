# Soldat Reloaded scripts

Lua scripts for [Soldat Reloaded](https://github.com/soldatreloaded/soldatreloaded-odin)
servers: the examples that show the server's script API in use, and scripts of the
community's own. A script greets players, answers chat commands, keeps the chat clean,
runs a gather from the chat, reports each round to a webhook, or turns the server into a
run server against the clock.

## Installing a script

1. Copy its `.lua` into the server's scripts folder: `scripts/` beside the server, or the
   folder named by `server.scripts` in its `server.config.mjson`. The server runs every
   `.lua` in that folder, in order of their names, side by side in one state.
2. Change the settings at its top, in its `options` table: the names that may run
   `/hold`, the words the chat may not hold, the webhook's address.
3. Restart the server, or type `script_reload` at its console, which reads the scripts
   again from the start (their state is lost).

A script's errors are printed on the server's console, and the game goes on without the
call that failed.

## The scripts

| Script | What it does |
|---|---|
| [`greeter.lua`](greeter.lua) | greets whoever joins, and says each map as it begins |
| [`stats.lua`](stats.lua) | /stats and /top, kills called out every so many, captures and the winner said |
| [`chat_filter.lua`](chat_filter.lua) | keeps lines with the words given out of the chat |
| [`match_controls.lua`](match_controls.lua) | !pause, !up (a count of 3, 2, 1), !restart and !map <name>, for gathers |
| [`admin.lua`](admin.lua) | /hold, /go and /skip for the names given, for a game among friends |
| [`round_webhook.lua`](round_webhook.lua) | each round's result printed and sent to a webhook (Discord's, or any JSON one) |
| [`runmode.lua`](runmode.lua) | run mode: each player runs from the alpha spawn to the bravo flag and home to the alpha flag against the clock, the best time on each map kept by hardware ID; !top, !best, !help |

## Writing a script

The API, what a script hears (`server.on`) and what it may do (the `server` table, `http`
and `json`), is the server's
[docs/scripting.md](https://github.com/soldatreloaded/soldatreloaded-odin/blob/main/docs/scripting.md).
Hand the server your handlers with `server.on`, so your script runs beside the others,
and keep its own names `local`. A file only to be `require`d goes in a folder under
`scripts/` (`scripts/lib/util.lua`, as `require("lib.util")`), so it isn't run as a script
of its own.

To add a script here, fork this repository, add your `.lua` with its settings at its top
and a comment saying what it does, add it to the table above, and open a pull request.
