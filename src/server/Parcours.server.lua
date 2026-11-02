--[[
	HIMMELSPFAD – ein Geschicklichkeits-Parcours für Roblox

	Dieses Skript baut beim Start den kompletten Parcours selbst auf
	und steuert alle Fallen, Checkpoints, die Zeitmessung und die Bestzeiten.

	Einbau: als Script in ServerScriptService legen.
	Dazu gehört das LocalScript "HUD" in StarterPlayer > StarterPlayerScripts.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local DataStoreService = game:GetService("DataStoreService")

----------------------------------------------------------------------
-- Einstellungen
----------------------------------------------------------------------

local BASIS_Y = 80 -- Höhe der Startplattform
local LAVA_Y = BASIS_Y - 45 -- Höhe des Lavasees unter dem Parcours
local SPRUNGKRAFT = 95 -- Startgeschwindigkeit der Sprungfelder (≈ 23 Studs hoch)

local FARBEN = {
	Start = Color3.fromRGB(90, 200, 255),
	Stein = Color3.fromRGB(236, 236, 245),
	Checkpoint = Color3.fromRGB(70, 200, 110),
	CheckpointPad = Color3.fromRGB(110, 255, 150),
	Lava = Color3.fromRGB(255, 75, 30),
	Beweglich = Color3.fromRGB(170, 120, 255),
	Dreh = Color3.fromRGB(255, 196, 70),
	Saeule = Color3.fromRGB(60, 60, 70),
	Broeckel = Color3.fromRGB(205, 160, 110),
	BroeckelWarnung = Color3.fromRGB(255, 110, 80),
	Blink = Color3.fromRGB(80, 170, 255),
	Band = Color3.fromRGB(55, 55, 65),
	Sprung = Color3.fromRGB(120, 255, 90),
	Balken = Color3.fromRGB(255, 140, 200),
	Ziel = Color3.fromRGB(255, 210, 40),
	Neustart = Color3.fromRGB(80, 200, 255),
}

----------------------------------------------------------------------
-- Grundgerüst
----------------------------------------------------------------------

local remote = ReplicatedStorage:FindFirstChild("ParcoursNachricht")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "ParcoursNachricht"
	remote.Parent = ReplicatedStorage
end

local alteKarte = workspace:FindFirstChild("Parcours")
if alteKarte then
	alteKarte:Destroy()
end
local karte = Instance.new("Folder")
karte.Name = "Parcours"
karte.Parent = workspace

-- Stimmung: später Nachmittag mit leichtem Dunst
Lighting.ClockTime = 16.8
Lighting.Brightness = 2.5
if not Lighting:FindFirstChildOfClass("Atmosphere") then
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.3
	atmo.Haze = 1.5
	atmo.Color = Color3.fromRGB(255, 220, 190)
	atmo.Decay = Color3.fromRGB(255, 140, 90)
	atmo.Parent = Lighting
end

-- Erzeugt ein verankertes Part mit den angegebenen Eigenschaften.
local function teil(eigenschaften)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for name, wert in eigenschaften do
		if name ~= "Parent" then
			p[name] = wert
		end
	end
	p.Parent = eigenschaften.Parent or karte
	return p
end

-- Plattform, deren OBERKANTE mittig bei `oben` liegt.
local function plattform(oben, groesse, farbe, material)
	return teil({
		Name = "Plattform",
		Size = groesse,
		CFrame = CFrame.new(oben - Vector3.new(0, groesse.Y / 2, 0)),
		Color = farbe,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function schild(anker, text, farbe, hoehe)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 50)
	bb.StudsOffset = Vector3.new(0, hoehe or 6, 0)
	bb.MaxDistance = 120
	bb.AlwaysOnTop = false
	bb.Parent = anker
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = farbe or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.3
	l.Parent = bb
end

local function humanoidVon(treffer)
	local modell = treffer.Parent
	if not modell then
		return nil
	end
	return modell:FindFirstChildOfClass("Humanoid")
end

----------------------------------------------------------------------
-- Fallen-Bausteine
----------------------------------------------------------------------

local beweger = {} -- hin- und herfahrende Teile
local dreher = {} -- rotierende Balken
local blinker = {} -- Plattformen, die im Takt verschwinden
local bewegteFallen = {} -- bewegte tödliche Teile, die zusätzlich per Überlappung geprüft werden

local function toedlich(p)
	CollectionService:AddTag(p, "Toedlich")
	p.Touched:Connect(function(treffer)
		local hum = humanoidVon(treffer)
		if hum and hum.Health > 0 then
			hum.Health = 0
		end
	end)
end

-- Lässt ein Teil sinusförmig entlang `achse` pendeln.
local function bewegen(p, achse, weite, tempo, phase)
	table.insert(beweger, {
		teil = p,
		basis = p.CFrame,
		achse = achse.Unit,
		weite = weite,
		tempo = tempo,
		phase = phase or 0,
	})
end

-- Plattform zerbröckelt kurz nach dem Betreten und kommt später zurück.
local function broeckeln(p)
	local aktiv = false
	local farbe = p.Color
	p.Touched:Connect(function(treffer)
		if aktiv or not Players:GetPlayerFromCharacter(treffer.Parent) then
			return
		end
		aktiv = true
		p.Color = FARBEN.BroeckelWarnung
		task.delay(0.6, function()
			p.Transparency = 0.85
			p.CanCollide = false
			task.delay(3, function()
				p.Transparency = 0
				p.CanCollide = true
				p.Color = farbe
				aktiv = false
			end)
		end)
	end)
end

----------------------------------------------------------------------
-- Checkpoints & Spielerdaten
----------------------------------------------------------------------

local checkpoints = {} -- [index] = CFrame zum Wiedereinstieg
local spielerDaten = {} -- [Player] = { abschnitt, laufStart, tode, bestzeit, ... }

local function formatZeit(sekunden)
	local minuten = math.floor(sekunden / 60)
	return string.format("%d:%05.2f", minuten, sekunden - minuten * 60)
end

local function richtungVorwaerts(position)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

local function setzeAbschnitt(spieler, index)
	local d = spielerDaten[spieler]
	if not d then
		return
	end
	d.abschnitt = index
	d.werte.Abschnitt.Value = index
	spieler:SetAttribute("Abschnitt", index)
end

-- Legt einen Checkpoint auf die Oberfläche bei `oben`.
local function neuerCheckpoint(oben)
	local index = #checkpoints + 1
	checkpoints[index] = richtungVorwaerts(oben + Vector3.new(0, 4, 0))
	if index == 1 then
		return -- Der Start braucht kein Pad
	end

	local pad = teil({
		Name = "Checkpoint" .. index,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 9, 9),
		CFrame = CFrame.new(oben + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = FARBEN.CheckpointPad,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	schild(pad, "Checkpoint " .. (index - 1), FARBEN.CheckpointPad, 5)

	pad.Touched:Connect(function(treffer)
		local spieler = Players:GetPlayerFromCharacter(treffer.Parent)
		local hum = humanoidVon(treffer)
		if not spieler or not hum or hum.Health <= 0 then
			return
		end
		local d = spielerDaten[spieler]
		if d and index > d.abschnitt then
			setzeAbschnitt(spieler, index)
			remote:FireClient(spieler, "checkpoint", index - 1)
		end
	end)
end

----------------------------------------------------------------------
-- Parcours aufbauen
-- z = Vorderkante der letzten Plattform, y = Höhe ihrer Oberfläche
----------------------------------------------------------------------

local z = 0
local y = BASIS_Y

local function checkpointPlattform(luecke)
	z += (luecke or 5) + 7
	plattform(Vector3.new(0, y, z), Vector3.new(14, 2, 14), FARBEN.Checkpoint)
	neuerCheckpoint(Vector3.new(0, y, z))
	z += 7
end

-- START ---------------------------------------------------------------
local startPlattform = plattform(Vector3.new(0, y, 0), Vector3.new(24, 2, 24), FARBEN.Start, Enum.Material.Glass)
schild(startPlattform, "HIMMELSPFAD", FARBEN.Ziel, 14)
neuerCheckpoint(Vector3.new(0, y, -5))
z = 12

local spawn = Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Size = Vector3.new(6, 0.4, 6)
spawn.CFrame = CFrame.new(0, y + 0.2, -5)
spawn.Transparency = 1
spawn.CanCollide = false
spawn.Duration = 0
spawn.Neutral = true
spawn.Parent = karte
local decal = spawn:FindFirstChildOfClass("Decal")
if decal then
	decal:Destroy()
end

-- Startbogen mit unsichtbarer Startlinie
for _, x in { -11, 11 } do
	teil({ Size = Vector3.new(2, 10, 2), CFrame = CFrame.new(x, y + 5, 10), Color = FARBEN.Saeule })
end
teil({
	Size = Vector3.new(24, 1.5, 2),
	CFrame = CFrame.new(0, y + 10.5, 10),
	Color = FARBEN.Start,
	Material = Enum.Material.Neon,
})
local startLinie = teil({
	Name = "Startlinie",
	Size = Vector3.new(20, 9, 1),
	CFrame = CFrame.new(0, y + 4.5, 10),
	Transparency = 1,
	CanCollide = false,
})

-- 1) SPRUNGSTEINE -------------------------------------------------------
for _, x in { 0, 4, -3, 5, -4, 2, 0 } do
	z += 5 + 3
	y += 0.6
	plattform(Vector3.new(x, y, z), Vector3.new(6, 1, 6), FARBEN.Stein)
	z += 3
end
checkpointPlattform()

-- 2) LAVASTEG: schmaler Steg mit Lavablöcken zum Überspringen ------------
z += 4
local stegLaenge = 66
plattform(Vector3.new(0, y, z + stegLaenge / 2), Vector3.new(3, 1, stegLaenge), FARBEN.Stein)
for i = 1, 5 do
	local hoehe = (i % 2 == 0) and 1.8 or 1.1
	local block = teil({
		Name = "Lavablock",
		Size = Vector3.new(3.6, hoehe, 1.6),
		CFrame = CFrame.new(0, y + hoehe / 2, z + i * 11),
		Color = FARBEN.Lava,
		Material = Enum.Material.Neon,
	})
	toedlich(block)
end
z += stegLaenge
checkpointPlattform(4)

-- 3) SCHWEBEPLATTFORMEN ---------------------------------------------------
for i = 1, 4 do
	z += 5 + 4
	local p = plattform(Vector3.new(0, y, z), Vector3.new(8, 1, 8), FARBEN.Beweglich, Enum.Material.Glass)
	if i < 4 then
		bewegen(p, Vector3.xAxis, 9, 0.9 + i * 0.15, i * 1.3)
	else
		bewegen(p, Vector3.yAxis, 4, 1.2, 0)
	end
	z += 4
end
checkpointPlattform()

-- 4) DREHBALKEN: über die rotierenden Lavabalken springen ------------------
for i = 1, 2 do
	z += 5 + 9
	local mitte = Vector3.new(0, y, z)
	plattform(mitte, Vector3.new(18, 1, 18), FARBEN.Dreh)
	teil({ Size = Vector3.new(2, 3, 2), CFrame = CFrame.new(mitte + Vector3.new(0, 1.5, 0)), Color = FARBEN.Saeule })
	local drehpunkt = mitte + Vector3.new(0, 2, 0)
	for b = 1, i do -- erst ein Balken, dann ein Kreuz
		local balken = teil({
			Name = "Drehbalken",
			Size = Vector3.new(25, 1, 1),
			CFrame = CFrame.new(drehpunkt),
			Color = FARBEN.Lava,
			Material = Enum.Material.Neon,
		})
		toedlich(balken)
		table.insert(bewegteFallen, balken)
		table.insert(dreher, {
			teil = balken,
			mitte = drehpunkt,
			tempo = (i == 1) and 1.6 or -1.25,
			winkel = (b - 1) * math.pi / 2,
		})
	end
	z += 9
end
checkpointPlattform()

-- 5) LAUFBAND: rückwärts laufendes Band mit Hindernissen -------------------
z += 5
local bandLaenge = 56
local band = plattform(
	Vector3.new(0, y, z + bandLaenge / 2),
	Vector3.new(7, 1, bandLaenge),
	FARBEN.Band,
	Enum.Material.DiamondPlate
)
band.AssemblyLinearVelocity = Vector3.new(0, 0, -9) -- schiebt Spieler zurück
for i = 1, 5 do
	local x = (i % 2 == 0) and 2 or -2
	local block = teil({
		Name = "Lavablock",
		Size = Vector3.new(3, 1.5, 1.5),
		CFrame = CFrame.new(x, y + 0.75, z + i * 9),
		Color = FARBEN.Lava,
		Material = Enum.Material.Neon,
	})
	toedlich(block)
end
z += bandLaenge
checkpointPlattform(3)

-- 6) BRÖCKELPLATTEN: nicht stehen bleiben! ---------------------------------
for i, x in { -3, 3, -3, 3, -3, 0 } do
	z += 4.5 + 3
	local p = plattform(Vector3.new(x, y, z), Vector3.new(6, 1, 6), FARBEN.Broeckel, Enum.Material.Sand)
	broeckeln(p)
	z += 3
end
checkpointPlattform()

-- 7) BLINKPLATTEN: zwei Gruppen erscheinen abwechselnd ---------------------
for i = 1, 6 do
	z += 4 + 3.5
	local p = plattform(Vector3.new(0, y, z), Vector3.new(7, 1, 7), FARBEN.Blink, Enum.Material.Neon)
	table.insert(blinker, { teil = p, phase = (i % 2) * 1.5, sichtbar = nil, warnung = nil })
	z += 3.5
end
checkpointPlattform()

-- 8) SPRUNGFELD: hinauf aufs Hochplateau -----------------------------------
z += 4 + 7
plattform(Vector3.new(0, y, z), Vector3.new(14, 2, 14), FARBEN.Stein)
local sprungfeld = teil({
	Name = "Sprungfeld",
	Size = Vector3.new(6, 0.4, 6),
	CFrame = CFrame.new(0, y + 0.2, z + 3),
	Color = FARBEN.Sprung,
	Material = Enum.Material.Neon,
	CanCollide = false,
})
sprungfeld:SetAttribute("Kraft", SPRUNGKRAFT)
CollectionService:AddTag(sprungfeld, "Sprungfeld")
schild(sprungfeld, "⬆ SPRUNGFELD ⬆", FARBEN.Sprung, 4)
z += 7
y += 18
checkpointPlattform(5)

-- 9) BALANCIERBALKEN mit Pendelfallen --------------------------------------
for i, x in { -3, 3, -3, 3 } do
	z += 3
	local laenge = 14
	plattform(Vector3.new(x, y, z + laenge / 2), Vector3.new(1.6, 1, laenge), FARBEN.Balken)
	local falle = teil({
		Name = "Pendelfalle",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(x, y + 2, z + laenge / 2),
		Color = FARBEN.Lava,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	toedlich(falle)
	table.insert(bewegteFallen, falle)
	bewegen(falle, Vector3.xAxis, 6, 1.4 + i * 0.2, i)
	z += laenge
end

-- ZIEL -----------------------------------------------------------------
z += 4 + 12
local zielMitte = Vector3.new(0, y, z)
plattform(zielMitte, Vector3.new(24, 2, 24), FARBEN.Ziel, Enum.Material.Foil)
local zielPad = teil({
	Name = "Ziel",
	Size = Vector3.new(14, 0.4, 4),
	CFrame = CFrame.new(zielMitte + Vector3.new(0, 0.2, -6)),
	Color = FARBEN.Ziel,
	Material = Enum.Material.Neon,
	CanCollide = false,
})
schild(zielPad, "🏁 ZIEL 🏁", FARBEN.Ziel, 8)
for _, x in { -8, 8 } do
	teil({ Size = Vector3.new(1.5, 9, 1.5), CFrame = CFrame.new(x, y + 4.5, z - 6), Color = FARBEN.Ziel, Material = Enum.Material.Neon })
end

local konfetti = Instance.new("ParticleEmitter")
konfetti.Enabled = false
konfetti.Rate = 0
konfetti.Lifetime = NumberRange.new(2, 3)
konfetti.Speed = NumberRange.new(25, 40)
konfetti.SpreadAngle = Vector2.new(35, 35)
konfetti.Acceleration = Vector3.new(0, -30, 0)
konfetti.Size = NumberSequence.new(0.5)
konfetti.RotSpeed = NumberRange.new(-200, 200)
konfetti.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 60)),
})
konfetti.Parent = zielPad

local neustartPad = teil({
	Name = "Neustart",
	Size = Vector3.new(6, 0.4, 6),
	CFrame = CFrame.new(zielMitte + Vector3.new(0, 0.2, 7)),
	Color = FARBEN.Neustart,
	Material = Enum.Material.Neon,
	CanCollide = false,
})
schild(neustartPad, "↺ NOCHMAL", FARBEN.Neustart, 4)

-- LAVASEE unter allem ----------------------------------------------------
local lava = teil({
	Name = "Lavasee",
	Size = Vector3.new(2048, 2, 2048),
	CFrame = CFrame.new(0, LAVA_Y, z / 2),
	Color = FARBEN.Lava,
	Material = Enum.Material.CrackedLava,
})
toedlich(lava)

ReplicatedStorage:SetAttribute("AnzahlCheckpoints", #checkpoints - 1)

----------------------------------------------------------------------
-- Bestzeiten speichern (funktioniert nur in veröffentlichten Spielen
-- bzw. wenn in Studio "Enable Studio Access to API Services" aktiv ist)
----------------------------------------------------------------------

local speicherOk, speicher = pcall(function()
	return DataStoreService:GetDataStore("Himmelspfad_Bestzeiten_v1")
end)
if not speicherOk then
	speicher = nil
end

local function ladeBestzeit(spieler)
	if not speicher then
		return nil
	end
	local ok, wert = pcall(function()
		return speicher:GetAsync(tostring(spieler.UserId))
	end)
	return ok and tonumber(wert) or nil
end

local function speichereBestzeit(spieler, zeit)
	if not speicher then
		return
	end
	task.spawn(function()
		pcall(function()
			speicher:UpdateAsync(tostring(spieler.UserId), function(alt)
				if alt and tonumber(alt) and tonumber(alt) <= zeit then
					return nil -- vorhandene Zeit ist besser
				end
				return zeit
			end)
		end)
	end)
end

----------------------------------------------------------------------
-- Spieler
----------------------------------------------------------------------

local function laufBeginnen(spieler)
	local d = spielerDaten[spieler]
	if not d or d.laufStart or d.abschnitt ~= 1 then
		return
	end
	d.laufStart = workspace:GetServerTimeNow()
	d.tode = 0
	d.werte.Tode.Value = 0
	spieler:SetAttribute("LaufStart", d.laufStart)
	remote:FireClient(spieler, "start")
end

local function spielerBeitritt(spieler)
	local werte = Instance.new("Folder")
	werte.Name = "leaderstats"
	local abschnitt = Instance.new("IntValue")
	abschnitt.Name = "Abschnitt"
	abschnitt.Value = 1
	abschnitt.Parent = werte
	local tode = Instance.new("IntValue")
	tode.Name = "Tode"
	tode.Parent = werte
	local best = Instance.new("StringValue")
	best.Name = "Bestzeit"
	best.Value = "–"
	best.Parent = werte
	werte.Parent = spieler

	local d = {
		abschnitt = 1,
		laufStart = nil,
		tode = 0,
		bestzeit = nil,
		sperre = false,
		werte = { Abschnitt = abschnitt, Tode = tode, Bestzeit = best },
	}
	spielerDaten[spieler] = d
	spieler:SetAttribute("Abschnitt", 1)

	task.spawn(function()
		local zeit = ladeBestzeit(spieler)
		if zeit and spielerDaten[spieler] == d and (not d.bestzeit or zeit < d.bestzeit) then
			d.bestzeit = zeit
			best.Value = formatZeit(zeit)
		end
	end)

	local function charakterGeladen(charakter)
		local hum = charakter:WaitForChild("Humanoid")
		charakter:WaitForChild("HumanoidRootPart")
		task.wait() -- Roblox setzt den Charakter erst noch selbst an den Spawn
		if spielerDaten[spieler] ~= d then
			return
		end
		charakter:PivotTo(checkpoints[d.abschnitt] or checkpoints[1])
		hum.Died:Connect(function()
			d.tode += 1
			tode.Value = d.tode
		end)
	end

	spieler.CharacterAdded:Connect(charakterGeladen)
	if spieler.Character then
		task.spawn(charakterGeladen, spieler.Character)
	end
end

Players.RespawnTime = 1.5 -- schnell wieder einsteigen
Players.PlayerAdded:Connect(spielerBeitritt)
for _, spieler in Players:GetPlayers() do
	task.spawn(spielerBeitritt, spieler)
end
Players.PlayerRemoving:Connect(function(spieler)
	spielerDaten[spieler] = nil
end)

startLinie.Touched:Connect(function(treffer)
	local spieler = Players:GetPlayerFromCharacter(treffer.Parent)
	if spieler then
		laufBeginnen(spieler)
	end
end)

zielPad.Touched:Connect(function(treffer)
	local spieler = Players:GetPlayerFromCharacter(treffer.Parent)
	local d = spieler and spielerDaten[spieler]
	if not d or not d.laufStart or d.abschnitt < #checkpoints then
		return
	end
	local zeit = workspace:GetServerTimeNow() - d.laufStart
	d.laufStart = nil
	spieler:SetAttribute("LaufStart", nil)

	local neueBestzeit = not d.bestzeit or zeit < d.bestzeit
	if neueBestzeit then
		d.bestzeit = zeit
		d.werte.Bestzeit.Value = formatZeit(zeit)
		speichereBestzeit(spieler, zeit)
	end

	konfetti:Emit(120)
	remote:FireClient(spieler, "ziel", zeit, neueBestzeit, d.tode)
	for _, anderer in Players:GetPlayers() do
		if anderer ~= spieler then
			remote:FireClient(anderer, "meldung", spieler.DisplayName .. " ist im Ziel: " .. formatZeit(zeit))
		end
	end
end)

neustartPad.Touched:Connect(function(treffer)
	local spieler = Players:GetPlayerFromCharacter(treffer.Parent)
	local d = spieler and spielerDaten[spieler]
	if not d or d.sperre then
		return
	end
	d.sperre = true
	d.laufStart = nil
	spieler:SetAttribute("LaufStart", nil)
	setzeAbschnitt(spieler, 1)
	remote:FireClient(spieler, "neustart")
	spieler:LoadCharacter()
	task.delay(1, function()
		d.sperre = false
	end)
end)

----------------------------------------------------------------------
-- Bewegung aller Fallen (jeder Frame)
----------------------------------------------------------------------

local function pruefeFalle(falle)
	for _, t in workspace:GetPartsInPart(falle) do
		local hum = humanoidVon(t)
		if hum and hum.Health > 0 then
			hum.Health = 0
		end
	end
end

RunService.Heartbeat:Connect(function()
	local t = os.clock()

	for _, b in beweger do
		local winkel = t * b.tempo + b.phase
		b.teil.CFrame = b.basis + b.achse * (math.sin(winkel) * b.weite)
		-- Geschwindigkeit setzen, damit Spieler auf der Plattform mitfahren
		b.teil.AssemblyLinearVelocity = b.achse * (math.cos(winkel) * b.weite * b.tempo)
	end

	for _, d in dreher do
		d.teil.CFrame = CFrame.new(d.mitte) * CFrame.Angles(0, d.winkel + t * d.tempo, 0)
	end

	for _, bl in blinker do
		local takt = (t + bl.phase) % 3
		local sichtbar = takt < 2.2
		local warnung = sichtbar and takt > 1.6
		if sichtbar ~= bl.sichtbar or warnung ~= bl.warnung then
			bl.sichtbar = sichtbar
			bl.warnung = warnung
			bl.teil.CanCollide = sichtbar
			bl.teil.Transparency = if not sichtbar then 0.9 elseif warnung then 0.55 else 0
		end
	end

	for _, falle in bewegteFallen do
		pruefeFalle(falle)
	end
end)

print(("[Himmelspfad] Parcours gebaut: %d Checkpoints, Länge %d Studs"):format(#checkpoints - 1, math.floor(z)))
