-- NEON STRIKE server entry: start the authoritative game server.
-- All game logic lives in StrikeServer; this file only boots it.
-- NOTE: Rojo turns this init file into the "Server" Script itself, so
-- StrikeServer is a CHILD of this script (ServerScriptService.Server
-- .StrikeServer), not a sibling under ServerScriptService. Requiring it
-- through script.Parent silently returns nil and kills the server.

local StrikeServer = require(script.StrikeServer)

StrikeServer.start()
