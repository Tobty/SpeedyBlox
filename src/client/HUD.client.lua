--[[
	SPEEDYBLOX – Anzeige (Stoppuhr, Abschnitt, Tode, Meldungen) und Sprungfelder

	Einbau: als LocalScript in StarterPlayer > StarterPlayerScripts legen.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local spieler = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("ParcoursNachricht")

local function formatZeit(sekunden)
	local minuten = math.floor(sekunden / 60)
	return string.format("%d:%05.2f", minuten, sekunden - minuten * 60)
end

----------------------------------------------------------------------
-- Oberfläche
----------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ParcoursHUD"
gui.ResetOnSpawn = false
gui.Parent = spieler:WaitForChild("PlayerGui")

local function kasten(name, groesse, position)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = groesse
	f.Position = position
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	f.BackgroundTransparency = 0.3
	f.Parent = gui
	local ecke = Instance.new("UICorner")
	ecke.CornerRadius = UDim.new(0, 12)
	ecke.Parent = f
	return f
end

local function text(eltern, groesse, position, schrift)
	local l = Instance.new("TextLabel")
	l.Size = groesse
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = schrift or Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Parent = eltern
	return l
end

local anzeige = kasten("Anzeige", UDim2.fromOffset(240, 78), UDim2.new(0.5, 0, 0, 8))
local zeitText = text(anzeige, UDim2.new(1, -16, 0, 44), UDim2.fromOffset(8, 4), Enum.Font.GothamBlack)
zeitText.Text = "0:00.00"
local infoText = text(anzeige, UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 50))
infoText.TextColor3 = Color3.fromRGB(190, 200, 220)

local meldungText = text(gui, UDim2.new(0.8, 0, 0, 60), UDim2.new(0.5, 0, 0.28, 0), Enum.Font.GothamBlack)
meldungText.AnchorPoint = Vector2.new(0.5, 0.5)
meldungText.TextStrokeTransparency = 0.2
meldungText.TextTransparency = 1
meldungText.TextStrokeTransparency = 1

local meldungNummer = 0
local function meldung(inhalt, farbe, dauer)
	meldungNummer += 1
	local nummer = meldungNummer
	meldungText.Text = inhalt
	meldungText.TextColor3 = farbe or Color3.new(1, 1, 1)
	meldungText.TextTransparency = 0
	meldungText.TextStrokeTransparency = 0.2
	meldungText.Size = UDim2.new(0.9, 0, 0, 72)
	TweenService:Create(meldungText, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.new(0.8, 0, 0, 60) }):Play()
	task.delay(dauer or 2, function()
		if nummer ~= meldungNummer then
			return
		end
		TweenService:Create(meldungText, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

local letzteZeit = nil -- eingefrorene Zeit nach dem Zieleinlauf

RunService.RenderStepped:Connect(function()
	local start = spieler:GetAttribute("LaufStart")
	if start then
		zeitText.Text = formatZeit(workspace:GetServerTimeNow() - start)
		zeitText.TextColor3 = Color3.new(1, 1, 1)
	elseif letzteZeit then
		zeitText.Text = formatZeit(letzteZeit)
		zeitText.TextColor3 = Color3.fromRGB(255, 215, 60)
	else
		zeitText.Text = "0:00.00"
		zeitText.TextColor3 = Color3.fromRGB(160, 170, 190)
	end

	local gesamt = ReplicatedStorage:GetAttribute("AnzahlCheckpoints") or 0
	local abschnitt = (spieler:GetAttribute("Abschnitt") or 1) - 1
	local stats = spieler:FindFirstChild("leaderstats")
	local tode = stats and stats:FindFirstChild("Tode")
	infoText.Text = string.format("Checkpoint %d/%d   ·   ☠ %d", abschnitt, gesamt, tode and tode.Value or 0)
end)

remote.OnClientEvent:Connect(function(art, a, b, c)
	if art == "start" then
		letzteZeit = nil
		meldung("Los geht's!", Color3.fromRGB(120, 220, 255), 1.5)
	elseif art == "checkpoint" then
		meldung("✔ Checkpoint " .. a, Color3.fromRGB(110, 255, 150), 1.5)
	elseif art == "ziel" then
		letzteZeit = a
		local zeile = "🏁 Ziel! " .. formatZeit(a)
		if b then
			zeile ..= "  –  NEUE BESTZEIT!"
		end
		meldung(zeile .. "\n" .. c .. " Tode · Stell dich auf ↺ für einen neuen Lauf", Color3.fromRGB(255, 215, 60), 5)
	elseif art == "neustart" then
		letzteZeit = nil
		meldung("Neuer Lauf – lauf durchs Starttor!", Color3.fromRGB(120, 220, 255), 2)
	elseif art == "meldung" then
		meldung(a, Color3.fromRGB(220, 220, 230), 2.5)
	end
end)

meldung("Willkommen bei SPEEDYBLOX!", Color3.fromRGB(255, 215, 60), 3)

----------------------------------------------------------------------
-- Sprungfelder (auf dem Client, weil der Spieler seine Figur selbst steuert)
----------------------------------------------------------------------

local sprungSperre = false

local function sprungfeld(pad)
	pad.Touched:Connect(function(treffer)
		local charakter = spieler.Character
		if sprungSperre or not charakter or treffer.Parent ~= charakter then
			return
		end
		local wurzel = charakter:FindFirstChild("HumanoidRootPart")
		local hum = charakter:FindFirstChildOfClass("Humanoid")
		if not wurzel or not hum or hum.Health <= 0 then
			return
		end
		sprungSperre = true
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
		local v = wurzel.AssemblyLinearVelocity
		wurzel.AssemblyLinearVelocity = Vector3.new(v.X, pad:GetAttribute("Kraft") or 90, v.Z)
		task.delay(0.5, function()
			sprungSperre = false
		end)
	end)
end

for _, pad in CollectionService:GetTagged("Sprungfeld") do
	sprungfeld(pad)
end
CollectionService:GetInstanceAddedSignal("Sprungfeld"):Connect(sprungfeld)
