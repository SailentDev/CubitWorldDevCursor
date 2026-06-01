--!strict
local StarterPlayerScripts = script.Parent
local ClientLoader = require(StarterPlayerScripts:WaitForChild("ClientLoader") :: ModuleScript)

-- Uruchomienie centralnego loadera po stronie klienta
ClientLoader.Boot()