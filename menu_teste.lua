-- LocalScript
-- Onde colocar: StarterGui (ou StarterPlayer > StarterPlayerScripts)
-- Recursos: ESP (nome + distância), Chams (contorno/preenchimento), Fly e VFly (veículo) com velocidade ajustável

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local DISTANCIA_MAXIMA = 500 -- em studs (use math.huge para sem limite)
local COR_ESP = Color3.fromRGB(255, 255, 255)
local COR_CHAMS_CONTORNO = Color3.fromRGB(255, 60, 60)
local COR_CHAMS_PREENCHIMENTO = Color3.fromRGB(255, 60, 60)
local TRANSPARENCIA_PREENCHIMENTO = 0.6 -- 1 = só o contorno, 0 = totalmente preenchido
local VELOCIDADE_FLY_PADRAO = 60
local VELOCIDADE_VFLY_PADRAO = 80
local VELOCIDADE_MIN, VELOCIDADE_MAX = 1, 500

------------------------------------------------------------
-- ESTADO
------------------------------------------------------------
local estado = { esp = false, chams = false, fly = false, vfly = false, noclip = false, swim = false, xray = false, tptool = false }
local VELOCIDADE_SWIM_PADRAO = 40
local velocidadeSwim = VELOCIDADE_SWIM_PADRAO
local velocidadeFly = VELOCIDADE_FLY_PADRAO
local velocidadeVFly = VELOCIDADE_VFLY_PADRAO

local subindo, descendo = false, false -- teclas / botões de subir e descer

------------------------------------------------------------
-- INTERFACE
------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MenuTeste"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Botão que abre/fecha o menu (aparece com animação)
local botao = Instance.new("TextButton")
botao.Name = "BotaoMenu"
botao.AnchorPoint = Vector2.new(0.5, 0.5)
botao.Position = UDim2.new(0.5, 0, 0.92, 0)
botao.Size = UDim2.new(0, 0, 0, 0)
botao.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
botao.Text = "MENU"
botao.TextColor3 = Color3.new(1, 1, 1)
botao.Font = Enum.Font.GothamBold
botao.TextSize = 18
botao.AutoButtonColor = true
botao.BackgroundTransparency = 1
botao.TextTransparency = 1
botao.Parent = gui
Instance.new("UICorner", botao).CornerRadius = UDim.new(0, 12)

-- Painel do menu
local TAMANHO_PAINEL = UDim2.new(0, 300, 0, 750)

local painel = Instance.new("Frame")
painel.Name = "Painel"
painel.AnchorPoint = Vector2.new(0.5, 0.5)
painel.Position = UDim2.new(0.5, 0, 0.5, 0)
painel.Size = UDim2.new(0, 0, 0, 0)
painel.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
painel.Visible = false
painel.ClipsDescendants = true
painel.Parent = gui
Instance.new("UICorner", painel).CornerRadius = UDim.new(0, 14)

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, 0, 0, 40)
titulo.BackgroundTransparency = 1
titulo.Text = "Menu de Teste"
titulo.TextColor3 = Color3.new(1, 1, 1)
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 20
titulo.Parent = painel

local COR_OFF = Color3.fromRGB(170, 50, 50)
local COR_ON = Color3.fromRGB(50, 170, 80)

-- Cria uma linha do menu: botão liga/desliga (+ caixa de velocidade opcional)
local function criarLinha(y, nome, comVelocidade, velocidadePadrao)
	local b = Instance.new("TextButton")
	b.Name = "Botao" .. nome
	b.Position = UDim2.new(0.05, 0, 0, y)
	b.Size = comVelocidade and UDim2.new(0.55, 0, 0, 40) or UDim2.new(0.9, 0, 0, 40)
	b.BackgroundColor3 = COR_OFF
	b.Text = nome .. ": DESLIGADO"
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.Parent = painel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)

	local caixa = nil
	if comVelocidade then
		caixa = Instance.new("TextBox")
		caixa.Name = "Velocidade" .. nome
		caixa.Position = UDim2.new(0.65, 0, 0, y)
		caixa.Size = UDim2.new(0.3, 0, 0, 40)
		caixa.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
		caixa.Text = tostring(velocidadePadrao)
		caixa.PlaceholderText = "vel."
		caixa.TextColor3 = Color3.new(1, 1, 1)
		caixa.PlaceholderColor3 = Color3.fromRGB(140, 140, 140)
		caixa.Font = Enum.Font.GothamBold
		caixa.TextSize = 15
		caixa.ClearTextOnFocus = false
		caixa.Parent = painel
		Instance.new("UICorner", caixa).CornerRadius = UDim.new(0, 10)
	end
	return b, caixa
end

local botaoESP = criarLinha(50, "ESP", false)
local botaoChams = criarLinha(100, "CHAMS", false)
local botaoFly, caixaFly = criarLinha(150, "FLY", true, VELOCIDADE_FLY_PADRAO)
local botaoVFly, caixaVFly = criarLinha(200, "VFLY", true, VELOCIDADE_VFLY_PADRAO)

local botaoRejoin = criarLinha(250, "REJOIN", false)
botaoRejoin.Text = "REJOIN (reentrar no server)"
botaoRejoin.BackgroundColor3 = Color3.fromRGB(50, 110, 200)

local botaoNoclip = criarLinha(300, "NOCLIP", false)
local botaoSwim, caixaSwim = criarLinha(350, "SWIM", true, VELOCIDADE_SWIM_PADRAO)

local botaoSpawns = criarLinha(400, "SPAWNS", false)
botaoSpawns.Text = "SPAWNS (abrir lista)"
botaoSpawns.BackgroundColor3 = Color3.fromRGB(50, 110, 200)

local botaoTP = criarLinha(450, "TP", false)
botaoTP.Text = "TP (ir até jogadores)"
botaoTP.BackgroundColor3 = Color3.fromRGB(50, 110, 200)

local botaoXray, caixaXray = criarLinha(500, "XRAY", true, 0.6)

local botaoTPTool = criarLinha(550, "TPTOOL", false)

local dica = Instance.new("TextLabel")
dica.Position = UDim2.new(0.05, 0, 0, 605)
dica.Size = UDim2.new(0.9, 0, 0, 135)
dica.BackgroundTransparency = 1
dica.TextWrapped = true
dica.TextYAlignment = Enum.TextYAlignment.Top
dica.Text = "Fly: WASD/analógico para mover, mire a câmera para subir/descer.\nEspaço/E = subir, Shift/Q = descer.\nVFLY: use sentado em um veículo.\nNOCLIP: atravessa paredes (sem o Fly você cai pelo chão).\nSWIM: nada no ar como se estivesse na água.\nSPAWNS: salve posições, renomeie e volte a elas.\nTP: clique no nome de um jogador para ir até ele.\nXRAY: deixa o mapa transparente (caixa: 0 = normal, 0.95 = quase invisível).\nTPTOOL: dá um item no inventário; equipe e clique/toque onde quer ir."
dica.TextColor3 = Color3.fromRGB(170, 170, 180)
dica.Font = Enum.Font.Gotham
dica.TextSize = 12
dica.Parent = painel

-- Botões de subir/descer (úteis no celular), só aparecem voando
local function criarBotaoVertical(texto, y)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.new(0.92, 0, y, 0)
	b.Size = UDim2.new(0, 56, 0, 56)
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	b.BackgroundTransparency = 0.2
	b.Text = texto
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 24
	b.Visible = false
	b.Parent = gui
	Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
	return b
end

local botaoSobe = criarBotaoVertical("▲", 0.55)
local botaoDesce = criarBotaoVertical("▼", 0.68)

botaoSobe.MouseButton1Down:Connect(function() subindo = true end)
botaoSobe.MouseButton1Up:Connect(function() subindo = false end)
botaoSobe.MouseLeave:Connect(function() subindo = false end)
botaoDesce.MouseButton1Down:Connect(function() descendo = true end)
botaoDesce.MouseButton1Up:Connect(function() descendo = false end)
botaoDesce.MouseLeave:Connect(function() descendo = false end)

local function atualizarBotaoVertical()
	local visivel = estado.fly or estado.vfly or estado.swim
	botaoSobe.Visible = visivel
	botaoDesce.Visible = visivel
	if not visivel then
		subindo, descendo = false, false
	end
end

local function pintarBotao(b, nome, ligado)
	b.Text = nome .. (ligado and ": LIGADO" or ": DESLIGADO")
	b.BackgroundColor3 = ligado and COR_ON or COR_OFF
end

------------------------------------------------------------
-- ANIMAÇÃO DE ENTRADA DO BOTÃO
------------------------------------------------------------
task.wait(0.5)
TweenService:Create(botao, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
	Size = UDim2.new(0, 120, 0, 40),
	BackgroundTransparency = 0,
	TextTransparency = 0,
}):Play()

------------------------------------------------------------
-- ABRIR / FECHAR PAINEL
------------------------------------------------------------
local aberto = false

botao.MouseButton1Click:Connect(function()
	aberto = not aberto
	if aberto then
		painel.Visible = true
		TweenService:Create(painel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = TAMANHO_PAINEL,
		}):Play()
	else
		local t = TweenService:Create(painel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0),
		})
		t:Play()
		t.Completed:Connect(function()
			if not aberto then
				painel.Visible = false
			end
		end)
	end
end)

------------------------------------------------------------
-- ESP (nome + distância) e CHAMS (contorno/preenchimento)
------------------------------------------------------------
local espObjetos = {}   -- [Player] = { gui = BillboardGui, label = TextLabel }
local chamsObjetos = {} -- [Player] = Highlight

local function removerESP(p)
	local obj = espObjetos[p]
	if obj then
		obj.gui:Destroy()
		espObjetos[p] = nil
	end
end

local function removerChams(p)
	local h = chamsObjetos[p]
	if h then
		h:Destroy()
		chamsObjetos[p] = nil
	end
end

local function criarESP(p)
	if p == player then return end
	removerESP(p)

	local char = p.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "ESP_Nome"
	bb.Adornee = head
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 200, 0, 40)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "Texto"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = COR_ESP
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = p.DisplayName
	label.Parent = bb

	espObjetos[p] = { gui = bb, label = label }
end

local function criarChams(p)
	if p == player then return end
	removerChams(p)

	local char = p.Character
	if not char then return end

	local h = Instance.new("Highlight")
	h.Name = "Chams"
	h.FillColor = COR_CHAMS_PREENCHIMENTO
	h.FillTransparency = TRANSPARENCIA_PREENCHIMENTO
	h.OutlineColor = COR_CHAMS_CONTORNO
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- aparece através das paredes
	h.Parent = char

	chamsObjetos[p] = h
end

-- Recria o que estiver ligado para um jogador
local function atualizarJogador(p)
	if estado.esp then criarESP(p) else removerESP(p) end
	if estado.chams then criarChams(p) else removerChams(p) end
end

local function atualizarTodos()
	for _, p in ipairs(Players:GetPlayers()) do
		atualizarJogador(p)
	end
end

local function atualizarESP()
	if not estado.esp then return end

	local meuChar = player.Character
	local minhaRaiz = meuChar and meuChar:FindFirstChild("HumanoidRootPart")
	if not minhaRaiz then return end

	for p, obj in pairs(espObjetos) do
		local char = p.Character
		local raiz = char and char:FindFirstChild("HumanoidRootPart")
		if raiz then
			local dist = (raiz.Position - minhaRaiz.Position).Magnitude
			obj.gui.Enabled = dist <= DISTANCIA_MAXIMA
			obj.label.Text = string.format("%s\n[%d studs]", p.DisplayName, math.floor(dist))
		else
			obj.gui.Enabled = false
		end
	end
end

-- Jogadores novos / respawn
local function monitorar(p)
	if p == player then return end
	p.CharacterAdded:Connect(function()
		task.wait(0.5)
		atualizarJogador(p)
	end)
	if p.Character then
		atualizarJogador(p)
	end
end

for _, p in ipairs(Players:GetPlayers()) do
	monitorar(p)
end
Players.PlayerAdded:Connect(monitorar)
Players.PlayerRemoving:Connect(function(p)
	removerESP(p)
	removerChams(p)
end)

botaoESP.MouseButton1Click:Connect(function()
	estado.esp = not estado.esp
	pintarBotao(botaoESP, "ESP", estado.esp)
	atualizarTodos()
end)

botaoChams.MouseButton1Click:Connect(function()
	estado.chams = not estado.chams
	pintarBotao(botaoChams, "CHAMS", estado.chams)
	atualizarTodos()
end)

------------------------------------------------------------
-- VELOCIDADE (caixas de texto)
------------------------------------------------------------
local function lerVelocidade(caixa, atual)
	local n = tonumber(caixa.Text)
	if not n then
		caixa.Text = tostring(atual)
		return atual
	end
	n = math.clamp(n, VELOCIDADE_MIN, VELOCIDADE_MAX)
	caixa.Text = tostring(n)
	return n
end

caixaFly.FocusLost:Connect(function()
	velocidadeFly = lerVelocidade(caixaFly, velocidadeFly)
end)

caixaVFly.FocusLost:Connect(function()
	velocidadeVFly = lerVelocidade(caixaVFly, velocidadeVFly)
end)

caixaSwim.FocusLost:Connect(function()
	velocidadeSwim = lerVelocidade(caixaSwim, velocidadeSwim)
end)

------------------------------------------------------------
-- TECLAS (subir / descer)
------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processado)
	if processado then return end
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E then
		subindo = true
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.Q then
		descendo = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E then
		subindo = false
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.Q then
		descendo = false
	end
end)

------------------------------------------------------------
-- DIREÇÃO DE VOO (compartilhada entre FLY e VFLY)
------------------------------------------------------------
local function direcaoDeVoo(hum)
	local cam = workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local move = hum.MoveDirection
	local dir = move

	-- Ao andar para frente/trás, a inclinação da câmera sobe ou desce
	if move.Magnitude > 0 and flat.Magnitude > 0.001 then
		local frente = move:Dot(flat.Unit)
		dir = dir + Vector3.new(0, (look.Y / flat.Magnitude) * frente, 0)
	end

	-- Subir / descer manual
	local vertical = (subindo and 1 or 0) - (descendo and 1 or 0)
	dir = dir + Vector3.new(0, vertical, 0)

	if dir.Magnitude > 1 then
		dir = dir.Unit
	end
	return dir, flat
end

local function pegarPersonagem()
	local char = player.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local raiz = char:FindFirstChild("HumanoidRootPart")
	if hum and raiz and hum.Health > 0 then
		return raiz, hum
	end
	return nil
end

------------------------------------------------------------
-- FLY
------------------------------------------------------------
local flyBV, flyBG

local function pararFly()
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
	local _, hum = pegarPersonagem()
	if hum then hum.PlatformStand = false end
end

local function iniciarFly(raiz, hum)
	if flyBV then flyBV:Destroy() end
	if flyBG then flyBG:Destroy() end

	flyBV = Instance.new("BodyVelocity")
	flyBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
	flyBV.Velocity = Vector3.zero
	flyBV.Parent = raiz

	flyBG = Instance.new("BodyGyro")
	flyBG.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
	flyBG.P = 9e4
	flyBG.CFrame = raiz.CFrame
	flyBG.Parent = raiz

	hum.PlatformStand = true
end

local function atualizarFly()
	if not estado.fly then
		if flyBV then pararFly() end
		return
	end

	local raiz, hum = pegarPersonagem()
	if not raiz then return end

	-- Sentado: use o VFLY
	if hum.SeatPart then
		if flyBV then pararFly() end
		return
	end

	if not flyBV or flyBV.Parent ~= raiz then
		iniciarFly(raiz, hum)
	end

	local dir, flat = direcaoDeVoo(hum)
	flyBV.Velocity = dir * velocidadeFly
	if flat.Magnitude > 0.001 then
		flyBG.CFrame = CFrame.lookAt(raiz.Position, raiz.Position + flat)
	end
end

botaoFly.MouseButton1Click:Connect(function()
	estado.fly = not estado.fly
	pintarBotao(botaoFly, "FLY", estado.fly)
	atualizarBotaoVertical()
end)

------------------------------------------------------------
-- VFLY (voar com veículo enquanto sentado)
------------------------------------------------------------
local vBV, vBG

local function pararVFly()
	if vBV then vBV:Destroy() vBV = nil end
	if vBG then vBG:Destroy() vBG = nil end
end

local function atualizarVFly()
	if not estado.vfly then
		if vBV then pararVFly() end
		return
	end

	local _, hum = pegarPersonagem()
	local seat = hum and hum.SeatPart
	if not seat then
		pararVFly() -- saiu do veículo
		return
	end

	local raiz = seat.AssemblyRootPart or seat
	if not vBV or vBV.Parent ~= raiz then
		pararVFly()

		vBV = Instance.new("BodyVelocity")
		vBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
		vBV.Velocity = Vector3.zero
		vBV.Parent = raiz

		vBG = Instance.new("BodyGyro")
		vBG.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
		vBG.P = 9e4
		vBG.CFrame = raiz.CFrame
		vBG.Parent = raiz
	end

	local dir, flat = direcaoDeVoo(hum)
	vBV.Velocity = dir * velocidadeVFly

	-- Alinha a frente do assento com a direção da câmera
	if flat.Magnitude > 0.001 then
		local alvoAssento = CFrame.lookAt(seat.Position, seat.Position + flat)
		local deslocamento = seat.CFrame:ToObjectSpace(raiz.CFrame)
		vBG.CFrame = alvoAssento * deslocamento
	end
end

botaoVFly.MouseButton1Click:Connect(function()
	estado.vfly = not estado.vfly
	pintarBotao(botaoVFly, "VFLY", estado.vfly)
	atualizarBotaoVertical()
end)

------------------------------------------------------------
-- SWIM (nadar no ar)
------------------------------------------------------------
local swimBV

local function pararSwim()
	if swimBV then swimBV:Destroy() swimBV = nil end
	local _, hum = pegarPersonagem()
	if hum and hum:GetState() == Enum.HumanoidStateType.Swimming then
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function atualizarSwim()
	-- Fly e VFly têm prioridade sobre o swim
	if not estado.swim or estado.fly then
		if swimBV then pararSwim() end
		return
	end

	local raiz, hum = pegarPersonagem()
	if not raiz then return end

	if hum.SeatPart then
		if swimBV then pararSwim() end
		return
	end

	if not swimBV or swimBV.Parent ~= raiz then
		if swimBV then swimBV:Destroy() end
		swimBV = Instance.new("BodyVelocity")
		swimBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
		swimBV.Velocity = Vector3.zero
		swimBV.Parent = raiz
	end

	-- Mantém o estado de natação (toca a animação de nadar)
	hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
	if hum:GetState() ~= Enum.HumanoidStateType.Swimming then
		hum:ChangeState(Enum.HumanoidStateType.Swimming)
	end

	local dir = direcaoDeVoo(hum)
	swimBV.Velocity = dir * velocidadeSwim
end

botaoSwim.MouseButton1Click:Connect(function()
	estado.swim = not estado.swim
	pintarBotao(botaoSwim, "SWIM", estado.swim)
	atualizarBotaoVertical()
end)

------------------------------------------------------------
-- NOCLIP (atravessar paredes)
------------------------------------------------------------
local colisaoOriginal = {} -- [BasePart] = CanCollide original

local function aplicarNoclip()
	local char = player.Character
	if not char then return end
	for _, parte in ipairs(char:GetDescendants()) do
		if parte:IsA("BasePart") and parte.CanCollide then
			if colisaoOriginal[parte] == nil then
				colisaoOriginal[parte] = true
			end
			parte.CanCollide = false
		end
	end
end

local function restaurarColisao()
	for parte, valor in pairs(colisaoOriginal) do
		if parte and parte.Parent then
			parte.CanCollide = valor
		end
	end
	colisaoOriginal = {}
end

-- Stepped roda antes da física, que é quando a colisão precisa estar desligada
RunService.Stepped:Connect(function()
	if estado.noclip then
		aplicarNoclip()
	end
end)

botaoNoclip.MouseButton1Click:Connect(function()
	estado.noclip = not estado.noclip
	pintarBotao(botaoNoclip, "NOCLIP", estado.noclip)
	if not estado.noclip then
		restaurarColisao()
	end
end)

player.CharacterAdded:Connect(function()
	colisaoOriginal = {}
end)

------------------------------------------------------------
-- SPAWNS (salvar posições, renomear e teleportar)
------------------------------------------------------------
local painelSpawn = Instance.new("Frame")
painelSpawn.Name = "PainelSpawns"
painelSpawn.AnchorPoint = Vector2.new(0, 0.5)
painelSpawn.Position = UDim2.new(0.5, 160, 0.5, 0) -- ao lado do menu principal
painelSpawn.Size = UDim2.new(0, 270, 0, 400)
painelSpawn.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
painelSpawn.Visible = false
painelSpawn.Parent = gui
Instance.new("UICorner", painelSpawn).CornerRadius = UDim.new(0, 14)

local tituloSpawn = Instance.new("TextLabel")
tituloSpawn.Size = UDim2.new(1, 0, 0, 40)
tituloSpawn.BackgroundTransparency = 1
tituloSpawn.Text = "Spawns"
tituloSpawn.TextColor3 = Color3.new(1, 1, 1)
tituloSpawn.Font = Enum.Font.GothamBold
tituloSpawn.TextSize = 20
tituloSpawn.Parent = painelSpawn

local botaoCriarSpawn = Instance.new("TextButton")
botaoCriarSpawn.Position = UDim2.new(0.05, 0, 0, 45)
botaoCriarSpawn.Size = UDim2.new(0.9, 0, 0, 40)
botaoCriarSpawn.BackgroundColor3 = COR_ON
botaoCriarSpawn.Text = "+ Criar spawn aqui"
botaoCriarSpawn.TextColor3 = Color3.new(1, 1, 1)
botaoCriarSpawn.Font = Enum.Font.GothamBold
botaoCriarSpawn.TextSize = 15
botaoCriarSpawn.Parent = painelSpawn
Instance.new("UICorner", botaoCriarSpawn).CornerRadius = UDim.new(0, 10)

local listaSpawn = Instance.new("ScrollingFrame")
listaSpawn.Position = UDim2.new(0.05, 0, 0, 95)
listaSpawn.Size = UDim2.new(0.9, 0, 1, -105)
listaSpawn.BackgroundTransparency = 1
listaSpawn.BorderSizePixel = 0
listaSpawn.ScrollBarThickness = 4
listaSpawn.CanvasSize = UDim2.new(0, 0, 0, 0)
listaSpawn.AutomaticCanvasSize = Enum.AutomaticSize.Y
listaSpawn.Parent = painelSpawn

local layoutSpawn = Instance.new("UIListLayout")
layoutSpawn.Padding = UDim.new(0, 6)
layoutSpawn.SortOrder = Enum.SortOrder.LayoutOrder
layoutSpawn.Parent = listaSpawn

local contadorSpawn = 0

local function criarLinhaSpawn(cframeSalvo)
	contadorSpawn += 1

	local linha = Instance.new("Frame")
	linha.Size = UDim2.new(1, -6, 0, 40)
	linha.BackgroundTransparency = 1
	linha.LayoutOrder = contadorSpawn
	linha.Parent = listaSpawn

	-- Nome editável (clique e digite)
	local nome = Instance.new("TextBox")
	nome.Size = UDim2.new(0.55, 0, 1, 0)
	nome.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
	nome.Text = "Spawn " .. contadorSpawn
	nome.PlaceholderText = "nome"
	nome.TextColor3 = Color3.new(1, 1, 1)
	nome.PlaceholderColor3 = Color3.fromRGB(140, 140, 140)
	nome.Font = Enum.Font.GothamBold
	nome.TextSize = 14
	nome.ClearTextOnFocus = false
	nome.TextTruncate = Enum.TextTruncate.AtEnd
	nome.Parent = linha
	Instance.new("UICorner", nome).CornerRadius = UDim.new(0, 8)

	nome.FocusLost:Connect(function()
		if nome.Text:gsub("%s", "") == "" then
			nome.Text = "Spawn"
		end
	end)

	-- Ir até o spawn
	local ir = Instance.new("TextButton")
	ir.Position = UDim2.new(0.58, 0, 0, 0)
	ir.Size = UDim2.new(0.24, 0, 1, 0)
	ir.BackgroundColor3 = COR_ON
	ir.Text = "IR"
	ir.TextColor3 = Color3.new(1, 1, 1)
	ir.Font = Enum.Font.GothamBold
	ir.TextSize = 14
	ir.Parent = linha
	Instance.new("UICorner", ir).CornerRadius = UDim.new(0, 8)

	ir.MouseButton1Click:Connect(function()
		local raiz = pegarPersonagem()
		if raiz then
			raiz.AssemblyLinearVelocity = Vector3.zero
			raiz.CFrame = cframeSalvo + Vector3.new(0, 3, 0)
		end
	end)

	-- Apagar o spawn
	local apagar = Instance.new("TextButton")
	apagar.Position = UDim2.new(0.85, 0, 0, 0)
	apagar.Size = UDim2.new(0.15, 0, 1, 0)
	apagar.BackgroundColor3 = COR_OFF
	apagar.Text = "X"
	apagar.TextColor3 = Color3.new(1, 1, 1)
	apagar.Font = Enum.Font.GothamBold
	apagar.TextSize = 14
	apagar.Parent = linha
	Instance.new("UICorner", apagar).CornerRadius = UDim.new(0, 8)

	apagar.MouseButton1Click:Connect(function()
		linha:Destroy()
	end)
end

botaoCriarSpawn.MouseButton1Click:Connect(function()
	local raiz = pegarPersonagem()
	if raiz then
		criarLinhaSpawn(raiz.CFrame)
	end
end)

botaoSpawns.MouseButton1Click:Connect(function()
	painelSpawn.Visible = not painelSpawn.Visible
end)

------------------------------------------------------------
-- TP (teleportar até jogadores)
------------------------------------------------------------
local painelTP = Instance.new("Frame")
painelTP.Name = "PainelTP"
painelTP.AnchorPoint = Vector2.new(1, 0.5)
painelTP.Position = UDim2.new(0.5, -160, 0.5, 0) -- à esquerda do menu principal
painelTP.Size = UDim2.new(0, 270, 0, 400)
painelTP.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
painelTP.Visible = false
painelTP.Parent = gui
Instance.new("UICorner", painelTP).CornerRadius = UDim.new(0, 14)

local tituloTP = Instance.new("TextLabel")
tituloTP.Size = UDim2.new(1, 0, 0, 40)
tituloTP.BackgroundTransparency = 1
tituloTP.Text = "Teleportar para..."
tituloTP.TextColor3 = Color3.new(1, 1, 1)
tituloTP.Font = Enum.Font.GothamBold
tituloTP.TextSize = 20
tituloTP.Parent = painelTP

local listaTP = Instance.new("ScrollingFrame")
listaTP.Position = UDim2.new(0.05, 0, 0, 50)
listaTP.Size = UDim2.new(0.9, 0, 1, -60)
listaTP.BackgroundTransparency = 1
listaTP.BorderSizePixel = 0
listaTP.ScrollBarThickness = 4
listaTP.CanvasSize = UDim2.new(0, 0, 0, 0)
listaTP.AutomaticCanvasSize = Enum.AutomaticSize.Y
listaTP.Parent = painelTP

local layoutTP = Instance.new("UIListLayout")
layoutTP.Padding = UDim.new(0, 6)
layoutTP.SortOrder = Enum.SortOrder.Name
layoutTP.Parent = listaTP

local botoesTP = {} -- [Player] = TextButton

local function removerBotaoTP(p)
	local b = botoesTP[p]
	if b then
		b:Destroy()
		botoesTP[p] = nil
	end
end

local function criarBotaoTP(p)
	if p == player or botoesTP[p] then return end

	local b = Instance.new("TextButton")
	b.Name = p.DisplayName:lower() .. p.UserId
	b.Size = UDim2.new(1, -6, 0, 40)
	b.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
	b.Text = string.format("%s (@%s)", p.DisplayName, p.Name)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.Parent = listaTP
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)

	b.MouseButton1Click:Connect(function()
		local minhaRaiz = pegarPersonagem()
		local char = p.Character
		local alvo = char and char:FindFirstChild("HumanoidRootPart")
		if minhaRaiz and alvo then
			minhaRaiz.AssemblyLinearVelocity = Vector3.zero
			minhaRaiz.CFrame = alvo.CFrame + Vector3.new(0, 3, 0)
		else
			local textoAntigo = b.Text
			b.Text = "Jogador indisponível"
			task.wait(1.5)
			if b.Parent then b.Text = textoAntigo end
		end
	end)

	botoesTP[p] = b
end

for _, p in ipairs(Players:GetPlayers()) do
	criarBotaoTP(p)
end
Players.PlayerAdded:Connect(criarBotaoTP)
Players.PlayerRemoving:Connect(removerBotaoTP)

botaoTP.MouseButton1Click:Connect(function()
	painelTP.Visible = not painelTP.Visible
end)

------------------------------------------------------------
-- XRAY (mapa semitransparente, só no seu cliente)
------------------------------------------------------------
local transparenciaXray = 0.6
local xrayPartes = {}   -- [BasePart] = true
local xrayConexao = nil
local xrayVersao = 0    -- cancela varreduras antigas ao desligar

local function ehParteDePersonagem(parte)
	local modelo = parte:FindFirstAncestorOfClass("Model")
	while modelo do
		if modelo:FindFirstChildOfClass("Humanoid") then
			return true
		end
		modelo = modelo.Parent and modelo.Parent:FindFirstAncestorOfClass("Model")
	end
	return false
end

local function aplicarXray(obj)
	if obj:IsA("BasePart") and not xrayPartes[obj] and obj.Transparency < 1 and not ehParteDePersonagem(obj) then
		xrayPartes[obj] = true
		obj.LocalTransparencyModifier = transparenciaXray
	end
end

local function ligarXray()
	xrayVersao += 1
	local minhaVersao = xrayVersao

	xrayConexao = workspace.DescendantAdded:Connect(aplicarXray)

	task.spawn(function()
		local n = 0
		for _, obj in ipairs(workspace:GetDescendants()) do
			if minhaVersao ~= xrayVersao or not estado.xray then return end
			aplicarXray(obj)
			n += 1
			if n % 300 == 0 then
				task.wait() -- evita travar em mapas grandes
			end
		end
	end)
end

local function desligarXray()
	xrayVersao += 1
	if xrayConexao then
		xrayConexao:Disconnect()
		xrayConexao = nil
	end
	for parte in pairs(xrayPartes) do
		if parte.Parent then
			parte.LocalTransparencyModifier = 0
		end
	end
	xrayPartes = {}
end

botaoXray.MouseButton1Click:Connect(function()
	estado.xray = not estado.xray
	pintarBotao(botaoXray, "XRAY", estado.xray)
	if estado.xray then
		ligarXray()
	else
		desligarXray()
	end
end)

caixaXray.FocusLost:Connect(function()
	local n = tonumber(caixaXray.Text)
	if n then
		transparenciaXray = math.clamp(n, 0, 0.95)
	end
	caixaXray.Text = tostring(transparenciaXray)
	if estado.xray then
		for parte in pairs(xrayPartes) do
			if parte.Parent then
				parte.LocalTransparencyModifier = transparenciaXray
			end
		end
	end
end)

------------------------------------------------------------
-- TPTOOL (item que teleporta para onde você clicar)
------------------------------------------------------------
local tpTool = nil

local function removerTPTool()
	if tpTool then
		tpTool:Destroy()
		tpTool = nil
	end
end

local function criarTPTool()
	removerTPTool()

	local ferramenta = Instance.new("Tool")
	ferramenta.Name = "TPTool"
	ferramenta.ToolTip = "Clique para teleportar"
	ferramenta.RequiresHandle = false
	ferramenta.CanBeDropped = false

	ferramenta.Activated:Connect(function()
		local raiz = pegarPersonagem()
		if not raiz then return end

		local mouse = player:GetMouse()
		mouse.TargetFilter = player.Character -- ignora o próprio personagem
		local alvo = mouse.Hit
		if alvo then
			raiz.AssemblyLinearVelocity = Vector3.zero
			raiz.CFrame = CFrame.new(alvo.Position + Vector3.new(0, 3, 0)) * raiz.CFrame.Rotation
		end
	end)

	ferramenta.Parent = player:WaitForChild("Backpack")
	tpTool = ferramenta
end

botaoTPTool.MouseButton1Click:Connect(function()
	estado.tptool = not estado.tptool
	pintarBotao(botaoTPTool, "TPTOOL", estado.tptool)
	if estado.tptool then
		criarTPTool()
	else
		removerTPTool()
	end
end)

-- Depois de morrer, entrega o item de novo
player.CharacterAdded:Connect(function()
	if estado.tptool then
		task.wait(0.5)
		criarTPTool()
	end
end)

------------------------------------------------------------
-- REJOIN (reentrar no server)
------------------------------------------------------------
local reentrando = false

botaoRejoin.MouseButton1Click:Connect(function()
	if reentrando then return end
	reentrando = true
	botaoRejoin.Text = "Reentrando..."

	local ok, erro = pcall(function()
		if #Players:GetPlayers() <= 1 then
			-- Sozinho no server: ele fecharia ao sair, então entra em um novo
			TeleportService:Teleport(game.PlaceId, player)
		else
			-- Volta para o mesmo server
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
		end
	end)

	if not ok then
		warn("Rejoin falhou: " .. tostring(erro))
		botaoRejoin.Text = "Falhou (só funciona no jogo publicado)"
		task.wait(2)
		botaoRejoin.Text = "REJOIN (reentrar no server)"
		reentrando = false
	end
end)

-- Se o teleporte falhar depois de iniciado, libera o botão de novo
TeleportService.TeleportInitFailed:Connect(function()
	botaoRejoin.Text = "REJOIN (reentrar no server)"
	reentrando = false
end)

------------------------------------------------------------
-- LOOP PRINCIPAL
------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	atualizarESP()
	atualizarFly()
	atualizarVFly()
	atualizarSwim()
end)

-- Ao morrer/respawnar, desliga os voos
player.CharacterAdded:Connect(function()
	estado.fly = false
	estado.vfly = false
	estado.swim = false
	pararFly()
	pararVFly()
	pararSwim()
	pintarBotao(botaoSwim, "SWIM", false)
	pintarBotao(botaoFly, "FLY", false)
	pintarBotao(botaoVFly, "VFLY", false)
	atualizarBotaoVertical()
end)
