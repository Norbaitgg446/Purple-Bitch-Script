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
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

------------------------------------------------------------
-- ARRASTAR / REDIMENSIONAR (mouse e toque)
------------------------------------------------------------
local LIMITE_ARRASTO = 6 -- pixels que precisa andar para contar como arrasto (menos que isso é clique)
local TAMANHO_MINIMO = Vector2.new(220, 140) -- menor tamanho possível do painel

local function tamanhoTela()
	local t = gui.AbsoluteSize
	if t.X > 0 and t.Y > 0 then
		return t
	end
	return workspace.CurrentCamera.ViewportSize
end

-- Acompanha um dedo/mouse que começou em "alca" e chama aoMover(delta) enquanto ele anda
local function ligarArrasto(alca, aoIniciar, aoMover, aoSoltar)
	local atual, inicio, moveu = nil, nil, false

	alca.InputBegan:Connect(function(input)
		local tipo = input.UserInputType
		if atual or (tipo ~= Enum.UserInputType.MouseButton1 and tipo ~= Enum.UserInputType.Touch) then
			return
		end
		atual = input
		inicio = Vector2.new(input.Position.X, input.Position.Y)
		moveu = false
		if aoIniciar then aoIniciar() end

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End and atual == input then
				atual = nil
				if aoSoltar then aoSoltar(moveu) end
			end
		end)
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not atual then return end
		local mesmoDedo = input == atual
		local mouse = atual.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseMovement
		if not (mesmoDedo or mouse) then return end

		local delta = Vector2.new(input.Position.X, input.Position.Y) - inicio
		if not moveu and delta.Magnitude < LIMITE_ARRASTO then return end
		moveu = true
		aoMover(delta)
	end)
end

-- Move "alvo" quando "alca" é arrastado (toque rápido sem mover chama aoClicar)
local function tornarMovel(alca, alvo, aoClicar)
	local origem
	ligarArrasto(alca,
		function() origem = alvo.AbsolutePosition end,
		function(delta)
			local tela, tam, a = tamanhoTela(), alvo.AbsoluteSize, alvo.AnchorPoint
			local x = math.clamp(origem.X + delta.X, 0, math.max(0, tela.X - tam.X))
			local y = math.clamp(origem.Y + delta.Y, 0, math.max(0, tela.Y - tam.Y))
			alvo.Position = UDim2.fromOffset(x + a.X * tam.X, y + a.Y * tam.Y)
		end,
		function(moveu)
			if not moveu and aoClicar then aoClicar() end
		end
	)
end

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
botao.ZIndex = 10 -- fica na frente do painel
botao.Parent = gui
Instance.new("UICorner", botao).CornerRadius = UDim.new(0, 12)

-- Painel do menu (o tamanho inicial se ajusta à tela; depois você redimensiona)
local telaInicial = tamanhoTela()
local larguraInicial = math.max(TAMANHO_MINIMO.X, math.min(640, telaInicial.X - 20))
local alturaInicial = larguraInicial * 9 / 16 -- formato 16:9 (como um vídeo)
local alturaMaxima = math.max(TAMANHO_MINIMO.Y, telaInicial.Y - 120)
if alturaInicial > alturaMaxima then -- tela baixa: diminui mantendo 16:9
	alturaInicial = alturaMaxima
	larguraInicial = math.max(TAMANHO_MINIMO.X, alturaInicial * 16 / 9)
end
local tamanhoPainel = UDim2.fromOffset(larguraInicial, alturaInicial)

local painel = Instance.new("Frame")
painel.Name = "Painel"
painel.AnchorPoint = Vector2.new(0, 0)
painel.Position = UDim2.fromOffset((telaInicial.X - larguraInicial) / 2, math.max(20, (telaInicial.Y - alturaInicial) / 2))
painel.Size = UDim2.new(0, 0, 0, 0)
painel.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
painel.Visible = false
painel.ClipsDescendants = true
painel.Parent = gui
Instance.new("UICorner", painel).CornerRadius = UDim.new(0, 14)

-- FOTO DE FUNDO DO PAINEL
do
	-- >>> COLE AQUI O LINK DIRETO DA FOTO (termina em .png ou .jpg) <<<
	local LINK_FOTO = "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcR9Iiv00phL--lhkgtq-jLsfL_zsUNZ7VCn4ztV62_rgi1_grgpy-1ZSTPW&s=10"
	local TRANSPARENCIA_FOTO = 0.4 -- 0 = foto forte, 1 = invisível
	local NOME_ARQUIVO_FOTO = "foto_fundo.png" -- arquivo criado pelo script na pasta workspace
	local ID_FOTO_FUNDO = "rbxassetid://0" -- plano B (opcional): ID do Roblox

	local fundo = Instance.new("ImageLabel")
	fundo.Name = "FotoFundo"
	fundo.Size = UDim2.new(1, 0, 1, 0)
	fundo.BackgroundTransparency = 1
	fundo.ScaleType = Enum.ScaleType.Crop -- preenche sem esticar
	fundo.ImageTransparency = TRANSPARENCIA_FOTO
	fundo.ZIndex = 0 -- fica atrás de tudo
	fundo.Image = ID_FOTO_FUNDO

	-- Baixa a foto (só na primeira vez) e usa o arquivo; se algo falhar, usa o ID
	local ok, imagem = pcall(function()
		if LINK_FOTO ~= "" and not (isfile and isfile(NOME_ARQUIVO_FOTO)) then
			writefile(NOME_ARQUIVO_FOTO, game:HttpGet(LINK_FOTO))
		end
		if getcustomasset and isfile and isfile(NOME_ARQUIVO_FOTO) then
			return getcustomasset(NOME_ARQUIVO_FOTO)
		end
	end)
	if ok and imagem then
		fundo.Image = imagem
	end

	fundo.Parent = painel
	Instance.new("UICorner", fundo).CornerRadius = UDim.new(0, 14)
end

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, 0, 0, 40)
titulo.BackgroundTransparency = 1
titulo.Text = "Menu de Teste"
titulo.TextColor3 = Color3.new(1, 1, 1)
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 20
titulo.Active = true
titulo.Parent = painel

-- Área rolável: os botões ficam aqui dentro, então dá para diminuir o painel sem cortar nada
local conteudo = Instance.new("ScrollingFrame")
conteudo.Name = "Conteudo"
conteudo.Position = UDim2.new(0, 0, 0, 40)
conteudo.Size = UDim2.new(1, 0, 1, -40)
conteudo.BackgroundTransparency = 1
conteudo.BorderSizePixel = 0
conteudo.ScrollBarThickness = 4
conteudo.ScrollingDirection = Enum.ScrollingDirection.Y
conteudo.CanvasSize = UDim2.new()
conteudo.AutomaticCanvasSize = Enum.AutomaticSize.Y
conteudo.Parent = painel

-- Alça no canto inferior direito para redimensionar
local alcaResize = Instance.new("TextButton")
alcaResize.Name = "AlcaRedimensionar"
alcaResize.AnchorPoint = Vector2.new(1, 1)
alcaResize.Position = UDim2.new(1, 0, 1, 0)
alcaResize.Size = UDim2.new(0, 32, 0, 32)
alcaResize.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
alcaResize.BackgroundTransparency = 0.3
alcaResize.Text = "◢"
alcaResize.TextColor3 = Color3.new(1, 1, 1)
alcaResize.Font = Enum.Font.GothamBold
alcaResize.TextSize = 18
alcaResize.AutoButtonColor = false
alcaResize.ZIndex = 5
alcaResize.Parent = painel
Instance.new("UICorner", alcaResize).CornerRadius = UDim.new(0, 10)

-- Arrastar o título move o painel
tornarMovel(titulo, painel)

-- Arrastar a alça muda o tamanho do painel
local tamanhoAoIniciar
ligarArrasto(alcaResize,
	function() tamanhoAoIniciar = painel.AbsoluteSize end,
	function(delta)
		local tela, pos = tamanhoTela(), painel.AbsolutePosition
		local w = math.clamp(tamanhoAoIniciar.X + delta.X, TAMANHO_MINIMO.X, math.max(TAMANHO_MINIMO.X, tela.X - pos.X))
		local h = math.clamp(tamanhoAoIniciar.Y + delta.Y, TAMANHO_MINIMO.Y, math.max(TAMANHO_MINIMO.Y, tela.Y - pos.Y))
		tamanhoPainel = UDim2.fromOffset(w, h)
		painel.Size = tamanhoPainel
	end
)

local COR_OFF = Color3.fromRGB(170, 50, 50)
local COR_ON = Color3.fromRGB(50, 170, 80)

-- Grade de botões em 3 colunas (menu deitado). O "y" antigo (50, 100, ...) vira a posição na grade.
local COLUNAS = 3
local LARG_CEL = (1 - 0.04 - (COLUNAS - 1) * 0.02) / COLUNAS
local function celula(y)
	local i = (y - 50) / 50
	return 0.02 + (i % COLUNAS) * (LARG_CEL + 0.02), 8 + math.floor(i / COLUNAS) * 50
end

-- Cria uma célula do menu: botão liga/desliga (+ caixa de velocidade opcional)
local function criarLinha(y, nome, comVelocidade, velocidadePadrao)
	local cx, cy = celula(y)
	local b = Instance.new("TextButton")
	b.Name = "Botao" .. nome
	b.Position = UDim2.new(cx, 0, 0, cy)
	b.Size = comVelocidade and UDim2.new(LARG_CEL * 0.62, 0, 0, 40) or UDim2.new(LARG_CEL, 0, 0, 40)
	b.BackgroundColor3 = COR_OFF
	b.Text = nome .. ": DESLIGADO"
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextScaled = true -- o texto encolhe se não couber
	local limite = Instance.new("UITextSizeConstraint")
	limite.MaxTextSize = 15
	limite.MinTextSize = 8
	limite.Parent = b
	b.Parent = conteudo
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)

	local caixa = nil
	if comVelocidade then
		caixa = Instance.new("TextBox")
		caixa.Name = "Velocidade" .. nome
		caixa.Position = UDim2.new(cx + LARG_CEL * 0.66, 0, 0, cy)
		caixa.Size = UDim2.new(LARG_CEL * 0.34, 0, 0, 40)
		caixa.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
		caixa.Text = tostring(velocidadePadrao)
		caixa.PlaceholderText = "vel."
		caixa.TextColor3 = Color3.new(1, 1, 1)
		caixa.PlaceholderColor3 = Color3.fromRGB(140, 140, 140)
		caixa.Font = Enum.Font.GothamBold
		caixa.TextSize = 15
		caixa.ClearTextOnFocus = false
		caixa.Parent = conteudo
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
local botaoTeclado = criarLinha(600, "TECLADO", false)

local dica = Instance.new("TextLabel")
dica.Position = UDim2.new(0.02, 0, 0, 216)
dica.Size = UDim2.new(0.96, 0, 0, 0)
dica.AutomaticSize = Enum.AutomaticSize.Y
dica.BackgroundTransparency = 1
dica.TextWrapped = true
dica.TextYAlignment = Enum.TextYAlignment.Top
dica.Text = "Mover: arraste o título do painel ou o botão MENU. Tamanho: arraste o ◢ do canto.\nFly: WASD/analógico para mover, mire a câmera para subir/descer.\nEspaço/E = subir, Shift/Q = descer.\nVFLY: use sentado em um veículo.\nNOCLIP: atravessa paredes (sem o Fly você cai pelo chão).\nSWIM: nada no ar como se estivesse na água.\nSPAWNS: salve posições, renomeie e volte a elas.\nTP: clique no nome de um jogador para ir até ele.\nXRAY: deixa o mapa transparente (caixa: 0 = normal, 0.95 = quase invisível).\nTPTOOL: dá um item no inventário; equipe e clique/toque onde quer ir.\nTECLADO: mostra o botão >_ no canto da tela; toque nele e digite comandos (ex.: fly 80, unfly, np, xray, rj). Digite cmds para ver todos."
dica.TextColor3 = Color3.fromRGB(170, 170, 180)
dica.Font = Enum.Font.Gotham
dica.TextSize = 12
dica.Parent = conteudo

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
	b.ZIndex = 9
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

local function alternarPainel()
	aberto = not aberto
	if aberto then
		painel.Visible = true
		TweenService:Create(painel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = tamanhoPainel,
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
end

-- Toque rápido no botão abre/fecha; arrastar move o botão
tornarMovel(botao, botao, alternarPainel)

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

local function definirESP(v)
	estado.esp = v
	pintarBotao(botaoESP, "ESP", v)
	atualizarTodos()
end

local function definirChams(v)
	estado.chams = v
	pintarBotao(botaoChams, "CHAMS", v)
	atualizarTodos()
end

botaoESP.MouseButton1Click:Connect(function() definirESP(not estado.esp) end)
botaoChams.MouseButton1Click:Connect(function() definirChams(not estado.chams) end)

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

local function definirFly(v)
	estado.fly = v
	pintarBotao(botaoFly, "FLY", v)
	atualizarBotaoVertical()
end
botaoFly.MouseButton1Click:Connect(function() definirFly(not estado.fly) end)

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

local function definirVFly(v)
	estado.vfly = v
	pintarBotao(botaoVFly, "VFLY", v)
	atualizarBotaoVertical()
end
botaoVFly.MouseButton1Click:Connect(function() definirVFly(not estado.vfly) end)

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

local function definirSwim(v)
	estado.swim = v
	pintarBotao(botaoSwim, "SWIM", v)
	atualizarBotaoVertical()
end
botaoSwim.MouseButton1Click:Connect(function() definirSwim(not estado.swim) end)

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

local function definirNoclip(v)
	estado.noclip = v
	pintarBotao(botaoNoclip, "NOCLIP", v)
	if not v then
		restaurarColisao()
	end
end
botaoNoclip.MouseButton1Click:Connect(function() definirNoclip(not estado.noclip) end)

player.CharacterAdded:Connect(function()
	colisaoOriginal = {}
end)

------------------------------------------------------------
-- SPAWNS (salvar posições, renomear e teleportar)
------------------------------------------------------------
-- Abre um painel lateral colado ao menu (à direita; se não couber, à esquerda)
local function posicionarAoLado(f)
	local tela = tamanhoTela()
	local pos = painel.AbsolutePosition
	local larguraMenu = tamanhoPainel.X.Offset
	local w, h = f.Size.X.Offset, f.Size.Y.Offset
	local x
	if pos.X + larguraMenu + 10 + w <= tela.X then
		x = pos.X + larguraMenu + 10
	elseif pos.X - 10 - w >= 0 then
		x = pos.X - 10 - w
	else
		x = math.clamp(pos.X + 20, 0, math.max(0, tela.X - w)) -- sem espaço: fica por cima
	end
	local y = math.clamp(pos.Y, 0, math.max(0, tela.Y - h))
	f.AnchorPoint = Vector2.new(0, 0)
	f.Position = UDim2.fromOffset(x, y)
end

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
tituloSpawn.Active = true
tituloSpawn.Parent = painelSpawn
tornarMovel(tituloSpawn, painelSpawn)

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

local spawnsSalvos = {} -- [Frame da linha] = { nome = TextBox, cf = CFrame }
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

	spawnsSalvos[linha] = { nome = nome, cf = cframeSalvo }

	apagar.MouseButton1Click:Connect(function()
		spawnsSalvos[linha] = nil
		linha:Destroy()
	end)

	return nome
end

botaoCriarSpawn.MouseButton1Click:Connect(function()
	local raiz = pegarPersonagem()
	if raiz then
		criarLinhaSpawn(raiz.CFrame)
	end
end)

botaoSpawns.MouseButton1Click:Connect(function()
	painelSpawn.Visible = not painelSpawn.Visible
	if painelSpawn.Visible then posicionarAoLado(painelSpawn) end
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
tituloTP.Active = true
tituloTP.Parent = painelTP
tornarMovel(tituloTP, painelTP)

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
	if painelTP.Visible then posicionarAoLado(painelTP) end
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

local function definirXray(v)
	if v == estado.xray then return end
	estado.xray = v
	pintarBotao(botaoXray, "XRAY", v)
	if v then
		ligarXray()
	else
		desligarXray()
	end
end
botaoXray.MouseButton1Click:Connect(function() definirXray(not estado.xray) end)

local function aplicarCaixaXray()
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
end
caixaXray.FocusLost:Connect(aplicarCaixaXray)

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

local function definirTPTool(v)
	if v == estado.tptool then return end
	estado.tptool = v
	pintarBotao(botaoTPTool, "TPTOOL", v)
	if v then
		criarTPTool()
	else
		removerTPTool()
	end
end
botaoTPTool.MouseButton1Click:Connect(function() definirTPTool(not estado.tptool) end)

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

local function fazerRejoin()
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
end
botaoRejoin.MouseButton1Click:Connect(fazerRejoin)

-- Se o teleporte falhar depois de iniciado, libera o botão de novo
TeleportService.TeleportInitFailed:Connect(function()
	botaoRejoin.Text = "REJOIN (reentrar no server)"
	reentrando = false
end)

------------------------------------------------------------
-- TECLADO (barra de comandos digitados)
------------------------------------------------------------
do
	local toque = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local tecladoLigado = false
	local barraAberta = false
	local listaAjuda = {}
	local comandos = {} -- [palavra] = function(args) -> sucesso, mensagem
	local LARGURA_ABERTA = 282

	local function novo(classe, props, pai)
		local o = Instance.new(classe)
		for k, v in pairs(props) do o[k] = v end
		o.Parent = pai
		return o
	end

	----------------------------------------------------------
	-- Interface: ícone ">_" (arrastável) que abre a barra
	----------------------------------------------------------
	local cmdFrame = novo("Frame", {
		Name = "BarraComandos",
		AnchorPoint = Vector2.new(1, 1),
		Position = toque and UDim2.new(1, -16, 1, -190) or UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(40, 40),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
	}, gui)

	local icone = novo("TextButton", {
		Name = "Icone",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Color3.fromRGB(40, 40, 45),
		BackgroundTransparency = 0.15,
		Text = ">_",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
	}, cmdFrame)
	novo("UICorner", { CornerRadius = UDim.new(0, 10) }, icone)

	local caixaCmd = novo("TextBox", {
		Name = "Comando",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -92, 0, 0),
		Size = UDim2.fromOffset(190, 40),
		BackgroundColor3 = Color3.fromRGB(25, 25, 30),
		Text = "",
		PlaceholderText = "comando (cmds = lista)",
		PlaceholderColor3 = Color3.fromRGB(140, 140, 140),
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Visible = false,
	}, cmdFrame)
	novo("UICorner", { CornerRadius = UDim.new(0, 10) }, caixaCmd)
	novo("UIPadding", { PaddingLeft = UDim.new(0, 10) }, caixaCmd)

	local botaoEnviar = novo("TextButton", {
		Name = "Enviar",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -46, 0, 0),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = COR_ON,
		Text = "OK",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		Visible = false,
	}, cmdFrame)
	novo("UICorner", { CornerRadius = UDim.new(0, 10) }, botaoEnviar)

	-- Aviso curto com o resultado do comando
	local toast = novo("TextLabel", {
		Name = "Aviso",
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Color3.fromRGB(25, 25, 30),
		BackgroundTransparency = 0.1,
		TextWrapped = true,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Visible = false,
	}, cmdFrame)
	novo("UICorner", { CornerRadius = UDim.new(0, 8) }, toast)
	novo("UIPadding", {
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
	}, toast)
	novo("UISizeConstraint", { MaxSize = Vector2.new(280, 200) }, toast)

	-- Lista de comandos
	local ajuda = novo("Frame", {
		Name = "Ajuda",
		Size = UDim2.fromOffset(290, 230),
		BackgroundColor3 = Color3.fromRGB(25, 25, 30),
		Visible = false,
	}, cmdFrame)
	novo("UICorner", { CornerRadius = UDim.new(0, 12) }, ajuda)
	novo("TextLabel", {
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -56, 0, 30),
		BackgroundTransparency = 1,
		Text = "Comandos",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, ajuda)
	local fecharAjuda = novo("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 5),
		Size = UDim2.fromOffset(32, 28),
		BackgroundColor3 = COR_OFF,
		Text = "X",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
	}, ajuda)
	novo("UICorner", { CornerRadius = UDim.new(0, 8) }, fecharAjuda)
	local rolagem = novo("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 38),
		Size = UDim2.new(1, -20, 1, -46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, ajuda)
	local textoAjuda = novo("TextLabel", {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(200, 200, 210),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		Text = "",
	}, rolagem)

	-- Coloca avisos/lista em cima da barra (ou embaixo, se ela estiver no topo da tela)
	local function posicionarAcima(obj)
		if cmdFrame.AbsolutePosition.Y < 90 then
			obj.AnchorPoint = Vector2.new(1, 0)
			obj.Position = UDim2.new(1, 0, 1, 6)
		else
			obj.AnchorPoint = Vector2.new(1, 1)
			obj.Position = UDim2.new(1, 0, 0, -6)
		end
	end

	local toastVersao = 0
	local function mostrarToast(texto, ok)
		toastVersao += 1
		local minha = toastVersao
		posicionarAcima(toast)
		toast.Text = texto
		toast.TextColor3 = ok and Color3.fromRGB(150, 255, 170) or Color3.fromRGB(255, 150, 150)
		toast.Visible = true
		task.delay(ok and 2.5 or 4, function()
			if toastVersao == minha then toast.Visible = false end
		end)
	end

	local function abrirAjuda()
		textoAjuda.Text = "Vários de uma vez: fly 80; np\nPara desligar, coloque 'un' na frente (unfly, unnp...)\n\n"
			.. table.concat(listaAjuda, "\n")
		posicionarAcima(ajuda)
		toast.Visible = false
		ajuda.Visible = true
	end
	fecharAjuda.Activated:Connect(function() ajuda.Visible = false end)

	local function fecharBarra()
		barraAberta = false
		caixaCmd:ReleaseFocus()
		caixaCmd.Visible = false
		botaoEnviar.Visible = false
		cmdFrame.Size = UDim2.fromOffset(40, 40)
	end

	local function abrirBarra()
		barraAberta = true
		-- se o ícone estiver perto da borda esquerda, empurra a barra para dentro da tela
		local direita = cmdFrame.AbsolutePosition.X + cmdFrame.AbsoluteSize.X
		local falta = LARGURA_ABERTA - direita
		if falta > 0 then
			local p = cmdFrame.Position
			cmdFrame.Position = UDim2.new(p.X.Scale, p.X.Offset + falta, p.Y.Scale, p.Y.Offset)
		end
		cmdFrame.Size = UDim2.fromOffset(LARGURA_ABERTA, 40)
		caixaCmd.Visible = true
		botaoEnviar.Visible = true
		task.defer(function() caixaCmd:CaptureFocus() end)
	end

	-- Toque rápido no ícone abre/fecha a barra; arrastar move o ícone
	tornarMovel(icone, cmdFrame, function()
		if barraAberta then fecharBarra() else abrirBarra() end
	end)

	----------------------------------------------------------
	-- Comandos
	----------------------------------------------------------
	-- Comando simples
	local function comando(nomes, descricao, f)
		for _, n in ipairs(nomes) do comandos[n] = f end
		listaAjuda[#listaAjuda + 1] = descricao
	end

	-- Comando liga/desliga: "nome" liga e "unnome" desliga
	local function alternavel(nomes, descricao, f)
		for _, n in ipairs(nomes) do
			comandos[n] = function(args) return f(true, args) end
			comandos["un" .. n] = function(args) return f(false, args) end
		end
		listaAjuda[#listaAjuda + 1] = descricao
	end

	-- Se vier um número, usa como velocidade (passa pela mesma regra 1-500 da caixa do menu)
	local function velocidadeDoComando(args, caixa, obter, guardar)
		if args[1] then
			local n = tonumber(args[1])
			if not n then return false end
			caixa.Text = tostring(n)
			guardar(lerVelocidade(caixa, obter()))
		end
		return true
	end

	local function comandoDeVoo(nomes, descricao, titulo, caixa, definir, obter, guardar)
		alternavel(nomes, descricao, function(ligar, args)
			if ligar and not velocidadeDoComando(args, caixa, obter, guardar) then
				return false, "Velocidade inválida: " .. tostring(args[1])
			end
			definir(ligar)
			return true, titulo .. (ligar and (" ligado (" .. obter() .. ")") or " desligado")
		end)
	end

	comandoDeVoo({ "fly" }, "fly [vel] / unfly - voar (vel. 1 a 500)", "Fly", caixaFly, definirFly,
		function() return velocidadeFly end, function(v) velocidadeFly = v end)
	comandoDeVoo({ "vfly", "vf" }, "vfly [vel] / unvfly - voar sentado em veículo", "VFly", caixaVFly, definirVFly,
		function() return velocidadeVFly end, function(v) velocidadeVFly = v end)
	comandoDeVoo({ "swim", "sw" }, "swim [vel] / unswim - nadar no ar", "Swim", caixaSwim, definirSwim,
		function() return velocidadeSwim end, function(v) velocidadeSwim = v end)

	alternavel({ "np", "cp", "nc", "noclip" }, "np / unnp - atravessar paredes (noclip)", function(ligar)
		definirNoclip(ligar)
		return true, "Noclip " .. (ligar and "ligado" or "desligado")
	end)

	alternavel({ "xray", "exy", "xr" }, "xray [0 a 0.95] / unxray (ou exy) - mapa transparente", function(ligar, args)
		if ligar and args[1] then
			local n = tonumber(args[1])
			if not n then return false, "Valor inválido: " .. args[1] end
			caixaXray.Text = tostring(n)
			aplicarCaixaXray()
		end
		definirXray(ligar)
		return true, "Xray " .. (ligar and ("ligado (" .. transparenciaXray .. ")") or "desligado")
	end)

	alternavel({ "esp" }, "esp / unesp - nome e distância dos jogadores", function(ligar)
		definirESP(ligar)
		return true, "ESP " .. (ligar and "ligado" or "desligado")
	end)

	alternavel({ "chams", "ch" }, "chams / unchams - contorno nos jogadores", function(ligar)
		definirChams(ligar)
		return true, "Chams " .. (ligar and "ligado" or "desligado")
	end)

	alternavel({ "tptool", "tpt" }, "tptool / untptool - item que teleporta onde você clica", function(ligar)
		definirTPTool(ligar)
		return true, "TPTool " .. (ligar and "no inventário" or "removido")
	end)

	-- Procura jogador: nome exato, começo do nome, ou parte do nome
	local function acharJogador(busca)
		busca = busca:lower()
		local regras = {
			function(p) return p.Name:lower() == busca or p.DisplayName:lower() == busca end,
			function(p) return p.Name:lower():sub(1, #busca) == busca or p.DisplayName:lower():sub(1, #busca) == busca end,
			function(p) return p.Name:lower():find(busca, 1, true) or p.DisplayName:lower():find(busca, 1, true) end,
		}
		for _, regra in ipairs(regras) do
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and regra(p) then return p end
			end
		end
	end

	comando({ "tp" }, "tp <jogador> - ir até um jogador (nome parcial)", function(args)
		if #args == 0 then return false, "Uso: tp <jogador>" end
		local alvoJogador = acharJogador(table.concat(args, " "))
		if not alvoJogador then return false, "Jogador não encontrado: " .. table.concat(args, " ") end
		local alvo = alvoJogador.Character and alvoJogador.Character:FindFirstChild("HumanoidRootPart")
		local minha = pegarPersonagem()
		if not (alvo and minha) then return false, alvoJogador.DisplayName .. " indisponível" end
		minha.AssemblyLinearVelocity = Vector3.zero
		minha.CFrame = alvo.CFrame + Vector3.new(0, 3, 0)
		return true, "TP -> " .. alvoJogador.DisplayName
	end)

	comando({ "sp", "setspawn" }, "sp [nome] - salvar spawn aqui", function(args)
		local raiz = pegarPersonagem()
		if not raiz then return false, "Personagem indisponível" end
		local caixaNome = criarLinhaSpawn(raiz.CFrame)
		if #args > 0 then caixaNome.Text = table.concat(args, " ") end
		return true, "Spawn salvo: " .. caixaNome.Text
	end)

	comando({ "go" }, "go [nome ou nº] - ir a um spawn (sem nome = lista)", function(args)
		local lista = {}
		for linha, dados in pairs(spawnsSalvos) do
			lista[#lista + 1] = { ordem = linha.LayoutOrder, dados = dados }
		end
		table.sort(lista, function(a, b) return a.ordem < b.ordem end)

		if #args == 0 then
			if #lista == 0 then return false, "Nenhum spawn salvo (use sp)" end
			local nomes = {}
			for _, e in ipairs(lista) do nomes[#nomes + 1] = e.dados.nome.Text end
			return true, "Spawns: " .. table.concat(nomes, ", ")
		end

		local busca = table.concat(args, " "):lower()
		local function achar(regra)
			for _, e in ipairs(lista) do
				if regra(e.dados.nome.Text:lower()) then return e.dados end
			end
		end
		local achado = achar(function(n) return n == busca end)
			or achar(function(n) return n == "spawn " .. busca end)
			or achar(function(n) return n:sub(1, #busca) == busca end)
		if not achado then return false, "Spawn não encontrado: " .. busca end

		local raiz = pegarPersonagem()
		if not raiz then return false, "Personagem indisponível" end
		raiz.AssemblyLinearVelocity = Vector3.zero
		raiz.CFrame = achado.cf + Vector3.new(0, 3, 0)
		return true, "Indo para " .. achado.nome.Text
	end)

	comando({ "rj", "rejoin" }, "rj - reentrar no servidor (rejoin)", function()
		fazerRejoin()
		return true, "Reentrando..."
	end)

	comando({ "menu" }, "menu - abrir/fechar o menu", function()
		alternarPainel()
		return true, aberto and "Menu aberto" or "Menu fechado"
	end)

	comando({ "cmds", "help", "?" }, "cmds - mostrar esta lista", function()
		abrirAjuda()
		return true
	end)

	----------------------------------------------------------
	-- Executar o que foi digitado
	----------------------------------------------------------
	local function executarComando(trecho)
		local partes = {}
		for p in trecho:gmatch("%S+") do partes[#partes + 1] = p end
		if #partes == 0 then return true end

		local nome = (table.remove(partes, 1):lower():gsub("^/", ""))
		local f = comandos[nome]
		if not f then
			return false, "Comando desconhecido: " .. nome .. " (digite cmds)"
		end

		local rodou, ok, msg = pcall(f, partes)
		if not rodou then
			warn("Erro no comando " .. nome .. ": " .. tostring(ok))
			return false, "Erro ao executar " .. nome
		end
		return ok, msg
	end

	local function executarLinha(texto)
		texto = texto:match("^%s*(.-)%s*$")
		if texto == "" then return end

		local mensagens, tudoCerto = {}, true
		for trecho in texto:gmatch("[^;]+") do
			local ok, msg = executarComando(trecho)
			if msg then mensagens[#mensagens + 1] = msg end
			tudoCerto = tudoCerto and ok
		end

		if #mensagens > 0 then
			ajuda.Visible = false
			mostrarToast(table.concat(mensagens, "\n"), tudoCerto)
		end
		if tudoCerto then
			caixaCmd.Text = ""
			fecharBarra()
		end
	end

	caixaCmd.FocusLost:Connect(function(enter)
		if enter then executarLinha(caixaCmd.Text) end
	end)
	botaoEnviar.Activated:Connect(function()
		executarLinha(caixaCmd.Text)
	end)

	-- Botão TECLADO do menu: mostra/esconde o ícone no canto da tela
	botaoTeclado.MouseButton1Click:Connect(function()
		tecladoLigado = not tecladoLigado
		pintarBotao(botaoTeclado, "TECLADO", tecladoLigado)
		cmdFrame.Visible = tecladoLigado
		if not tecladoLigado then
			fecharBarra()
			ajuda.Visible = false
			toast.Visible = false
		end
	end)
end

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
