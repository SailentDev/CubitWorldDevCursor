--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ServerLoader = require(ServerScriptService.ServerLoader)

-- Odpalamy centralny silnik ładowania, który sam uruchomi bazę, sieć i optymalizacje
ServerLoader.Boot()