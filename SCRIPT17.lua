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
local DISTANCIA_MAXIMA = math.huge -- em studs: sem limite (ESP e Chams valem a qualquer distância; ponha um número, ex.: 500, para limitar)
local COR_ESP = Color3.fromRGB(255, 255, 255)
local COR_CHAMS_CONTORNO = Color3.fromRGB(255, 60, 60)
local COR_CHAMS_PREENCHIMENTO = Color3.fromRGB(255, 60, 60)
local TRANSPARENCIA_PREENCHIMENTO = 0.6 -- 1 = só o contorno, 0 = totalmente preenchido
local VELOCIDADE_FLY_PADRAO = 10
local MULTIPLICADOR_FLY = 10 -- cada ponto de velocidade do FLY vale isso em studs/s (aumente para ficar mais rápido)
local POSE_HEROI = true -- true = personagem voa deitado, braço esticado (pose de herói); false = só voa
local GANHO_INCLINACAO = 1 -- quanto o corpo acompanha a câmera ao olhar pra cima/baixo (1 = total: olhou pra baixo = deitado de barriga pra baixo; 0.5 = metade)
local EFEITO_VELOCIDADE = true -- true = riscos de vento + tremida + FOV maior quando o FLY chega na velocidade máxima
local EFEITO_VEL_MINIMA = 60 -- studs/s: abaixo disso o efeito nunca aparece (voo lento)
local EFEITO_TREMIDA = 1 -- força da tremida da tela (0 = sem tremer)
local EFEITO_FOV_EXTRA = 15 -- quanto o campo de visão abre na velocidade máxima (0 = não muda)
local EFEITO_QTD_RISCOS = 14 -- quantidade de riscos brancos (eles aparecem só na borda da tela)
-- SUPER VOO: ao ficar na velocidade máxima, uma barrinha carrega e ativa o boost
local SUPER = {
	ativo = false,
	habilitado = true, -- false = o super voo nunca carrega (ajustável na categoria Config)
	tempoCarga = 7, -- segundos na velocidade máxima até ativar o super voo
	mult = 3,         -- quantas vezes mais rápido fica no super voo
	tremida = 2.5,    -- tremida extra da tela
	fov = 25,         -- campo de visão extra
}
local VELOCIDADE_VFLY_PADRAO = 80
local VELOCIDADE_MIN, VELOCIDADE_MAX = 1, 500
-- REEXECUTAR APÓS O REJOIN (precisa de executor com queue_on_teleport). Preencha UM dos dois:
local ARQUIVO_SCRIPT = "" -- nome deste script na pasta workspace do executor (ex.: "menu.lua")
local URL_SCRIPT = ""     -- ou o link direto (raw) do script, se ele estiver hospedado

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

-- FOTOS DE FUNDO DO PAINEL (até 4, troca a cada vez que abre o menu)
local proximaFotoFundo -- chamada em alternarPainel; definida logo abaixo
do
	-- >>> COLE AQUI OS LINKS DIRETOS DAS FOTOS (terminam em .png ou .jpg) <<<
	-- Só a foto purple, que é o fundo do painel (a foto do botão MENU é a LINK_BOTAO, mais abaixo).
	local LINKS_FOTOS = {
		"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRo72Vsot2aEMyHqbb1Nij43mYDpQUqGgGLHYvYOu84BD4Y-agSFZXu4U0&s=10", -- foto purple (fundo do painel e botão MENU)
	}
	local TRANSPARENCIA_FOTO = 0.4 -- 0 = foto forte, 1 = invisível
	local ID_FOTO_FUNDO = "rbxassetid://0" -- plano B (opcional): ID do Roblox

	local fundo = Instance.new("ImageLabel")
	fundo.Name = "FotoFundo"
	fundo.Size = UDim2.new(1, 0, 1, 0)
	fundo.BackgroundTransparency = 1
	fundo.ScaleType = Enum.ScaleType.Crop -- preenche sem esticar
	fundo.ImageTransparency = TRANSPARENCIA_FOTO
	fundo.ZIndex = 0 -- fica atrás de tudo
	fundo.Image = ID_FOTO_FUNDO
	fundo.Parent = painel
	Instance.new("UICorner", fundo).CornerRadius = UDim.new(0, 14)

	local imagens = {} -- [número da foto] = imagem pronta para usar
	local indice = 0 -- foto que está aparecendo agora

	-- Baixa a foto (só se for nova ou mudou o link) e devolve a imagem pronta
	local function prepararFoto(i, link)
		local arquivo = "foto_fundo" .. i .. ".png"
		local marca = "foto_fundo" .. i .. ".txt" -- guarda qual link gerou o arquivo
		local atual = isfile(arquivo) and isfile(marca) and readfile(marca) == link
		if not atual then
			writefile(arquivo, game:HttpGet(link))
			writefile(marca, link)
		end
		return getcustomasset(arquivo)
	end

	-- Foto do botão MENU: quadrada, mostrando só o meio da imagem (ScaleType.Crop corta as bordas)
	local LINK_BOTAO = "https://pbs.twimg.com/amplify_video_thumb/1425387452521459712/img/rCnVIOKSPPEVchx9.jpg"
	local function criarFotoBotao(imagem)
		local fotoBotao = Instance.new("ImageLabel")
		fotoBotao.Name = "FotoBotao"
		fotoBotao.Size = UDim2.new(1, 0, 1, 0)
		fotoBotao.BackgroundTransparency = 1
		fotoBotao.Image = imagem
		fotoBotao.ScaleType = Enum.ScaleType.Crop
		fotoBotao.ZIndex = botao.ZIndex + 1
		fotoBotao.Active = false
		fotoBotao.Parent = botao
		Instance.new("UICorner", fotoBotao).CornerRadius = UDim.new(0, 12)
		local contornoFoto = Instance.new("UIStroke")
		contornoFoto.Color = Color3.new(1, 1, 1)
		contornoFoto.Thickness = 1.2
		contornoFoto.Transparency = 0.45
		contornoFoto.Parent = fotoBotao
		botao.Text = ""
		botao.AutoButtonColor = false

		-- Foto do projeto no canto do título do menu (redonda, junto do nome)
		local fotoProjeto = Instance.new("ImageLabel")
		fotoProjeto.Name = "FotoProjeto"
		fotoProjeto.Position = UDim2.fromOffset(8, 5)
		fotoProjeto.Size = UDim2.fromOffset(30, 30)
		fotoProjeto.BackgroundTransparency = 1
		fotoProjeto.Image = imagem
		fotoProjeto.ScaleType = Enum.ScaleType.Crop
		fotoProjeto.ZIndex = 2
		fotoProjeto.Active = false
		fotoProjeto.Parent = painel
		Instance.new("UICorner", fotoProjeto).CornerRadius = UDim.new(1, 0)
		local contornoProjeto = Instance.new("UIStroke")
		contornoProjeto.Color = Color3.new(1, 1, 1)
		contornoProjeto.Thickness = 1.2
		contornoProjeto.Transparency = 0.45
		contornoProjeto.Parent = fotoProjeto
	end

	-- Baixa as fotos em segundo plano, sem travar o menu
	task.spawn(function()
		for i, link in ipairs(LINKS_FOTOS) do
			if link ~= "" then
				local ok, imagem = pcall(prepararFoto, i, link)
				if ok and imagem then
					imagens[i] = imagem
				end
			end
		end
		local okB, imagemB = pcall(prepararFoto, "botao", LINK_BOTAO)
		if okB and imagemB then criarFotoBotao(imagemB) end
	end)

	-- Mostra a próxima foto da fila (pula as vazias) e volta pra 1 depois da última
	proximaFotoFundo = function()
		local total = #LINKS_FOTOS
		for passo = 1, total do
			local i = (indice + passo - 1) % total + 1
			if imagens[i] then
				indice = i
				fundo.Image = imagens[i]
				return
			end
		end
	end
end

local titulo = Instance.new("TextLabel")
titulo.Position = UDim2.new(0, 46, 0, 0) -- deixa o canto esquerdo para a foto do projeto
titulo.Size = UDim2.new(1, -54, 0, 40)
titulo.BackgroundTransparency = 1
titulo.Text = "Purple Bitch Script" -- nome do projeto
titulo.TextColor3 = Color3.new(1, 1, 1)
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 20
titulo.TextScaled = true
titulo.TextXAlignment = Enum.TextXAlignment.Left
do
	local limiteTitulo = Instance.new("UITextSizeConstraint")
	limiteTitulo.MaxTextSize = 20
	limiteTitulo.MinTextSize = 10
	limiteTitulo.Parent = titulo
end
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

-- CATEGORIAS: lista na lateral esquerda (a categoria escolhida fica destacada em roxo)
local MENU = { atual = "Movimento", abas = {}, mostrar = nil,
	-- ajustes do sonar do Xray (mudam na categoria Config)
	sonar = { ligado = true, intervalo = 4, alcance = 120, duracao = 1.8 },
	-- liga/desliga da categoria Config
	cfg = { barraVida = true, alertaChams = true, swimEfeitos = true, noclipTransp = true, tpInstantaneo = false, tpToolInstantaneo = false } }
do -- bloco (libera variáveis locais)
local CATEGORIAS = { "Movimento", "Combate", "Visão", "Teleporte", "Extras", "Config", "Ajuda" }
local LARGURA_LATERAL = 104
local COR_DESTAQUE = Color3.fromRGB(130, 60, 255)
conteudo.Position = UDim2.new(0, LARGURA_LATERAL + 12, 0, 40)
conteudo.Size = UDim2.new(1, -(LARGURA_LATERAL + 12), 1, -40)

local lateral = Instance.new("ScrollingFrame")
lateral.Name = "Categorias"
lateral.Position = UDim2.new(0, 8, 0, 44)
lateral.Size = UDim2.new(0, LARGURA_LATERAL, 1, -88)
lateral.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
lateral.BackgroundTransparency = 0.25
lateral.BorderSizePixel = 0
lateral.ScrollBarThickness = 2
lateral.CanvasSize = UDim2.new()
lateral.AutomaticCanvasSize = Enum.AutomaticSize.Y
lateral.Parent = painel
Instance.new("UICorner", lateral).CornerRadius = UDim.new(0, 10)
do
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 4)
	lay.Parent = lateral
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
	pad.Parent = lateral
	for i, nome in ipairs(CATEGORIAS) do
		local b = Instance.new("TextButton")
		b.Name = "Aba" .. nome
		b.LayoutOrder = i
		b.Size = UDim2.new(1, 0, 0, 34)
		b.BackgroundColor3 = COR_DESTAQUE
		b.BackgroundTransparency = 1
		b.Text = nome
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 14
		b.AutoButtonColor = false
		b.Parent = lateral
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
		MENU.abas[nome] = b
		b.MouseButton1Click:Connect(function()
			if MENU.mostrar then MENU.mostrar(nome) end
		end)
	end
end
end -- fim do bloco (libera variáveis locais)

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

-- ESTILO "BOLHA" (vidro transparente) dos botões do menu principal
-- Mude aqui para ajustar: transparência maior = mais transparente
local VIDRO = {
	corOff = Color3.fromRGB(255, 255, 255), transpOff = 0.92, -- desligado: quase só o contorno
	corOn = Color3.fromRGB(110, 235, 150), transpOn = 0.75, -- ligado: leve brilho verde
	transpTexto = 0, -- texto (0 = forte, 1 = invisível)
	transpContorno = 0.45, -- contorno fininho
}
function VIDRO.aplicar(b, ligado)
	b.BackgroundColor3 = ligado and VIDRO.corOn or VIDRO.corOff
	b.BackgroundTransparency = ligado and VIDRO.transpOn or VIDRO.transpOff
	b.TextColor3 = Color3.new(0, 0, 0) -- texto preto
	b.Font = Enum.Font.Gotham -- fonte normal (sem negrito)
	b.TextTransparency = VIDRO.transpTexto
	b.TextStrokeTransparency = 1 -- sem contorno no texto
	local contorno = b:FindFirstChildOfClass("UIStroke")
	if not contorno then
		contorno = Instance.new("UIStroke")
		contorno.Parent = b
	end
	contorno.Color = Color3.new(1, 1, 1)
	contorno.Thickness = 1.2
	contorno.Transparency = VIDRO.transpContorno
end

-- LISTA ORGANIZADA: duas colunas, todos os botões do mesmo tamanho, um embaixo do outro.
-- O 1º número de criarLinha é só a ordem na grade (menor = primeiro).
local ALTURA_BOTAO = 38
local ESPACO = 6

local lista = Instance.new("UIListLayout") -- empilha: grade de botões em cima, dicas embaixo
lista.SortOrder = Enum.SortOrder.LayoutOrder
lista.Padding = UDim.new(0, 8)
lista.Parent = conteudo

local margem = Instance.new("UIPadding")
margem.PaddingTop = UDim.new(0, 6)
margem.PaddingBottom = UDim.new(0, 40) -- espaço para a alça de redimensionar não cobrir o fim
margem.PaddingLeft = UDim.new(0, ESPACO)
margem.PaddingRight = UDim.new(0, ESPACO)
margem.Parent = conteudo

local grade = Instance.new("Frame")
grade.Name = "Grade"
grade.LayoutOrder = 1
grade.Size = UDim2.new(1, 0, 0, 0)
grade.AutomaticSize = Enum.AutomaticSize.Y
grade.BackgroundTransparency = 1
grade.Parent = conteudo

-- Os botões ficam numa grade de 2 colunas (só aparecem os da categoria escolhida; o resto some e a grade se reorganiza).
do
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -ESPACO / 2, 0, ALTURA_BOTAO)
	gl.CellPadding = UDim2.fromOffset(ESPACO, ESPACO)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.FillDirectionMaxCells = 2
	gl.Parent = grade
end

-- Nomes mostrados nos botões (em português). A chave é o nome interno usado no resto do script.
MENU.trad = {
	FLY = "VOAR", VFLY = "VOAR (VEÍCULO)", SWIM = "NADAR NO AR", NOCLIP = "ATRAVESSAR PAREDES",
	SHIFTLOCK = "CÂMERA TRAVADA", TPTOOL = "FERRAMENTA TP", ESP = "VER JOGADORES", CHAMS = "CONTORNO",
	XRAY = "MAPA TRANSPARENTE", AIMBOT = "MIRA AUTOMÁTICA", GRUDAR = "GRUDAR NO CHÃO",
	WALL = "ANDAR NAS PAREDES", NOTAS = "ANOTAÇÕES",
}
-- Em que categoria cada botão fica (o que não está aqui vai para "Extras")
MENU.categoria = {
	FLY = "Movimento", VFLY = "Movimento", SWIM = "Movimento", NOCLIP = "Movimento", SHIFTLOCK = "Movimento",
	GRUDAR = "Movimento", WALL = "Movimento",
	ESP = "Combate", CHAMS = "Combate", AIMBOT = "Combate", ALVO = "Combate", PAREDE = "Combate", TIME = "Combate",
	XRAY = "Visão", VIEW = "Visão",
	TP = "Teleporte", TPTOOL = "Teleporte", SPAWNS = "Teleporte",
	REJOIN = "Extras", NOTAS = "Extras",
}

-- Cria uma célula: botão liga/desliga (+ caixa de velocidade opcional, colada no botão)
local function criarLinha(ordem, nome, comVelocidade, velocidadePadrao)
	local celulaFrame = Instance.new("Frame")
	celulaFrame.Name = "Celula" .. nome
	celulaFrame.LayoutOrder = ordem
	celulaFrame.Size = UDim2.new(1, 0, 0, ALTURA_BOTAO)
	celulaFrame.BackgroundTransparency = 1
	celulaFrame.Parent = grade
	local categoria = MENU.categoria[nome] or "Extras"
	celulaFrame:SetAttribute("Categoria", categoria)
	celulaFrame.Visible = (categoria == MENU.atual)

	local b = Instance.new("TextButton")
	b.Name = "Botao" .. nome
	b.Position = UDim2.new(0, 0, 0, 0)
	b.Size = UDim2.new(0.68, 0, 1, 0) -- todos os botões têm o mesmo tamanho
	b.Text = (MENU.trad[nome] or nome) .. ": DESLIGADO"
	VIDRO.aplicar(b, false)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextScaled = true -- o texto encolhe se não couber
	local limite = Instance.new("UITextSizeConstraint")
	limite.MaxTextSize = 15
	limite.MinTextSize = 8
	limite.Parent = b
	b.Parent = celulaFrame
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)

	local caixa = nil
	if comVelocidade then
		caixa = Instance.new("TextBox")
		caixa.Name = "Velocidade" .. nome
		caixa.Position = UDim2.new(0.70, 0, 0, 0)
		caixa.Size = UDim2.new(0.30, 0, 1, 0)
		VIDRO.aplicar(caixa, false)
		caixa.Text = tostring(velocidadePadrao)
		caixa.PlaceholderText = "vel."
		caixa.PlaceholderColor3 = Color3.fromRGB(140, 140, 140)
		caixa.Font = Enum.Font.GothamBold
		caixa.TextSize = 15
		caixa.ClearTextOnFocus = false
		caixa.Parent = celulaFrame
		Instance.new("UICorner", caixa).CornerRadius = UDim.new(0, 10)
	end
	return b, caixa
end

-- Grupo 1: voo e movimento
local botaoFly, caixaFly = criarLinha(1, "FLY", true, VELOCIDADE_FLY_PADRAO)
local botaoVFly, caixaVFly = criarLinha(2, "VFLY", true, VELOCIDADE_VFLY_PADRAO)
local botaoSwim, caixaSwim = criarLinha(3, "SWIM", true, VELOCIDADE_SWIM_PADRAO)
local botaoNoclip = criarLinha(4, "NOCLIP", false)
local botaoShiftLock = criarLinha(5, "SHIFTLOCK", false)
local botaoTPTool = criarLinha(6, "TPTOOL", false)

-- Grupo 2: visão
local botaoESP = criarLinha(7, "ESP", false)
local botaoChams = criarLinha(8, "CHAMS", false)
local botaoXray, caixaXray = criarLinha(9, "XRAY", true, 0.6)

-- Grupo 3: teleporte e servidor
local botaoTP = criarLinha(10, "TP", false)
botaoTP.Text = "TELEPORTAR"
local botaoSpawns = criarLinha(11, "SPAWNS", false)
botaoSpawns.Text = "LOCAIS SALVOS"
local botaoView = criarLinha(12, "VIEW", false)
botaoView.Text = "ESPECTAR"
local botaoRejoin = criarLinha(13, "REJOIN", false)
botaoRejoin.Text = "REENTRAR"


local dica = Instance.new("TextLabel")
dica.Name = "Dicas"
dica.LayoutOrder = 2
dica.Size = UDim2.new(1, 0, 0, 0)
dica.AutomaticSize = Enum.AutomaticSize.Y
dica.BackgroundTransparency = 1
dica.TextWrapped = true
dica.TextXAlignment = Enum.TextXAlignment.Left
dica.TextYAlignment = Enum.TextYAlignment.Top
dica.Text = "Mover: arraste o título do painel ou o botão MENU. Tamanho: arraste o ◢ do canto.\nFly: WASD/analógico para mover, mire a câmera para subir/descer.\nEspaço/E = subir, Shift/Q = descer.\nVFLY: use sentado em um veículo. Aparecem setas na tela (esquerda: ▲▼◀▶ andam; direita: SOBE/DESCE) para jogos em que o analógico não move o veículo; arraste o ≡ para mudar de lugar.\nNOCLIP: atravessa paredes (sem o Fly você cai pelo chão).\nSWIM: nada no ar como se estivesse na água.\nSPAWNS: salve posições (ficam gravadas por jogo, se o executor permitir), renomeie, veja a distância e clique em IR para voar até lá. O nome aparece discreto em cima do spawn quando você está perto.\nVIEW: escolha um jogador para ver pela câmera dele (espectar). Na barra de cima, ◀ ▶ trocam de jogador e SAIR volta pra você. Comando: view <jogador> / unview.\nTP: digite na busca para filtrar; a lista mostra a distância. Clique no nome (ou dê Enter na busca para ir no primeiro da lista) para voar até o jogador em velocidade supersônica.\nXRAY: deixa o mapa transparente (caixa: 0 = normal, 0.95 = quase invisível).\nTPTOOL: dá um item no inventário; equipe e clique/toque onde quer ir (você voa até lá em uma fração de segundo, com os efeitos de velocidade e o estrondo na chegada).\nSHIFTLOCK: mostra o cadeado na tela (arraste para mover). Toque nele: azul = travado, branco = solto. O ⇄ embaixo troca o ombro da câmera. Comando: sl / unsl.\nAIMBOT: bolinha verde no centro = alcance (digite o tamanho na caixa). A mira muda ao travar: na cabeça os tracinhos fecham (vermelho), no tronco eles abrem (laranja); a vida do alvo aparece pequena no canto da bolinha. ALVO troca cabeça/tronco, PAREDE = mirar através de paredes, TIME = ignorar seu time. Comando: aim [tamanho] / unaim.\nBARRA DE COMANDOS: a barrinha \"> comandos\" no canto de baixo da tela (arraste para mover). Toque nela e abre um painel escuro com a caixa de digitar e a lista de comandos logo abaixo, que filtra enquanto você digita (toque num comando para completar). Ao dar Enter, fechar o teclado ou tocar fora, o painel volta para a tira fina. Ex.: fly 80, unfly, np, xy, rj. No PC, a tecla , (vírgula) também abre a barra. Vários comandos de uma vez: fly 80, np."
dica.TextColor3 = Color3.fromRGB(170, 170, 180)
dica.Font = Enum.Font.Gotham
dica.TextSize = 12
dica.Visible = false -- só aparece na categoria "Ajuda"
dica.Parent = conteudo

-- Troca de categoria: mostra só os botões dela e destaca a aba
function MENU.mostrar(nome)
	MENU.atual = nome
	for _, c in ipairs(grade:GetChildren()) do
		local cat = c:GetAttribute("Categoria")
		if cat then c.Visible = (cat == nome) end
	end
	dica.Visible = (nome == "Ajuda")
	for n, b in pairs(MENU.abas) do
		b.BackgroundTransparency = (n == nome) and 0.1 or 1
	end
	conteudo.CanvasPosition = Vector2.new(0, 0)
end
MENU.mostrar(MENU.atual)

-- (os botões ▲▼ foram removidos; subir/descer = inclinar a câmera, ou Espaço/E e Shift/Q no teclado)
local function atualizarBotaoVertical()
	if not (estado.fly or estado.vfly or estado.swim) then
		subindo, descendo = false, false
	end
end

local function pintarBotao(b, nome, ligado)
	b.Text = (MENU.trad[nome] or nome) .. (ligado and ": LIGADO" or ": DESLIGADO")
	VIDRO.aplicar(b, ligado)
end

------------------------------------------------------------
-- ANIMAÇÃO DE ENTRADA DO BOTÃO
------------------------------------------------------------
task.wait(0.5)
TweenService:Create(botao, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
	Size = UDim2.new(0, 52, 0, 52), -- quadrado (combina com a foto do botão)
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
		pcall(proximaFotoFundo) -- troca a foto de fundo a cada abertura
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

local atualizarESP, definirChams, definirESP
do -- bloco (libera variáveis locais)
------------------------------------------------------------
-- ESP (nome + distância) e CHAMS (contorno/preenchimento)
------------------------------------------------------------
local espObjetos = {}   -- [Player] = { gui = BillboardGui, label = TextLabel }
local chamsObjetos = {} -- [Player] = Highlight

local function removerESP(p)
	local obj = espObjetos[p]
	if obj then
		if obj.tween then obj.tween:Cancel() end
		for _, a in ipairs(obj.aneis) do a.parte:Destroy() end
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

local COR_VIDA_CHEIA = Color3.fromRGB(90, 255, 120)
local COR_VIDA_BAIXA = Color3.fromRGB(255, 70, 70)
local COR_ONDA = Color3.fromRGB(120, 220, 255) -- anel do chão (vira vermelho no alerta)
local DISTANCIA_ALERTA = 30 -- studs: abaixo disso aparece o "!" e o nome treme
local ultimoESP

-- Pop ao entrar no alcance (cresce com um "quique") e encolhe ao sair
local function definirDentroESP(obj, dentro)
	if obj.dentro == dentro then return end
	obj.dentro = dentro
	if obj.tween then obj.tween:Cancel() end
	local info = dentro and TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		or TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	obj.tween = TweenService:Create(obj.escala, info, { Scale = dentro and 1 or 0 })
	obj.tween:Play()
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
	bb.Size = UDim2.new(0, 200, 0, 66)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.MaxDistance = math.huge -- sem corte de distância
	bb.Parent = gui

	-- Tudo fica dentro de "conteudo", que cresce com um pop quando o jogador entra no alcance
	local conteudo = Instance.new("Frame")
	conteudo.Name = "Conteudo"
	conteudo.Size = UDim2.new(1, 0, 1, 0)
	conteudo.BackgroundTransparency = 1
	conteudo.Parent = bb
	local escala = Instance.new("UIScale")
	escala.Scale = 0
	escala.Parent = conteudo

	-- Nome + distância
	local label = Instance.new("TextLabel")
	label.Name = "Texto"
	label.Position = UDim2.fromOffset(0, 18)
	label.Size = UDim2.new(1, 0, 0, 34)
	label.BackgroundTransparency = 1
	label.TextColor3 = COR_ESP
	label.TextStrokeTransparency = 0.5
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.Text = p.DisplayName
	label.Parent = conteudo

	-- Barra de vida (verde cheia -> vermelha quase morta)
	local fundoVida = Instance.new("Frame")
	fundoVida.Name = "VidaFundo"
	fundoVida.AnchorPoint = Vector2.new(0.5, 0)
	fundoVida.Position = UDim2.new(0.5, 0, 0, 54)
	fundoVida.Size = UDim2.fromOffset(36, 3) -- pequena e discreta (era 90x6)
	fundoVida.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	fundoVida.BackgroundTransparency = 0.4
	fundoVida.BorderSizePixel = 0
	fundoVida.Parent = conteudo
	Instance.new("UICorner", fundoVida).CornerRadius = UDim.new(1, 0)
	local contornoVida = Instance.new("UIStroke")
	contornoVida.Color = Color3.new(0, 0, 0)
	contornoVida.Thickness = 0.75
	contornoVida.Transparency = 0.55
	contornoVida.Parent = fundoVida
	local enche = Instance.new("Frame")
	enche.Name = "Vida"
	enche.Size = UDim2.fromScale(1, 1)
	enche.BackgroundColor3 = COR_VIDA_CHEIA
	enche.BorderSizePixel = 0
	enche.Parent = fundoVida
	Instance.new("UICorner", enche).CornerRadius = UDim.new(1, 0)

	-- Ícone de alerta "!" (só aparece quando alguém chega muito perto)
	local icone = Instance.new("Frame")
	icone.Name = "Alerta"
	icone.AnchorPoint = Vector2.new(0.5, 0)
	icone.Position = UDim2.new(0.5, 0, 0, 3)
	icone.Size = UDim2.fromOffset(12, 12) -- menor (era 18x18)
	icone.BackgroundColor3 = COR_VIDA_BAIXA
	icone.BackgroundTransparency = 1
	icone.BorderSizePixel = 0
	icone.Parent = conteudo
	Instance.new("UICorner", icone).CornerRadius = UDim.new(1, 0)
	local iconeEscala = Instance.new("UIScale")
	iconeEscala.Parent = icone
	local iconeTexto = Instance.new("TextLabel")
	iconeTexto.Size = UDim2.fromScale(1, 1)
	iconeTexto.BackgroundTransparency = 1
	iconeTexto.Text = "!"
	iconeTexto.TextColor3 = Color3.new(1, 1, 1)
	iconeTexto.Font = Enum.Font.GothamBlack
	iconeTexto.TextSize = 10
	iconeTexto.TextTransparency = 1
	iconeTexto.Parent = icone

	-- Ondinhas no chão (radar): dois anéis que nascem sob os pés e crescem sumindo
	local aneis = {}
	for i = 1, 2 do
		local parte = Instance.new("Part")
		parte.Name = "ESP_Onda"
		parte.Anchored = true
		parte.CanCollide = false
		parte.CanQuery = false
		parte.CanTouch = false
		parte.CastShadow = false
		parte.Transparency = 1
		parte.Size = Vector3.new(2, 0.1, 2)
		parte.Parent = workspace.CurrentCamera
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Top
		sg.AlwaysOnTop = true
		sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		sg.CanvasSize = Vector2.new(256, 256)
		sg.LightInfluence = 0
		sg.Parent = parte
		local anel = Instance.new("Frame")
		anel.Size = UDim2.fromScale(1, 1)
		anel.BackgroundTransparency = 1
		anel.BorderSizePixel = 0
		anel.Parent = sg
		Instance.new("UICorner", anel).CornerRadius = UDim.new(1, 0)
		local contornoAnel = Instance.new("UIStroke")
		contornoAnel.Color = COR_ONDA
		contornoAnel.Thickness = 8
		contornoAnel.Transparency = 1
		contornoAnel.Parent = anel
		aneis[i] = { parte = parte, contorno = contornoAnel }
	end

	espObjetos[p] = {
		gui = bb, label = label, escala = escala, enche = enche, vida = 1, dentro = false,
		icone = icone, iconeEscala = iconeEscala, iconeTexto = iconeTexto, alerta = 0,
		aneis = aneis, fase = math.random(),
	}
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

function atualizarESP()
	if not estado.esp then return end

	local meuChar = player.Character
	local minhaRaiz = meuChar and meuChar:FindFirstChild("HumanoidRootPart")
	if not minhaRaiz then return end

	local agora = os.clock()
	local dt = math.min(agora - (ultimoESP or agora), 0.1)
	ultimoESP = agora
	local piscada = 0.5 + 0.5 * math.sin(agora * 14)

	for p, obj in pairs(espObjetos) do
		local char = p.Character
		local raiz = char and char:FindFirstChild("HumanoidRootPart")
		if raiz then
			local dist = (raiz.Position - minhaRaiz.Position).Magnitude
			definirDentroESP(obj, dist <= DISTANCIA_MAXIMA)
			obj.gui.Enabled = obj.dentro or obj.escala.Scale > 0.01
			obj.label.Text = string.format("%s\n[%d studs]", p.DisplayName, math.floor(dist))

			-- vida: a barra desliza suave até o valor real
			local hum = char:FindFirstChildOfClass("Humanoid")
			local alvoVida = hum and math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1) or 0
			obj.vida = obj.vida + (alvoVida - obj.vida) * 0.2
			obj.enche.Size = UDim2.fromScale(obj.vida, 1)
			obj.enche.BackgroundColor3 = COR_VIDA_BAIXA:Lerp(COR_VIDA_CHEIA, obj.vida)
			obj.enche.Parent.Visible = MENU.cfg.barraVida

			-- alerta: "!" piscando + nome vermelho tremendo quando está muito perto
			local perto = obj.dentro and dist <= DISTANCIA_ALERTA
			obj.alerta = obj.alerta + ((perto and 1 or 0) - obj.alerta) * math.min(1, dt * 10)
			local al = obj.alerta
			if al < 0.01 then al = 0 end
			local forca = al * (0.55 + 0.45 * piscada)
			obj.icone.BackgroundTransparency = 1 - forca
			obj.iconeTexto.TextTransparency = 1 - forca
			obj.iconeEscala.Scale = 0.7 + 0.5 * al * (0.7 + 0.3 * piscada)
			obj.label.TextColor3 = COR_ESP:Lerp(COR_VIDA_BAIXA, al * 0.7)
			obj.label.Position = UDim2.fromOffset((math.random() * 2 - 1) * 1.5 * al, 18 + (math.random() * 2 - 1) * 1 * al)

			-- ondinhas no chão: sobem de tamanho sumindo; mais rápidas e vermelhas no alerta
			obj.fase = (obj.fase + dt * (0.55 + al * 0.9)) % 1
			local vis = math.clamp(obj.escala.Scale, 0, 1)
			local cf, tam = char:GetBoundingBox()
			local pe = Vector3.new(cf.Position.X, cf.Position.Y - tam.Y / 2 + 0.1, cf.Position.Z)
			for i, a in ipairs(obj.aneis) do
				local t = (obj.fase + (i - 1) * 0.5) % 1
				local d = 2 + t * 8
				a.parte.Size = Vector3.new(d, 0.1, d)
				a.parte.CFrame = CFrame.new(pe)
				a.contorno.Color = COR_ONDA:Lerp(COR_VIDA_BAIXA, al)
				a.contorno.Transparency = 1 - (1 - t) * vis * 0.85
			end
		else
			definirDentroESP(obj, false)
			obj.gui.Enabled = obj.escala.Scale > 0.01
			for _, a in ipairs(obj.aneis) do a.contorno.Transparency = 1 end
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

function definirESP(v)
	estado.esp = v
	pintarBotao(botaoESP, "ESP", v)
	atualizarTodos()
end

-- CHAMS DINÂMICO: a cor muda com a distância (vermelho = perto, verde = longe) e o brilho "respira" de leve
do
	local DIST_PERTO = 25  -- studs: até aqui fica totalmente vermelho
	local DIST_LONGE = 300 -- studs: daqui em diante fica totalmente verde
	local AMPLITUDE_PULSO = 0.12 -- quanto o preenchimento varia (0 = sem pulso)
	local PARADAS = { -- cores do perto para o longe
		Color3.fromRGB(255, 60, 60),   -- vermelho
		Color3.fromRGB(255, 160, 40),  -- laranja
		Color3.fromRGB(255, 230, 60),  -- amarelo
		Color3.fromRGB(70, 225, 110),  -- verde
	}

	local function corPorDistancia(d)
		local t = math.clamp((d - DIST_PERTO) / (DIST_LONGE - DIST_PERTO), 0, 1) * (#PARADAS - 1)
		local i = math.min(math.floor(t) + 1, #PARADAS - 1)
		return PARADAS[i]:Lerp(PARADAS[i + 1], t - (i - 1))
	end

	RunService.RenderStepped:Connect(function()
		if not estado.chams then return end
		local meuChar = player.Character
		local minhaRaiz = meuChar and meuChar:FindFirstChild("HumanoidRootPart")
		if not minhaRaiz then return end

		local agora = os.clock()
		for p, h in pairs(chamsObjetos) do
			local char = p.Character
			local raiz = char and char:FindFirstChild("HumanoidRootPart")
			if raiz and h.Parent then
				local dist = (raiz.Position - minhaRaiz.Position).Magnitude
				if MENU.cfg.alertaChams then
					local cor = corPorDistancia(dist)
					h.FillColor = cor
					h.OutlineColor = cor

					-- pulso suave: mais rápido de perto, mais lento de longe; cada jogador com fase própria
					local fase = (p.UserId % 628) / 100
					local velocidade = 1.6 + 1.6 * (1 - math.clamp(dist / DIST_LONGE, 0, 1))
					local onda = math.sin(agora * velocidade + fase)
					h.FillTransparency = math.clamp(TRANSPARENCIA_PREENCHIMENTO + onda * AMPLITUDE_PULSO, 0, 1)
					h.OutlineTransparency = 0.08 + (onda * 0.5 + 0.5) * 0.17
				else
					-- alerta desligado: cor fixa, sem mudar com a distância e sem pulsar
					h.FillColor = COR_CHAMS_PREENCHIMENTO
					h.OutlineColor = COR_CHAMS_CONTORNO
					h.FillTransparency = TRANSPARENCIA_PREENCHIMENTO
					h.OutlineTransparency = 0.15
				end
			end
		end
	end)
end

function definirChams(v)
	estado.chams = v
	pintarBotao(botaoChams, "CHAMS", v)
	atualizarTodos()
end

botaoESP.MouseButton1Click:Connect(function() definirESP(not estado.esp) end)
botaoChams.MouseButton1Click:Connect(function() definirChams(not estado.chams) end)

end -- fim do bloco (libera variáveis locais)
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

local aplicarPoseFly, flyBG, flyBV, iniciarFly, pararFly, poseLean, poseMov, vBG, vBV
do -- bloco (libera variáveis locais)
------------------------------------------------------------
-- FLY
------------------------------------------------------------
-- (declarado antes)
-- (declarado antes)

-- POSE DE HERÓI: mexe nas juntas do corpo (R15 e R6) enquanto voa
poseMov = 0 -- 0 = parado (em pé), 1 = voando (deitado, braço esticado)
local poseChar, poseJuntas
poseLean = 0 -- inclinação calculada em atualizarFly e usada na pose
local animateDesligado -- script "Animate" do personagem, desligado enquanto voa

local function acharJunta(char, nome)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name == nome then return d end
	end
end

local function limparPoseFly()
	if poseJuntas then
		for _, j in pairs(poseJuntas) do
			if j.Parent then j.Transform = CFrame.new() end
		end
	end
	poseChar, poseJuntas, poseMov = nil, nil, 0
	estado.poseW, estado.flyFrente, estado.flyOcioso = nil, 0, 0
	if animateDesligado then
		animateDesligado.Disabled = false
		animateDesligado = nil
	end
end

function aplicarPoseFly(char, hum, inclinacao)
	-- para as animações normais (andar/cair) enquanto voa, senão elas desfazem a pose
	local animate = char:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") and not animate.Disabled then
		animate.Disabled = true
		animateDesligado = animate
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop(0) end
	end

	local r15 = hum.RigType == Enum.HumanoidRigType.R15
	if poseChar ~= char then
		poseChar = char
		poseJuntas = {
			ombroD = acharJunta(char, r15 and "RightShoulder" or "Right Shoulder"),
			ombroE = acharJunta(char, r15 and "LeftShoulder" or "Left Shoulder"),
			cotoveloD = r15 and acharJunta(char, "RightElbow") or nil,
			cotoveloE = r15 and acharJunta(char, "LeftElbow") or nil,
			quadrilD = acharJunta(char, r15 and "RightHip" or "Right Hip"),
			quadrilE = acharJunta(char, r15 and "LeftHip" or "Left Hip"),
			pescoco = acharJunta(char, "Neck"),
		}
	end
	local j = poseJuntas
	local mov = poseMov -- 0 = parado, 1 = voando
	local R = math.rad

	local function pose(junta, parado, voando)
		if junta then junta.Transform = parado:Lerp(voando, mov) end
	end

	if r15 then
		-- 5 poses, misturadas pelos pesos de estado.poseW (f = frente, t = trás, e = esquerda, d = direita):
		-- PARADO: mãos na cintura (pose de herói flutuando).
		-- FRENTE: deitado, braço direito esticado à frente. TRÁS: de costas, braços abertos e relaxados.
		-- ESQUERDA/DIREITA: deitado de lado, o braço de cima esticado na direção do voo.
		local w = estado.poseW or { f = 0, t = 0, e = 0, d = 0 }
		local soma = w.f + w.t + w.e + w.d
		local esc = soma > 1 and 1 / soma or 1
		local pesos = { w.f * esc, w.t * esc, w.e * esc, w.d * esc }
		local function pose4(junta, parado, f, t, e, d)
			if not junta then return end
			local total = 1 - math.min(1, soma * esc)
			local acc = parado
			local alvos = { f, t, e, d }
			for i = 1, 4 do
				local peso = pesos[i]
				if peso > 0.0001 then
					total = total + peso
					acc = acc:Lerp(alvos[i], peso / total)
				end
			end
			junta.Transform = acc
		end
		local A = CFrame.Angles
		local id = CFrame.new()
		--         junta        parado                                  frente           trás                  esquerda        direita
		pose4(j.ombroD,    A(0, 0, R(35)) * A(0, R(90), 0),   A(R(170), 0, 0), A(R(-20), 0, R(20)),  A(R(170), 0, 0), A(R(-15), 0, 0))
		pose4(j.ombroE,    A(0, 0, -R(35)) * A(0, -R(90), 0), A(R(-15), 0, 0), A(R(-20), 0, -R(20)), A(R(-15), 0, 0), A(R(170), 0, 0))
		pose4(j.cotoveloD, A(R(105), 0, 0),                   id,              A(R(15), 0, 0),       id,              A(R(25), 0, 0))
		pose4(j.cotoveloE, A(R(105), 0, 0),                   A(R(25), 0, 0),  A(R(15), 0, 0),       A(R(25), 0, 0),  id)
		-- pernas: levemente abertas parado; esticadas para trás voando de frente ou de lado; à frente de costas
		pose4(j.quadrilD,  A(0, 0, R(6)),                     A(R(-10), 0, 0), A(R(8), 0, R(3)),     A(R(-18), 0, 0), A(R(-18), 0, 0))
		pose4(j.quadrilE,  A(0, 0, -R(6)),                    A(R(-25), 0, 0), A(R(8), 0, -R(3)),    A(R(-18), 0, 0), A(R(-18), 0, 0))
	else
		-- R6 não tem cotovelo: parado, os braços ficam levemente abertos
		pose(j.ombroD, CFrame.Angles(-R(18), 0, 0), CFrame.Angles(0, 0, R(170)))
		pose(j.ombroE, CFrame.Angles(-R(18), 0, 0), CFrame.Angles(0, 0, R(15)))
		pose(j.quadrilD, CFrame.Angles(-R(6), 0, 0), CFrame.Angles(0, 0, R(-10)))
		pose(j.quadrilE, CFrame.Angles(-R(6), 0, 0), CFrame.Angles(0, 0, -R(-25)))
	end

	-- cabeça olha para frente em vez de para o chão
	if j.pescoco then
		local ang = math.clamp(-inclinacao * 0.8, -R(80), R(80))
		j.pescoco.Transform = CFrame.Angles(r15 and ang or -ang, 0, 0)
	end
end

function pararFly()
	limparPoseFly()
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
	local _, hum = pegarPersonagem()
	if hum then hum.PlatformStand = false end
end

function iniciarFly(raiz, hum)
	if flyBV then flyBV:Destroy() end
	if flyBG then flyBG:Destroy() end

	flyBV = Instance.new("BodyVelocity")
	flyBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
	flyBV.Velocity = Vector3.zero
	flyBV.Parent = raiz

	flyBG = Instance.new("BodyGyro")
	flyBG.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
	flyBG.P = 9e4
	flyBG.D = 1200
	flyBG.CFrame = raiz.CFrame
	flyBG.Parent = raiz

	hum.PlatformStand = true
end

end -- fim do bloco (libera variáveis locais)
------------------------------------------------------------
-- AIMBOT (bolinha verde = alcance; trava a câmera no alvo sem atraso)
------------------------------------------------------------
estado.aim = false
local definirAimbot

do
	local aim = {
		parte = "Head",       -- "Head" (cabeça) ou "Torso" (tronco)
		ignorarParede = false, -- true = mira mesmo com parede no meio
		ignorarTime = true,    -- true = não mira em quem é do seu time
		tamanho = 150,         -- diâmetro da bolinha verde em pixels (= alcance)
	}
	local TAMANHO_MIN, TAMANHO_MAX = 40, 900

	-- Botões (entram na grade do menu)
	local botaoAim, caixaAim = criarLinha(14, "AIMBOT", true, aim.tamanho)
	local botaoAlvo = criarLinha(15, "ALVO", false)
	local botaoParede = criarLinha(16, "PAREDE", false)
	local botaoTime = criarLinha(17, "TIME", false)

	local function pintarOpcoes()
		botaoAlvo.Text = "ALVO: " .. (aim.parte == "Head" and "CABEÇA" or "TRONCO")
		VIDRO.aplicar(botaoAlvo, false)
		botaoParede.Text = "PAREDE: " .. (aim.ignorarParede and "IGNORA" or "RESPEITA")
		VIDRO.aplicar(botaoParede, aim.ignorarParede)
		botaoTime.Text = "TIME: " .. (aim.ignorarTime and "IGNORA" or "MIRA")
		VIDRO.aplicar(botaoTime, aim.ignorarTime)
	end
	pintarOpcoes()

	-- Bolinha verde no centro da tela
	local aimGui = Instance.new("ScreenGui")
	aimGui.Name = "AimbotCirculo"
	aimGui.ResetOnSpawn = false
	aimGui.IgnoreGuiInset = true
	aimGui.DisplayOrder = -1
	aimGui.Parent = playerGui

	local circulo = Instance.new("Frame")
	circulo.AnchorPoint = Vector2.new(0.5, 0.5)
	circulo.Position = UDim2.fromScale(0.5, 0.5)
	circulo.Size = UDim2.fromOffset(aim.tamanho, aim.tamanho)
	circulo.BackgroundColor3 = Color3.fromRGB(60, 255, 100)
	circulo.BackgroundTransparency = 0.92
	circulo.BorderSizePixel = 0
	circulo.Active = false
	circulo.Visible = false
	circulo.Parent = aimGui
	Instance.new("UICorner", circulo).CornerRadius = UDim.new(1, 0)
	local contorno = Instance.new("UIStroke")
	contorno.Color = Color3.fromRGB(60, 255, 100)
	contorno.Thickness = 2
	contorno.Parent = circulo

	----------------------------------------------------------
	-- Mira de arma no centro da bolinha. Muda conforme o estado:
	--  * sem alvo: tracinhos brancos abertos
	--  * alvo na CABEÇA: os tracinhos fecham para o centro (vermelho)
	--  * alvo no TRONCO: o contrário, os tracinhos abrem ainda mais (laranja)
	-- Quando trava num alvo novo dá um pulsinho. A vida do alvo aparece pequena no canto superior direito da bolinha.
	----------------------------------------------------------
	local COR_CIRCULO = Color3.fromRGB(60, 255, 100)
	local MIRA = {
		gapParado = 9,   -- distância (px) do centro aos tracinhos sem alvo
		gapCabeca = 3,   -- na cabeça: fecha
		gapTronco = 17,  -- no tronco: abre
		corParado = Color3.new(1, 1, 1),
		corCabeca = Color3.fromRGB(255, 70, 70),
		corTronco = Color3.fromRGB(255, 170, 50),
		comprimento = 8, -- tamanho de cada tracinho
		grossura = 2,
	}

	local mira = Instance.new("Frame")
	mira.Name = "Mira"
	mira.AnchorPoint = Vector2.new(0, 0)
	mira.Position = UDim2.fromScale(0.5, 0.5)
	mira.Size = UDim2.fromOffset(0, 0)
	mira.BackgroundTransparency = 1
	mira.Active = false
	mira.Parent = circulo

	local function criarTraco(ancora, horizontal)
		local f = Instance.new("Frame")
		f.AnchorPoint = ancora
		f.Size = horizontal and UDim2.fromOffset(MIRA.comprimento, MIRA.grossura)
			or UDim2.fromOffset(MIRA.grossura, MIRA.comprimento)
		f.BackgroundColor3 = MIRA.corParado
		f.BorderSizePixel = 0
		f.Active = false
		f.Parent = mira
		local sombra = Instance.new("UIStroke")
		sombra.Color = Color3.new(0, 0, 0)
		sombra.Thickness = 1
		sombra.Transparency = 0.5
		sombra.Parent = f
		return f
	end
	local tracoCima = criarTraco(Vector2.new(0.5, 1), false)
	local tracoBaixo = criarTraco(Vector2.new(0.5, 0), false)
	local tracoEsq = criarTraco(Vector2.new(1, 0.5), true)
	local tracoDir = criarTraco(Vector2.new(0, 0.5), true)

	local ponto = Instance.new("Frame")
	ponto.AnchorPoint = Vector2.new(0.5, 0.5)
	ponto.Size = UDim2.fromOffset(3, 3)
	ponto.BackgroundColor3 = MIRA.corParado
	ponto.BorderSizePixel = 0
	ponto.Active = false
	ponto.Parent = mira
	Instance.new("UICorner", ponto).CornerRadius = UDim.new(1, 0)

	-- Vida do alvo: bem pequena, fora da bolinha, no canto superior direito
	local textoVida = Instance.new("TextLabel")
	textoVida.AnchorPoint = Vector2.new(0, 1)
	textoVida.Position = UDim2.fromScale(0.5 + 0.3536, 0.5 - 0.3536) -- 45° em cima à direita, na borda do círculo
	textoVida.Size = UDim2.fromOffset(34, 12)
	textoVida.BackgroundTransparency = 1
	textoVida.Font = Enum.Font.GothamBold
	textoVida.TextSize = 11
	textoVida.TextXAlignment = Enum.TextXAlignment.Left
	textoVida.TextColor3 = Color3.new(1, 1, 1)
	textoVida.TextStrokeTransparency = 0.6
	textoVida.Visible = false
	textoVida.Active = false
	textoVida.Parent = circulo

	local gapAtual, corAtual = MIRA.gapParado, MIRA.corParado
	local travadoMix = 0 -- 0 = sem alvo, 1 = travado
	local pulso = 0
	local alvoAnterior
	local ultimoMira

	local function atualizarMira(alvo)
		local agora = os.clock()
		local dt = math.min(agora - (ultimoMira or agora), 0.1)
		ultimoMira = agora

		local gapAlvo, corAlvo = MIRA.gapParado, MIRA.corParado
		if alvo then
			if aim.parte == "Head" then
				gapAlvo, corAlvo = MIRA.gapCabeca, MIRA.corCabeca
			else
				gapAlvo, corAlvo = MIRA.gapTronco, MIRA.corTronco
			end
		end

		if alvo ~= alvoAnterior then
			if alvo then pulso = 1 end -- travou num alvo novo
			alvoAnterior = alvo
		end
		pulso = math.max(0, pulso - dt * 5)

		local k = 1 - math.exp(-dt * 14)
		gapAtual = gapAtual + (gapAlvo - gapAtual) * k
		corAtual = corAtual:Lerp(corAlvo, k)
		travadoMix = travadoMix + ((alvo and 1 or 0) - travadoMix) * k

		local g = gapAtual + pulso * 4
		tracoCima.Position = UDim2.fromOffset(0, -g)
		tracoBaixo.Position = UDim2.fromOffset(0, g)
		tracoEsq.Position = UDim2.fromOffset(-g, 0)
		tracoDir.Position = UDim2.fromOffset(g, 0)
		for _, f in ipairs({ tracoCima, tracoBaixo, tracoEsq, tracoDir, ponto }) do
			f.BackgroundColor3 = corAtual
		end

		-- a bolinha muda de verde para a cor do estado quando trava
		local corCirculo = COR_CIRCULO:Lerp(corAtual, travadoMix)
		circulo.BackgroundColor3 = corCirculo
		contorno.Color = corCirculo

		-- vida do alvo
		local hum = alvo and alvo.Character and alvo.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			local fracao = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
			textoVida.Text = tostring(math.ceil(hum.Health))
			textoVida.TextColor3 = Color3.fromRGB(255, 80, 80):Lerp(Color3.fromRGB(90, 255, 120), fracao)
			textoVida.Visible = true
		else
			textoVida.Visible = false
		end
	end

	local function reiniciarMira()
		gapAtual, corAtual = MIRA.gapParado, MIRA.corParado
		travadoMix, pulso, alvoAnterior, ultimoMira = 0, 0, nil, nil
		atualizarMira(nil)
	end
	reiniciarMira()

	local function aplicarTamanho(n)
		aim.tamanho = math.clamp(n, TAMANHO_MIN, TAMANHO_MAX)
		caixaAim.Text = tostring(aim.tamanho)
		circulo.Size = UDim2.fromOffset(aim.tamanho, aim.tamanho)
	end

	caixaAim.FocusLost:Connect(function()
		local n = tonumber(caixaAim.Text)
		aplicarTamanho(n or aim.tamanho)
	end)

	local alvoAtual -- jogador travado no momento
	local raioParams = RaycastParams.new()
	raioParams.FilterType = Enum.RaycastFilterType.Exclude

	local function parteDoAlvo(char)
		if aim.parte == "Head" then
			return char:FindFirstChild("Head")
		end
		return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
	end

	-- Devolve (parte, distância ao centro) se o jogador pode ser mirado agora
	local function podeMirar(p, cam, centro, raio)
		if p == player then return end
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		if aim.ignorarTime and player.Team ~= nil and p.Team == player.Team then return end

		local parte = parteDoAlvo(char)
		if not parte then return end
		local pos = cam:WorldToViewportPoint(parte.Position)
		if pos.Z <= 0 then return end -- atrás da câmera
		local dist = (Vector2.new(pos.X, pos.Y) - centro).Magnitude
		if dist > raio then return end

		if not aim.ignorarParede then
			raioParams.FilterDescendantsInstances = { player.Character }
			local origem = cam.CFrame.Position
			local r = workspace:Raycast(origem, parte.Position - origem, raioParams)
			if r and not r.Instance:IsDescendantOf(char) then return end
		end
		return parte, dist
	end

	-- Depois do script da câmera do Roblox: trava a câmera no alvo todo frame (sem delay)
	RunService:BindToRenderStep("AimbotTravar", Enum.RenderPriority.Camera.Value + 2, function()
		if not estado.aim then return end
		local cam = workspace.CurrentCamera
		if not cam then return end
		local centro = cam.ViewportSize / 2
		local raio = aim.tamanho / 2

		-- mantém o alvo atual enquanto ele puder ser mirado
		local parte
		if alvoAtual then
			parte = podeMirar(alvoAtual, cam, centro, raio)
		end
		-- senão, pega quem está mais perto do centro da bolinha
		if not parte then
			alvoAtual = nil
			local melhor = math.huge
			for _, p in ipairs(Players:GetPlayers()) do
				local pt, dist = podeMirar(p, cam, centro, raio)
				if pt and dist < melhor then
					melhor, parte, alvoAtual = dist, pt, p
				end
			end
		end

		if parte then
			cam.CFrame = CFrame.lookAt(cam.CFrame.Position, parte.Position)
		end
		atualizarMira(parte and alvoAtual or nil)
	end)

	definirAimbot = function(v, tamanho)
		if tamanho then aplicarTamanho(tamanho) end
		estado.aim = v
		alvoAtual = nil
		reiniciarMira()
		circulo.Visible = v
		pintarBotao(botaoAim, "AIMBOT", v)
	end

	botaoAim.MouseButton1Click:Connect(function() definirAimbot(not estado.aim) end)
	botaoAlvo.MouseButton1Click:Connect(function()
		aim.parte = (aim.parte == "Head") and "Torso" or "Head"
		alvoAtual = nil
		pintarOpcoes()
	end)
	botaoParede.MouseButton1Click:Connect(function()
		aim.ignorarParede = not aim.ignorarParede
		pintarOpcoes()
	end)
	botaoTime.MouseButton1Click:Connect(function()
		aim.ignorarTime = not aim.ignorarTime
		alvoAtual = nil
		pintarOpcoes()
	end)
end

------------------------------------------------------------
-- EFEITO DE VELOCIDADE + SUPER VOO (barra de carga, boost, blur, raios vermelhos)
------------------------------------------------------------
do
	local efeitoIntens = 0 -- 0 = nada, 1 = velocidade máxima
	local superMix = 0     -- 0 = normal, 1 = super voo ativo (suavizado)
	local carga = 0        -- 0 a 1: barrinha de carga do super voo
	local flashFeito = false
	local fovBase
	local SUPER_LIMIAR_CARGA = 0.88  -- fração da velocidade máxima para começar a carregar (zona morta)
	local SUPER_LIMIAR_MANTER = 0.7  -- depois de começar, basta ficar acima disso
	local SUPER_TOLERANCIA = 0.4     -- segundos que pode sair da velocidade máxima sem perder a carga
	local semMax = 0                 -- há quanto tempo está fora da velocidade máxima
	local VERMELHO = Color3.fromRGB(255, 40, 40)

	local efeitoGui = Instance.new("ScreenGui")
	efeitoGui.Name = "EfeitoVelocidade"
	efeitoGui.ResetOnSpawn = false
	efeitoGui.IgnoreGuiInset = true
	efeitoGui.DisplayOrder = -1 -- fica atrás do menu
	efeitoGui.Parent = playerGui

	local function quadro(cor)
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = cor
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false
		f.Parent = efeitoGui
		return f
	end
	local efeitoFlash = quadro(Color3.new(1, 1, 1))

	-- Blur (embaçado) do super voo: bem fraquinho, só um soco rápido na hora que liga
	local BLUR_FIXO = 2.5   -- embaçado constante durante o super voo (0 = nenhum)
	local BLUR_SOCO = 6     -- embaçado extra na hora que liga (some em ~0.4s)
	local blur = Instance.new("BlurEffect")
	blur.Name = "BlurSuperVoo"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = game:GetService("Lighting")

	-- Cor: mais saturada/contrastada com leve tom vermelho (dá clima sem esconder a tela)
	local correcao = Instance.new("ColorCorrectionEffect")
	correcao.Name = "CorSuperVoo"
	correcao.Enabled = false
	correcao.Parent = game:GetService("Lighting")

	-- Vinheta de energia: brilho vermelho que pulsa só nas 4 bordas da tela
	local bordas = {}
	do
		local defs = { -- { posição, tamanho, rotação do degradê }
			{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.2), 90 },    -- cima
			{ UDim2.fromScale(0, 0.8), UDim2.fromScale(1, 0.2), 270 }, -- baixo
			{ UDim2.fromScale(0, 0), UDim2.fromScale(0.14, 1), 0 },    -- esquerda
			{ UDim2.fromScale(0.86, 0), UDim2.fromScale(0.14, 1), 180 }, -- direita
		}
		for _, d in ipairs(defs) do
			local f = Instance.new("Frame")
			f.Name = "BordaEnergia"
			f.Position, f.Size = d[1], d[2]
			f.BackgroundColor3 = VERMELHO
			f.BackgroundTransparency = 1
			f.BorderSizePixel = 0
			f.Active = false
			f.Visible = false
			f.Parent = efeitoGui
			local g = Instance.new("UIGradient")
			g.Rotation = d[3]
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(0.4, 0.75),
				NumberSequenceKeypoint.new(1, 1),
			})
			g.Parent = f
			bordas[#bordas + 1] = f
		end
	end

	-- Ondas de choque: anéis que saem do centro quando o super voo liga
	local aneis = {}
	for i = 1, 3 do
		local a = Instance.new("Frame")
		a.Name = "OndaChoque"
		a.AnchorPoint = Vector2.new(0.5, 0.5)
		a.Position = UDim2.fromScale(0.5, 0.5)
		a.Size = UDim2.fromOffset(0, 0)
		a.BackgroundTransparency = 1
		a.BorderSizePixel = 0
		a.Active = false
		a.Visible = false
		a.Parent = efeitoGui
		Instance.new("UICorner", a).CornerRadius = UDim.new(1, 0)
		local s = Instance.new("UIStroke")
		s.Color = i == 1 and Color3.new(1, 1, 1) or VERMELHO
		s.Thickness = 6
		s.Parent = a
		aneis[i] = { frame = a, stroke = s }
	end
	local inicioOnda -- os.clock() de quando o super voo ligou
	local inicioSoco -- idem, para o blur de impacto

	-- Barrinha de carga do super voo
	local barra = Instance.new("Frame")
	barra.Name = "BarraSuper"
	barra.AnchorPoint = Vector2.new(0.5, 0.5)
	barra.Position = UDim2.fromScale(0.5, 0.7)
	barra.Size = UDim2.fromOffset(130, 8)
	barra.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	barra.BackgroundTransparency = 0.4
	barra.BorderSizePixel = 0
	barra.Visible = false
	barra.Parent = efeitoGui
	Instance.new("UICorner", barra).CornerRadius = UDim.new(1, 0)
	local barraContorno = Instance.new("UIStroke")
	barraContorno.Color = Color3.new(1, 1, 1)
	barraContorno.Thickness = 1
	barraContorno.Transparency = 0.4
	barraContorno.Parent = barra
	local enche = Instance.new("Frame")
	enche.Size = UDim2.fromScale(0, 1)
	enche.BackgroundColor3 = Color3.new(1, 1, 1)
	enche.BorderSizePixel = 0
	enche.Parent = barra
	Instance.new("UICorner", enche).CornerRadius = UDim.new(1, 0)

	-- Riscos: brancos (os de índice acima da quantidade base só aparecem no super voo) e vermelhos (só no super voo)
	local riscos = {}
	-- "raio" = fração da distância do centro até a borda da tela naquela direção.
	-- Os riscos só vivem entre RISCO_INI e RISCO_FIM, ou seja, só na borda (o meio fica limpo).
	local RISCO_INI, RISCO_FIM = 0.62, 1.1
	local function reiniciarLinha(l, inicio)
		l.ang = math.random() * math.pi * 2
		l.raio = inicio and (RISCO_INI + math.random() * (RISCO_FIM - RISCO_INI)) or (RISCO_INI + math.random() * 0.08)
		if l.vermelha then
			l.vel = 1.5 + math.random() * 1.0
			l.comp = 0.10 + math.random() * 0.10
			l.grossura = math.random(2, 4)
		else
			l.vel = 0.9 + math.random() * 0.8
			l.comp = 0.06 + math.random() * 0.08
			l.grossura = math.random(1, 2)
		end
	end
	local function criarRisco(vermelha, extra)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = vermelha and VERMELHO or Color3.new(1, 1, 1)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false
		f.Visible = false
		f.Parent = efeitoGui
		-- rastro de cometa: a ponta de fora é forte, o rabo some
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		g.Parent = f
		local l = { frame = f, vermelha = vermelha, extra = extra }
		reiniciarLinha(l, true)
		riscos[#riscos + 1] = l
	end
	for _ = 1, EFEITO_QTD_RISCOS do criarRisco(false, false) end -- brancos normais
	for _ = 1, EFEITO_QTD_RISCOS do criarRisco(false, true) end  -- brancos extras (super)
	for _ = 1, 14 do criarRisco(true, true) end                  -- vermelhos (super)

	local ultimoEfeito
	RunService.RenderStepped:Connect(function()
		local agora = os.clock()
		local dt = math.min(agora - (ultimoEfeito or agora), 0.1)
		ultimoEfeito = agora

		-- alvo: 0 se não está voando ou está devagar; sobe de 0 a 1 perto da velocidade máxima
		local alvo = 0
		local vel, maxima = 0, 0
		if estado.fly and flyBV then
			vel, maxima = flyBV.Velocity.Magnitude, velocidadeFly * MULTIPLICADOR_FLY
		elseif estado.vfly and vBV then
			vel, maxima = vBV.Velocity.Magnitude, velocidadeVFly
		end
		if EFEITO_VELOCIDADE and (flyBV or vBV) then
			if vel >= EFEITO_VEL_MINIMA and maxima > 0 then
				alvo = math.clamp((vel / maxima - 0.7) / 0.3, 0, 1)
			end
		end
		-- o dash do TPTOOL também liga o efeito de velocidade
		if EFEITO_VELOCIDADE and (estado.dashEfeito or 0) > alvo then
			alvo = estado.dashEfeito
		end
		efeitoIntens = efeitoIntens + (alvo - efeitoIntens) * (1 - math.exp(-dt * 4))
		if efeitoIntens < 0.005 then efeitoIntens = 0 end

		-- carga do super voo: depende só de estar na velocidade máxima (analógico/teclado/câmera tanto faz).
		-- Zona morta: para COMEÇAR precisa de >= SUPER_LIMIAR_CARGA da velocidade máxima; depois de começar,
		-- basta ficar >= SUPER_LIMIAR_MANTER. Se sair disso, a carga fica CONGELADA por SUPER_TOLERANCIA segundos
		-- (mudar o ângulo, combinar teclas ou girar a câmera não zera); só depois desse tempo ela esvazia.
		local voando = (estado.fly and flyBV) or (estado.vfly and vBV)
		if not voando or SUPER.habilitado == false then
			SUPER.ativo = false
			carga = 0
			semMax = 0
		else
			local razao = maxima > 0 and (vel / maxima) or 0
			if estado.fly and flyBV and (estado.flyFrente or 0) < 0.5 then razao = 0 end -- super voo só para a frente
			local limiar = (SUPER.ativo or carga > 0.02) and SUPER_LIMIAR_MANTER or SUPER_LIMIAR_CARGA
			if razao >= limiar then
				semMax = 0
			else
				semMax = semMax + dt
			end
			if SUPER.ativo then
				if semMax > SUPER_TOLERANCIA then -- parou de verdade: o super acaba
					SUPER.ativo = false
					carga = 0
				end
			else
				if semMax == 0 then
					carga = math.min(1, carga + dt / SUPER.tempoCarga)
				elseif semMax > SUPER_TOLERANCIA then
					carga = math.max(0, carga - dt * 2)
				end -- dentro da tolerância: a carga só fica parada
				if carga >= 1 then
					SUPER.ativo = true
					-- clarão vermelho/branco na hora que o super voo liga
					efeitoFlash.BackgroundColor3 = Color3.fromRGB(255, 200, 200)
					efeitoFlash.BackgroundTransparency = 0.5
					TweenService:Create(efeitoFlash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
					-- ondas de choque + soco de blur
					inicioOnda, inicioSoco = agora, agora
				end
			end
		end
		superMix = superMix + ((SUPER.ativo and 1 or 0) - superMix) * (1 - math.exp(-dt * 5))
		if superMix < 0.01 then superMix = 0 end

		-- barrinha e texto
		barra.Visible = carga > 0.02 and not SUPER.ativo
		enche.Size = UDim2.fromScale(carga, 1)
		enche.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(VERMELHO, carga)

		-- flash branco rápido quando chega na velocidade máxima
		if efeitoIntens > 0.9 and not flashFeito then
			flashFeito = true
			efeitoFlash.BackgroundColor3 = Color3.new(1, 1, 1)
			efeitoFlash.BackgroundTransparency = 0.55
			TweenService:Create(efeitoFlash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		elseif efeitoIntens < 0.3 then
			flashFeito = false
		end

		-- blur fraquinho (+ soco rápido na hora que liga) e correção de cor
		local soco = 0
		if inicioSoco then
			soco = math.clamp(1 - (agora - inicioSoco) / 0.4, 0, 1)
			if soco <= 0 then inicioSoco = nil end
		end
		blur.Enabled = superMix > 0 or soco > 0
		blur.Size = BLUR_FIXO * superMix + BLUR_SOCO * soco
		correcao.Enabled = superMix > 0
		correcao.Saturation = 0.3 * superMix
		correcao.Contrast = 0.12 * superMix
		correcao.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 225, 225), superMix)

		-- vinheta de energia nas bordas, pulsando
		local pulsoBorda = 0.75 + 0.25 * math.sin(agora * 9)
		for _, b in ipairs(bordas) do
			b.Visible = superMix > 0.01
			b.BackgroundTransparency = 1 - superMix * pulsoBorda
		end

		-- ondas de choque
		for i, a in ipairs(aneis) do
			local t = inicioOnda and (agora - inicioOnda - (i - 1) * 0.15) / 0.7 or 2
			if t >= 0 and t <= 1 then
				local d = efeitoGui.AbsoluteSize.Magnitude * (1 - (1 - t) ^ 2) * 1.05
				a.frame.Visible = true
				a.frame.Size = UDim2.fromOffset(d, d)
				a.stroke.Transparency = t
				a.stroke.Thickness = 2 + 8 * (1 - t)
			else
				a.frame.Visible = false
			end
		end

		-- riscos nas bordas da tela (o meio fica limpo)
		local tela = efeitoGui.AbsoluteSize
		if tela.X <= 0 then tela = workspace.CurrentCamera.ViewportSize end
		local centro = tela / 2
		for _, l in ipairs(riscos) do
			local f = l.frame
			local mostrar
			if l.vermelha then
				mostrar = superMix > 0
			elseif l.extra then
				mostrar = efeitoIntens > 0 and superMix > 0.2
			else
				mostrar = efeitoIntens > 0
			end
			if not mostrar then
				f.Visible = false
			else
				f.Visible = true
				l.raio = l.raio + l.vel * dt * (0.8 + efeitoIntens) * (1 + superMix * 1.5)
				if l.raio > RISCO_FIM then
					reiniciarLinha(l, false)
				end
				local dir = Vector2.new(math.cos(l.ang), math.sin(l.ang))
				-- distância do centro até a borda da tela nessa direção
				local ax, ay = math.abs(dir.X), math.abs(dir.Y)
				local borda = math.min(ax > 0.001 and centro.X / ax or math.huge, ay > 0.001 and centro.Y / ay or math.huge)
				local pos = centro + dir * l.raio * borda
				local entra = math.clamp((l.raio - RISCO_INI) / 0.12, 0, 1)
				local sai = math.clamp((RISCO_FIM - l.raio) / 0.12, 0, 1)
				f.Position = UDim2.fromOffset(pos.X, pos.Y)
				f.Size = UDim2.fromOffset(l.comp * borda * (1 + superMix * 0.6), l.grossura)
				f.Rotation = math.deg(l.ang)
				if l.vermelha then
					f.BackgroundTransparency = 1 - superMix * 0.9 * entra * sai
				else
					f.BackgroundTransparency = 1 - math.min(1, efeitoIntens * 0.7 + superMix * 0.3) * entra * sai
				end
			end
		end
	end)

	-- tremida e FOV: depois do script da câmera do Roblox, senão ele desfaz
	RunService:BindToRenderStep("EfeitoVelocidadeFly", Enum.RenderPriority.Camera.Value + 1, function()
		local cam = workspace.CurrentCamera
		if not cam then return end
		if efeitoIntens > 0.01 then
			if not fovBase then fovBase = cam.FieldOfView end
			cam.FieldOfView = fovBase + EFEITO_FOV_EXTRA * efeitoIntens + SUPER.fov * superMix + (estado.dashFov or 0)

			local t = os.clock() * (35 + 25 * superMix)
			local amp = EFEITO_TREMIDA * efeitoIntens + SUPER.tremida * superMix + (estado.dashTremida or 0)
			local nx, ny, nr = math.noise(t, 0, 0), math.noise(0, t, 0), math.noise(0, 0, t)
			cam.CFrame = cam.CFrame
				* CFrame.new(nx * 0.25 * amp, ny * 0.25 * amp, 0)
				* CFrame.Angles(ny * 0.012 * amp, nx * 0.012 * amp, nr * 0.02 * amp)
		elseif fovBase then
			cam.FieldOfView = fovBase
			fovBase = nil
		end
	end)
end

local ultimoFly
local ultimoYawFly -- última direção horizontal válida
local function atualizarFly()
	if not estado.fly then
		if flyBV then pararFly() end
		estado.poseW, estado.flyFrente, estado.flyOcioso = nil, 0, 0
		ultimoFly = nil
		ultimoYawFly = nil
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

	local agora = os.clock()
	local dt = math.min(agora - (ultimoFly or agora), 0.1)
	ultimoFly = agora

	local dir, flat = direcaoDeVoo(hum)

	-- Velocidade com aceleração suave (não arranca nem para de uma vez)
	-- o super voo só vale voando para a FRENTE
	local alvoVel = dir * velocidadeFly * MULTIPLICADOR_FLY * ((SUPER.ativo and (estado.flyFrente or 0) > 0.5) and SUPER.mult or 1)
	-- PARADO: flutua subindo e descendo bem de leve (só quando você não está se movendo)
	local BOB_ALTURA, BOB_PERIODO = 0.7, 3 -- studs de sobe-e-desce e segundos de cada ida e volta
	local freqBob = 2 * math.pi / BOB_PERIODO
	alvoVel = alvoVel + Vector3.new(0, BOB_ALTURA * freqBob * math.cos(agora * freqBob) * (estado.flyOcioso or 0), 0)
	flyBV.Velocity = flyBV.Velocity:Lerp(alvoVel, 1 - math.exp(-dt * (SUPER.ativo and 12 or 8)))

	-- Para que lado você está indo em relação ao corpo: frente, trás, esquerda ou direita.
	-- Subir/descer sozinho conta como parado (pose de herói flutuando).
	local w = estado.poseW
	if not w then
		w = { f = 0, t = 0, e = 0, d = 0 }
		estado.poseW = w
	end
	local baseYaw = ultimoYawFly or (flat.Magnitude > 0.001 and flat.Unit or nil)
	local aF, aT, aE, aD = 0, 0, 0, 0
	local mover = hum.MoveDirection
	if baseYaw and mover.Magnitude > 0.05 then
		local fr = mover:Dot(baseYaw)
		local la = mover:Dot(baseYaw:Cross(Vector3.yAxis))
		local function zona(x) return math.clamp((math.abs(x) - 0.25) / 0.35, 0, 1) end
		if fr > 0 then aF = zona(fr) else aT = zona(fr) end
		if la < 0 then aE = zona(la) else aD = zona(la) end
	end
	local kPose = 1 - math.exp(-dt * 6)
	w.f = w.f + (aF - w.f) * kPose
	w.t = w.t + (aT - w.t) * kPose
	w.e = w.e + (aE - w.e) * kPose
	w.d = w.d + (aD - w.d) * kPose
	estado.flyOcioso = (estado.flyOcioso or 0) + ((dir.Magnitude < 0.05 and 1 or 0) - (estado.flyOcioso or 0)) * kPose
	poseMov = math.min(1, w.f + w.t + w.e + w.d) -- usado só pelo R6
	estado.flyFrente = w.f

	local look = workspace.CurrentCamera.CFrame.LookVector
	local pitch = math.asin(math.clamp(look.Y, -1, 1))

	-- O corpo acompanha a câmera SEMPRE (mesmo parado):
	-- olhou pra baixo = deita de barriga pra baixo; olhou pra cima = deita de barriga pra cima
	local inclinacao = pitch * GANHO_INCLINACAO
	if POSE_HEROI then
		-- ao se mover, ainda "deita" mais (pose de herói), mantendo a liberdade de cima/baixo
		-- frente: deita de barriga pra baixo; trás: deita de costas; lados: rola (abaixo)
		inclinacao = math.clamp(inclinacao - math.rad(75) * w.f + math.rad(70) * w.t, -math.rad(150), math.rad(110))
	end
	local rolagem = POSE_HEROI and math.rad(80) * (w.e - w.d) or 0 -- esquerda: cabeça pra esquerda

	-- Direção horizontal (yaw): guarda a última boa, pois olhando reto pra baixo/cima ela some
	local camCF = workspace.CurrentCamera.CFrame
	local planoFrente = Vector3.new(look.X, 0, look.Z)
	if planoFrente.Magnitude < 0.05 then
		-- olhando quase vertical: usa o "topo" da câmera para saber pra onde está virada
		local up = camCF.UpVector
		planoFrente = Vector3.new(up.X, 0, up.Z) * (look.Y > 0 and -1 or 1)
	end
	if planoFrente.Magnitude > 0.001 then
		ultimoYawFly = planoFrente.Unit
	end

	if ultimoYawFly then
		local yaw = CFrame.lookAt(Vector3.zero, ultimoYawFly)
		local alvo = CFrame.new(raiz.Position) * yaw * CFrame.Angles(inclinacao, 0, 0) * CFrame.Angles(0, 0, rolagem)
		flyBG.CFrame = flyBG.CFrame:Lerp(alvo, 1 - math.exp(-dt * 10))
	end

	poseLean = inclinacao
end

-- A pose é aplicada no Heartbeat (depois das animações do Roblox), senão elas sobrescrevem a pose
RunService.Heartbeat:Connect(function()
	if not (POSE_HEROI and estado.fly and flyBV) then return end
	local raiz, hum = pegarPersonagem()
	if raiz and not hum.SeatPart then
		aplicarPoseFly(raiz.Parent, hum, poseLean)
	end
end)

local function definirFly(v)
	estado.fly = v
	pintarBotao(botaoFly, "FLY", v)
	atualizarBotaoVertical()
end
botaoFly.MouseButton1Click:Connect(function() definirFly(not estado.fly) end)

local atualizarSetasVFly, atualizarVFly, definirVFly, pararVFly
do -- bloco (libera variáveis locais)
------------------------------------------------------------
-- VFLY (voar com veículo enquanto sentado)
------------------------------------------------------------
local ultimoVFly

-- SETAS NA TELA (para jogos em que o analógico não controla o veículo):
-- esquerda = frente / trás / lados, direita = subir / descer. Segure para mover; arraste o "≡" para mudar de lugar.
local setasV = { frente = false, tras = false, esq = false, dir = false, sobe = false, desce = false }
local clusterMovV, clusterAltV
do
	local COR_SETA = Color3.fromRGB(30, 30, 38)
	local COR_SETA_ON = Color3.fromRGB(60, 200, 110)

	local function criarCluster(titulo, ancora, posicao, largura)
		local c = Instance.new("Frame")
		c.Name = "Setas" .. titulo
		c.AnchorPoint = ancora
		c.Position = posicao
		c.Size = UDim2.fromOffset(largura, 136)
		c.BackgroundTransparency = 1
		c.Visible = false
		c.ZIndex = 8
		c.Parent = gui

		local alca = Instance.new("TextButton")
		alca.Size = UDim2.new(1, 0, 0, 20)
		alca.BackgroundColor3 = COR_SETA
		alca.BackgroundTransparency = 0.35
		alca.Text = "≡ " .. titulo
		alca.TextColor3 = Color3.new(1, 1, 1)
		alca.Font = Enum.Font.GothamBold
		alca.TextSize = 12
		alca.AutoButtonColor = false
		alca.ZIndex = 8
		alca.Parent = c
		Instance.new("UICorner", alca).CornerRadius = UDim.new(0, 8)
		tornarMovel(alca, c)
		return c
	end

	local function criarSeta(cluster, texto, x, y, w, chave)
		local b = Instance.new("TextButton")
		b.Name = "Seta_" .. chave
		b.Position = UDim2.fromOffset(x, 26 + y)
		b.Size = UDim2.fromOffset(w, 54)
		b.BackgroundColor3 = COR_SETA
		b.BackgroundTransparency = 0.35
		b.Text = texto
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 18
		b.AutoButtonColor = false
		b.ZIndex = 8
		b.Parent = cluster
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 12)
		local contorno = Instance.new("UIStroke")
		contorno.Color = Color3.new(1, 1, 1)
		contorno.Transparency = 0.5
		contorno.Thickness = 1.2
		contorno.Parent = b

		local function soltar()
			setasV[chave] = false
			b.BackgroundColor3 = COR_SETA
			b.BackgroundTransparency = 0.35
		end
		b.InputBegan:Connect(function(input)
			local tipo = input.UserInputType
			if tipo ~= Enum.UserInputType.MouseButton1 and tipo ~= Enum.UserInputType.Touch then return end
			setasV[chave] = true
			b.BackgroundColor3 = COR_SETA_ON
			b.BackgroundTransparency = 0.15
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then soltar() end
			end)
		end)
		return b
	end

	clusterMovV = criarCluster("VFLY", Vector2.new(0, 0), UDim2.new(0, 16, 0.5, -68), 174)
	criarSeta(clusterMovV, "▲", 60, 0, 54, "frente")
	criarSeta(clusterMovV, "◀", 0, 60, 54, "esq")
	criarSeta(clusterMovV, "▼", 60, 60, 54, "tras")
	criarSeta(clusterMovV, "▶", 120, 60, 54, "dir")

	clusterAltV = criarCluster("ALTURA", Vector2.new(1, 0), UDim2.new(1, -16, 0.5, -68), 84)
	criarSeta(clusterAltV, "▲\nSOBE", 0, 0, 84, "sobe")
	criarSeta(clusterAltV, "▼\nDESCE", 0, 60, 84, "desce")
end

function atualizarSetasVFly()
	clusterMovV.Visible = estado.vfly
	clusterAltV.Visible = estado.vfly
	if not estado.vfly then
		for k in pairs(setasV) do setasV[k] = false end
	end
end

function pararVFly()
	ultimoVFly = nil
	if vBV then vBV:Destroy() vBV = nil end
	if vBG then vBG:Destroy() vBG = nil end
end

function atualizarVFly()
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

	-- soma o que vem das setas da tela (frente/trás seguem a câmera, lados e altura são retos)
	local cam = workspace.CurrentCamera
	local extra = Vector3.zero
	local fb = (setasV.frente and 1 or 0) - (setasV.tras and 1 or 0)
	if fb ~= 0 then extra = extra + cam.CFrame.LookVector * fb end
	local lado = (setasV.dir and 1 or 0) - (setasV.esq and 1 or 0)
	if lado ~= 0 then
		local r = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
		if r.Magnitude > 0.001 then extra = extra + r.Unit * lado end
	end
	local alt = (setasV.sobe and 1 or 0) - (setasV.desce and 1 or 0)
	if alt ~= 0 then extra = extra + Vector3.new(0, alt, 0) end
	if extra.Magnitude > 0 then
		dir = dir + extra
		if dir.Magnitude > 1 then dir = dir.Unit end
	end

	-- aceleração suave e SUPER VOO, igual ao FLY
	local agora = os.clock()
	local dt = math.min(agora - (ultimoVFly or agora), 0.1)
	ultimoVFly = agora
	local alvoVel = dir * velocidadeVFly * (SUPER.ativo and SUPER.mult or 1)
	vBV.Velocity = vBV.Velocity:Lerp(alvoVel, 1 - math.exp(-dt * (SUPER.ativo and 12 or 8)))

	-- Alinha a frente do assento com a direção da câmera
	if flat.Magnitude > 0.001 then
		local alvoAssento = CFrame.lookAt(seat.Position, seat.Position + flat)
		local deslocamento = seat.CFrame:ToObjectSpace(raiz.CFrame)
		vBG.CFrame = alvoAssento * deslocamento
	end
end

function definirVFly(v)
	estado.vfly = v
	pintarBotao(botaoVFly, "VFLY", v)
	atualizarSetasVFly()
	atualizarBotaoVertical()
end
botaoVFly.MouseButton1Click:Connect(function() definirVFly(not estado.vfly) end)

end -- fim do bloco (libera variáveis locais)
local atualizarSwim, definirSwim, pararSwim, swimBV
do -- bloco (libera variáveis locais)
------------------------------------------------------------
-- SWIM (nadar no ar)
------------------------------------------------------------
-- (declarado antes)
local ultimoSwim
local swimHum        -- humanoid que está com os estados travados em "nadando"
local swimEstados    -- [estado] = estava ligado antes? (para devolver ao normal)

-- Trava o humanoid em "nadando": desliga os outros estados UMA vez, assim o Roblox não
-- fica trocando nadando <-> caindo a cada frame (era isso que fazia a animação travar).
local function travarEstadoNado(hum)
	if swimHum == hum then return end
	swimHum = hum
	swimEstados = {}
	for _, est in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
		if est ~= Enum.HumanoidStateType.Swimming and est ~= Enum.HumanoidStateType.Dead
			and est ~= Enum.HumanoidStateType.None and est ~= Enum.HumanoidStateType.Physics then
			local ok, ligado = pcall(function() return hum:GetStateEnabled(est) end)
			if ok then
				swimEstados[est] = ligado
				pcall(function() hum:SetStateEnabled(est, false) end)
			end
		end
	end
	hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
	hum:ChangeState(Enum.HumanoidStateType.Swimming)
end

local function destravarEstadoNado()
	local hum = swimHum
	if hum and swimEstados then
		for est, ligado in pairs(swimEstados) do
			pcall(function() hum:SetStateEnabled(est, ligado) end)
		end
		if hum.Parent and hum:GetState() == Enum.HumanoidStateType.Swimming then
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end
	swimHum, swimEstados = nil, nil
end

function pararSwim()
	if swimBV then swimBV:Destroy() swimBV = nil end
	ultimoSwim = nil
	destravarEstadoNado()
end

function atualizarSwim()
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

	-- Estado de natação travado (toca a animação de nadar sem ficar piscando)
	travarEstadoNado(hum)
	if hum:GetState() ~= Enum.HumanoidStateType.Swimming then
		hum:ChangeState(Enum.HumanoidStateType.Swimming)
	end

	-- Aceleração suave, como a água de verdade: não arranca nem para de uma vez
	local agora = os.clock()
	local dt = math.min(agora - (ultimoSwim or agora), 0.1)
	ultimoSwim = agora
	local dir = direcaoDeVoo(hum)
	local taxa = dir.Magnitude > 0.05 and 6 or 4
	swimBV.Velocity = swimBV.Velocity:Lerp(dir * velocidadeSwim, 1 - math.exp(-dt * taxa))
end

function definirSwim(v)
	estado.swim = v
	pintarBotao(botaoSwim, "SWIM", v)
	atualizarBotaoVertical()
end
botaoSwim.MouseButton1Click:Connect(function() definirSwim(not estado.swim) end)

end -- fim do bloco (libera variáveis locais)
------------------------------------------------------------
-- EFEITO DE ÁGUA DO SWIM (tela azulada, bolhas subindo, balanço suave) — sem os riscos brancos
------------------------------------------------------------
do
	local agua = 0   -- 0 = fora d'água, 1 = dentro d'água (suavizado)
	local entrada = 0 -- "splash" ao entrar, decai sozinho
	local antes = false

	local aguaGui = Instance.new("ScreenGui")
	aguaGui.Name = "EfeitoAgua"
	aguaGui.ResetOnSpawn = false
	aguaGui.IgnoreGuiInset = true
	aguaGui.DisplayOrder = -2
	aguaGui.Parent = playerGui

	-- Tom azul: mais claro em cima, mais fundo embaixo
	local tinta = Instance.new("Frame")
	tinta.Size = UDim2.fromScale(1, 1)
	tinta.BackgroundColor3 = Color3.new(1, 1, 1)
	tinta.BackgroundTransparency = 1
	tinta.BorderSizePixel = 0
	tinta.Active = false
	tinta.Parent = aguaGui
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(110, 200, 255), Color3.fromRGB(10, 70, 140))
	grad.Parent = tinta

	-- Clarão ao entrar na água
	local splash = Instance.new("Frame")
	splash.Size = UDim2.fromScale(1, 1)
	splash.BackgroundColor3 = Color3.fromRGB(200, 235, 255)
	splash.BackgroundTransparency = 1
	splash.BorderSizePixel = 0
	splash.Active = false
	splash.Parent = aguaGui

	local blur = Instance.new("BlurEffect")
	blur.Name = "BlurAgua"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = game:GetService("Lighting")

	-- Bolhas subindo
	local bolhas = {}
	local function reiniciarBolha(b, inicio)
		b.x = math.random()
		b.y = inicio and math.random() or (1.05 + math.random() * 0.1)
		b.tam = math.random(6, 22)
		b.vel = 0.10 + math.random() * 0.18 -- telas por segundo
		b.balanco = 0.01 + math.random() * 0.025
		b.fase = math.random() * math.pi * 2
		b.freq = 1 + math.random() * 1.5
	end
	for i = 1, 24 do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false
		f.Visible = false
		f.Parent = aguaGui
		Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
		local c = Instance.new("UIStroke")
		c.Color = Color3.new(1, 1, 1)
		c.Thickness = 1.2
		c.Transparency = 1
		c.Parent = f
		local b = { frame = f, contorno = c }
		reiniciarBolha(b, true)
		bolhas[i] = b
	end

	local ultimo
	RunService.RenderStepped:Connect(function()
		local agora = os.clock()
		local dt = math.min(agora - (ultimo or agora), 0.1)
		ultimo = agora

		local ligado = estado.swim and not estado.fly and swimBV ~= nil and MENU.cfg.swimEfeitos
		if ligado and not antes then
			-- acabou de entrar na água: splash + explosão de bolhas
			entrada = 1
			splash.BackgroundTransparency = 0.45
			TweenService:Create(splash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
			for _, b in ipairs(bolhas) do
				b.y = 0.9 + math.random() * 0.25
			end
		end
		antes = ligado

		agua = agua + ((ligado and 1 or 0) - agua) * (1 - math.exp(-dt * 3))
		if agua < 0.01 then agua = 0 end
		entrada = entrada * math.exp(-dt * 1.6)

		tinta.BackgroundTransparency = 1 - 0.16 * agua
		blur.Enabled = agua > 0
		blur.Size = (1 * agua) + 4 * entrada

		local tela = aguaGui.AbsoluteSize
		if tela.X <= 0 then tela = workspace.CurrentCamera.ViewportSize end
		local t = agora

		for _, b in ipairs(bolhas) do
			local f = b.frame
			if agua <= 0 then
				f.Visible = false
				b.contorno.Transparency = 1
			else
				f.Visible = true
				b.y = b.y - b.vel * dt * (1 + entrada * 2.5)
				if b.y < -0.08 then reiniciarBolha(b, false) end
				local x = b.x + math.sin(t * b.freq + b.fase) * b.balanco
				f.Position = UDim2.fromOffset(x * tela.X, b.y * tela.Y)
				f.Size = UDim2.fromOffset(b.tam, b.tam)
				f.BackgroundTransparency = 1 - agua * 0.12
				b.contorno.Transparency = 1 - agua * 0.55
			end
		end
	end)

	-- Balanço bem leve da câmera, como flutuando (depois do script da câmera do Roblox)
	-- O balanço do frame anterior é desfeito ANTES do script da câmera rodar; senão o Roblox lê a
	-- câmera já balançada e o balanço se soma a cada frame (a câmera fica "nadando" sozinha).
	local balancoAnterior = CFrame.new()
	RunService:BindToRenderStep("EfeitoAguaSwimDesfaz", Enum.RenderPriority.First.Value, function()
		local cam = workspace.CurrentCamera
		if cam and balancoAnterior ~= CFrame.new() then
			cam.CFrame = cam.CFrame * balancoAnterior:Inverse()
		end
		balancoAnterior = CFrame.new()
	end)
	RunService:BindToRenderStep("EfeitoAguaSwim", Enum.RenderPriority.Camera.Value + 1, function()
		if agua <= 0.01 then return end
		local cam = workspace.CurrentCamera
		if not cam then return end
		local t = os.clock()
		local balanco = CFrame.new(0, math.sin(t * 1.2) * 0.08 * agua, 0)
			* CFrame.Angles(math.sin(t * 0.8) * 0.004 * agua, 0, math.sin(t * 1.0) * 0.012 * agua)
		cam.CFrame = cam.CFrame * balanco
		balancoAnterior = balanco
	end)
end

local definirNoclip
do -- bloco (libera variáveis locais)
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

function definirNoclip(v)
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

end -- fim do bloco (libera variáveis locais)
------------------------------------------------------------
-- EFEITOS DO NOCLIP: só as partes que o personagem encosta ou atravessa ficam transparentes
-- (e voltam ao normal quando você se afasta). Personagem meio transparente enquanto ligado.
-- Tudo só no seu cliente: ninguém mais vê, e o mapa de verdade não muda.
------------------------------------------------------------
do
	local TRANSP_PAREDE = 0.75     -- 0 = normal, 1 = invisível (nas partes que você toca)
	local TRANSP_PERSONAGEM = 0.35 -- personagem meio transparente com o noclip ligado (0 = normal)
	local MARGEM = 1.2             -- studs além do corpo: pega também o que está encostando
	local INTERVALO_BUSCA = 0.04   -- segundos entre uma checagem e outra

	local afetadas = {}  -- [BasePart] = nível 0..1 (quanto já ficou transparente)
	local perto = {}     -- [BasePart] = true se está encostando/atravessando agora
	local nivelPersonagem = 0
	local ultimaBusca = 0
	local xrayAntes = false

	-- Sonda invisível do tamanho do corpo: GetPartsInPart usa a geometria real, então só
	-- volta o que de fato encosta em você (não a parede inteira do outro lado do mapa)
	local sonda = Instance.new("Part")
	sonda.Name = "SondaNoclip"
	sonda.Anchored = true
	sonda.CanCollide = false
	sonda.CanQuery = false
	sonda.CanTouch = false
	sonda.CastShadow = false
	sonda.Transparency = 1
	sonda.Size = Vector3.new(4, 6, 4)
	sonda.Parent = workspace.CurrentCamera

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local function ehDeJogador(parte)
		local m = parte:FindFirstAncestorOfClass("Model")
		return m ~= nil and m:FindFirstChildOfClass("Humanoid") ~= nil
	end

	RunService.RenderStepped:Connect(function(dt)
		local char = player.Character
		local raiz = char and char:FindFirstChild("HumanoidRootPart")
		local ligado = estado.noclip and raiz ~= nil
		local agora = os.clock()

		-- 1) Personagem meio transparente
		nivelPersonagem = nivelPersonagem + ((ligado and 1 or 0) - nivelPersonagem) * (1 - math.exp(-dt * 6))
		if char and (nivelPersonagem > 0.005 or ligado) then
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = MENU.cfg.noclipTransp and nivelPersonagem * TRANSP_PERSONAGEM or 0
				end
			end
		end

		-- 2) Checa o que está encostando/atravessando o corpo (com o Xray ligado o mapa já está transparente)
		if ligado and not estado.xray and MENU.cfg.noclipTransp then
			if agora - ultimaBusca > INTERVALO_BUSCA then
				ultimaBusca = agora
				local cam = workspace.CurrentCamera
				if sonda.Parent ~= cam then sonda.Parent = cam end
				local cf, tam = char:GetBoundingBox()
				-- em alta velocidade (fly) aumenta a margem, para não pular paredes finas entre uma checagem e outra
				local m = MARGEM + math.min(raiz.AssemblyLinearVelocity.Magnitude * 0.04, 5)
				sonda.Size = tam + Vector3.new(m, m, m)
				sonda.CFrame = cf
				params.FilterDescendantsInstances = { char, sonda }
				perto = {}
				for _, parte in ipairs(workspace:GetPartsInPart(sonda, params)) do
					if parte.CanCollide and parte.Transparency < 1 and not ehDeJogador(parte) then
						perto[parte] = true
						if afetadas[parte] == nil then afetadas[parte] = 0 end
					end
				end
			end
		else
			perto = {}
		end

		-- 3) As partes tocadas ficam transparentes / voltam ao normal aos poucos
		if estado.xray then
			-- o Xray cuida da transparência do mapa: solta o que o Noclip tinha mexido, uma vez só
			if not xrayAntes then
				xrayAntes = true
				for parte in pairs(afetadas) do
					if parte.Parent then parte.LocalTransparencyModifier = 0 end
				end
			end
			afetadas = {}
			perto = {}
		else
			xrayAntes = false
			local subir = 1 - math.exp(-dt * 10) -- fica transparente rápido
			local descer = 1 - math.exp(-dt * 5) -- volta ao normal mais devagar
			for parte, nivel in pairs(afetadas) do
				if not parte.Parent then
					afetadas[parte] = nil
				else
					local alvo = perto[parte] and 1 or 0
					nivel = nivel + (alvo - nivel) * (alvo == 1 and subir or descer)
					if nivel < 0.01 and alvo == 0 then
						parte.LocalTransparencyModifier = 0
						afetadas[parte] = nil
					else
						afetadas[parte] = nivel
						parte.LocalTransparencyModifier = nivel * TRANSP_PAREDE
					end
				end
			end
		end
	end)
end

local DASH_VELOCIDADE_TP, criarLinhaSpawn, iniciarDash, posicionarAoLado, salvarSpawns, spawnsSalvos
do -- bloco (libera variáveis locais)
------------------------------------------------------------
-- SPAWNS (salvar posições, renomear e teleportar)
------------------------------------------------------------
-- (declarado antes)
DASH_VELOCIDADE_TP = 700 -- studs por segundo no teleporte do TP e dos SPAWNS (aumente para ir mais rápido)
-- Abre um painel lateral colado ao menu (à direita; se não couber, à esquerda)
function posicionarAoLado(f)
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

-- Vidro escuro e compacto (mesma linguagem do menu: fundo translúcido + contorno branco fininho)
VIDRO.vermelho = Color3.fromRGB(255, 110, 110)
function VIDRO.vidroSpawn(b, cor, transp)
	b.BackgroundColor3 = cor
	b.BackgroundTransparency = transp
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextStrokeTransparency = 1
	b.BorderSizePixel = 0
	local c = b:FindFirstChildOfClass("UIStroke")
	if not c then
		c = Instance.new("UIStroke")
		c.Parent = b
	end
	c.Color = Color3.new(1, 1, 1)
	c.Thickness = 1
	c.Transparency = 0.6
end
local painelSpawn = Instance.new("Frame")
painelSpawn.Name = "PainelSpawns"
painelSpawn.AnchorPoint = Vector2.new(0, 0.5)
painelSpawn.Position = UDim2.new(0.5, 160, 0.5, 0) -- ao lado do menu principal
painelSpawn.Size = UDim2.new(0, 220, 0, 290) -- compacto (era 270x400)
painelSpawn.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
painelSpawn.BackgroundTransparency = 0.18 -- vidro
painelSpawn.Visible = false
painelSpawn.Parent = gui
Instance.new("UICorner", painelSpawn).CornerRadius = UDim.new(0, 12)
do
	local contornoPainel = Instance.new("UIStroke")
	contornoPainel.Color = Color3.new(1, 1, 1)
	contornoPainel.Thickness = 1.2
	contornoPainel.Transparency = 0.55
	contornoPainel.Parent = painelSpawn
end

local tituloSpawn = Instance.new("TextLabel")
tituloSpawn.Size = UDim2.new(1, 0, 0, 28)
tituloSpawn.BackgroundTransparency = 1
tituloSpawn.Text = "Spawns"
tituloSpawn.TextColor3 = Color3.new(1, 1, 1)
tituloSpawn.Font = Enum.Font.GothamBold
tituloSpawn.TextSize = 15
tituloSpawn.Active = true
tituloSpawn.Parent = painelSpawn
tornarMovel(tituloSpawn, painelSpawn)

local botaoCriarSpawn = Instance.new("TextButton")
botaoCriarSpawn.Position = UDim2.new(0.05, 0, 0, 32)
botaoCriarSpawn.Size = UDim2.new(0.9, 0, 0, 26)
botaoCriarSpawn.Text = "+ Criar spawn aqui"
botaoCriarSpawn.Font = Enum.Font.GothamMedium
botaoCriarSpawn.TextSize = 12
botaoCriarSpawn.AutoButtonColor = true
VIDRO.vidroSpawn(botaoCriarSpawn, VIDRO.corOn, 0.62)
botaoCriarSpawn.Parent = painelSpawn
Instance.new("UICorner", botaoCriarSpawn).CornerRadius = UDim.new(0, 8)

local listaSpawn = Instance.new("ScrollingFrame")
listaSpawn.Position = UDim2.new(0.05, 0, 0, 64)
listaSpawn.Size = UDim2.new(0.9, 0, 1, -72)
listaSpawn.BackgroundTransparency = 1
listaSpawn.BorderSizePixel = 0
listaSpawn.ScrollBarThickness = 3
listaSpawn.CanvasSize = UDim2.new(0, 0, 0, 0)
listaSpawn.AutomaticCanvasSize = Enum.AutomaticSize.Y
listaSpawn.Parent = painelSpawn

local layoutSpawn = Instance.new("UIListLayout")
layoutSpawn.Padding = UDim.new(0, 4)
layoutSpawn.SortOrder = Enum.SortOrder.LayoutOrder
layoutSpawn.Parent = listaSpawn

spawnsSalvos = {} -- [Frame da linha] = { nome = TextBox, cf = CFrame, dist = TextLabel, marca = Part }
local contadorSpawn = 0
local carregandoSpawns = true -- true enquanto lê o arquivo (não regrava no meio)

-- Salvamento em arquivo (só funciona se o seu executor tiver writefile/readfile; senão ignora)
local HttpService = game:GetService("HttpService")
local ARQUIVO_SPAWNS = "spawns_" .. tostring(game.PlaceId) .. ".json"
local function temArquivos()
	return typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
end

function salvarSpawns()
	if carregandoSpawns or not temArquivos() then return end
	local lista = {}
	for linha, d in pairs(spawnsSalvos) do
		lista[#lista + 1] = { ordem = linha.LayoutOrder, n = d.nome.Text, c = { d.cf:GetComponents() } }
	end
	table.sort(lista, function(a, b) return a.ordem < b.ordem end)
	pcall(function()
		writefile(ARQUIVO_SPAWNS, HttpService:JSONEncode(lista))
	end)
end

-- Nome pequeno e discreto flutuando em cima do spawn (só no seu cliente)
local function criarMarcaSpawn(cframeSalvo, texto)
	local cam = workspace.CurrentCamera
	local parte = Instance.new("Part")
	parte.Name = "SpawnMarca"
	parte.Anchored = true
	parte.CanCollide = false
	parte.CanQuery = false
	parte.CanTouch = false
	parte.CastShadow = false
	parte.Transparency = 1
	parte.Size = Vector3.new(0.2, 0.2, 0.2)
	parte.CFrame = CFrame.new(cframeSalvo.Position + Vector3.new(0, 1, 0))
	parte.Parent = cam

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(140, 18)
	bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120 -- só aparece quando você está perto
	bb.LightInfluence = 0
	bb.Adornee = parte
	bb.Parent = parte

	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = texto
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextTransparency = 0.35
	t.TextStrokeTransparency = 0.75
	t.Font = Enum.Font.Gotham
	t.TextSize = 12
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = bb
	return parte, t
end

function criarLinhaSpawn(cframeSalvo, nomeSalvo)
	contadorSpawn += 1

	local linha = Instance.new("Frame")
	linha.Size = UDim2.new(1, -6, 0, 38)
	linha.BackgroundTransparency = 1
	linha.LayoutOrder = contadorSpawn
	linha.Parent = listaSpawn

	-- Nome editável (clique e digite)
	local nome = Instance.new("TextBox")
	nome.Size = UDim2.new(0.56, 0, 0, 25)
	VIDRO.vidroSpawn(nome, Color3.new(1, 1, 1), 0.88)
	nome.Text = nomeSalvo or ("Spawn " .. contadorSpawn)
	nome.PlaceholderText = "nome"
	nome.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
	nome.Font = Enum.Font.GothamMedium
	nome.TextSize = 12
	nome.ClearTextOnFocus = false
	nome.TextTruncate = Enum.TextTruncate.AtEnd
	nome.Parent = linha
	Instance.new("UICorner", nome).CornerRadius = UDim.new(0, 6)

	-- Distância até o spawn (embaixo do nome)
	local dist = Instance.new("TextLabel")
	dist.Position = UDim2.new(0, 3, 0, 26)
	dist.Size = UDim2.new(0.56, -3, 0, 11)
	dist.BackgroundTransparency = 1
	dist.Text = "—"
	dist.TextColor3 = Color3.fromRGB(160, 160, 170)
	dist.Font = Enum.Font.Gotham
	dist.TextSize = 10
	dist.TextXAlignment = Enum.TextXAlignment.Left
	dist.Parent = linha

	local marca, marcaTexto = criarMarcaSpawn(cframeSalvo, nome.Text)

	nome:GetPropertyChangedSignal("Text"):Connect(function()
		marcaTexto.Text = nome.Text
	end)
	nome.FocusLost:Connect(function()
		if nome.Text:gsub("%s", "") == "" then
			nome.Text = "Spawn"
		end
		salvarSpawns()
	end)

	-- Ir até o spawn (voa na velocidade do som, igual ao TP)
	local ir = Instance.new("TextButton")
	ir.Position = UDim2.new(0.585, 0, 0, 0)
	ir.Size = UDim2.new(0.22, 0, 0, 25)
	ir.Text = "IR"
	ir.Font = Enum.Font.GothamBold
	ir.TextSize = 12
	VIDRO.vidroSpawn(ir, VIDRO.corOn, 0.6)
	ir.Parent = linha
	Instance.new("UICorner", ir).CornerRadius = UDim.new(0, 6)

	ir.MouseButton1Click:Connect(function()
		if pegarPersonagem() then
			iniciarDash(cframeSalvo.Position + Vector3.new(0, 3, 0), { velocidade = DASH_VELOCIDADE_TP, forte = true, instantaneo = MENU.cfg.tpInstantaneo })
		end
	end)

	-- Apagar o spawn
	local apagar = Instance.new("TextButton")
	apagar.Position = UDim2.new(0.83, 0, 0, 0)
	apagar.Size = UDim2.new(0.17, 0, 0, 25)
	apagar.Text = "X"
	apagar.Font = Enum.Font.GothamBold
	apagar.TextSize = 12
	VIDRO.vidroSpawn(apagar, VIDRO.vermelho, 0.6)
	apagar.Parent = linha
	Instance.new("UICorner", apagar).CornerRadius = UDim.new(0, 6)

	spawnsSalvos[linha] = { nome = nome, cf = cframeSalvo, dist = dist, marca = marca }

	apagar.MouseButton1Click:Connect(function()
		spawnsSalvos[linha] = nil
		marca:Destroy()
		linha:Destroy()
		salvarSpawns()
	end)

	return nome
end

botaoCriarSpawn.MouseButton1Click:Connect(function()
	local raiz = pegarPersonagem()
	if raiz then
		criarLinhaSpawn(raiz.CFrame)
		salvarSpawns()
	end
end)

-- distâncias atualizadas duas vezes por segundo, só com o painel aberto
local function atualizarDistanciasSpawn()
	local raiz = pegarPersonagem()
	for _, d in pairs(spawnsSalvos) do
		if raiz then
			d.dist.Text = math.floor((d.cf.Position - raiz.Position).Magnitude + 0.5) .. " studs"
		else
			d.dist.Text = "—"
		end
	end
end
task.spawn(function()
	while true do
		task.wait(0.5)
		if painelSpawn.Visible then atualizarDistanciasSpawn() end
	end
end)

-- carrega os spawns salvos deste jogo
do
	if temArquivos() then
		local ok, dados = pcall(function()
			if isfile(ARQUIVO_SPAWNS) then
				return HttpService:JSONDecode(readfile(ARQUIVO_SPAWNS))
			end
		end)
		if ok and type(dados) == "table" then
			for _, item in ipairs(dados) do
				if type(item) == "table" and type(item.c) == "table" and #item.c == 12 then
					local okCF, cf = pcall(function() return CFrame.new(table.unpack(item.c)) end)
					if okCF then
						criarLinhaSpawn(cf, type(item.n) == "string" and item.n or nil)
					end
				end
			end
		end
	end
	carregandoSpawns = false
end

botaoSpawns.MouseButton1Click:Connect(function()
	painelSpawn.Visible = not painelSpawn.Visible
	if painelSpawn.Visible then
		posicionarAoLado(painelSpawn)
		atualizarDistanciasSpawn()
	end
end)

end -- fim do bloco (libera variáveis locais)
local escaparRich
do -- bloco (libera variáveis locais)
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

-- Caixa de busca (filtra a lista enquanto você digita)
local buscaTP = Instance.new("TextBox")
buscaTP.Name = "BuscaTP"
buscaTP.Position = UDim2.new(0.05, 0, 0, 46)
buscaTP.Size = UDim2.new(0.9, 0, 0, 30)
buscaTP.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
buscaTP.PlaceholderText = "Buscar jogador..."
buscaTP.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
buscaTP.Text = ""
buscaTP.TextColor3 = Color3.new(1, 1, 1)
buscaTP.Font = Enum.Font.GothamBold
buscaTP.TextSize = 14
buscaTP.ClearTextOnFocus = false
buscaTP.TextXAlignment = Enum.TextXAlignment.Left
buscaTP.Parent = painelTP
Instance.new("UICorner", buscaTP).CornerRadius = UDim.new(0, 8)
do
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = buscaTP
end
listaTP.Position = UDim2.new(0.05, 0, 0, 84)
listaTP.Size = UDim2.new(0.9, 0, 1, -94)

local botoesTP = {} -- [Player] = TextButton
local avisosTP = {} -- [Player] = instante até quando o aviso "indisponível" fica na tela

function escaparRich(t)
	return (t:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

local function textoBotaoTP(p, dist)
	local d = dist and (math.floor(dist + 0.5) .. " studs") or "—"
	return string.format('<b>%s</b>\n<font size="12" color="rgb(160,160,170)">@%s  ·  %s</font>',
		escaparRich(p.DisplayName), escaparRich(p.Name), d)
end

local function distanciaAte(p)
	local minhaRaiz = pegarPersonagem()
	local char = p.Character
	local alvo = char and char:FindFirstChild("HumanoidRootPart")
	if minhaRaiz and alvo then
		return (alvo.Position - minhaRaiz.Position).Magnitude
	end
	return nil
end

local function atualizarDistanciasTP()
	local agora = os.clock()
	for p, b in pairs(botoesTP) do
		if (avisosTP[p] or 0) <= agora then
			b.Text = textoBotaoTP(p, distanciaAte(p))
		end
	end
end

local function filtrarTP()
	local q = buscaTP.Text:lower()
	for p, b in pairs(botoesTP) do
		local achou = q == "" or p.DisplayName:lower():find(q, 1, true) ~= nil or p.Name:lower():find(q, 1, true) ~= nil
		b.Visible = achou
	end
end
buscaTP:GetPropertyChangedSignal("Text"):Connect(filtrarTP)

local function removerBotaoTP(p)
	local b = botoesTP[p]
	if b then
		b:Destroy()
		botoesTP[p] = nil
		avisosTP[p] = nil
	end
end

local function teleportarTP(p, b)
	local minhaRaiz = pegarPersonagem()
	local char = p.Character
	local alvo = char and char:FindFirstChild("HumanoidRootPart")
	if minhaRaiz and alvo then
		-- voa até o jogador na "velocidade do som" (riscos, tremida, FOV e estrondo na chegada)
		iniciarDash(alvo.Position + Vector3.new(0, 3, 0), { velocidade = DASH_VELOCIDADE_TP, forte = true, instantaneo = MENU.cfg.tpInstantaneo })
	else
		avisosTP[p] = os.clock() + 1.5
		b.Text = "Jogador indisponível"
	end
end

local function criarBotaoTP(p)
	if p == player or botoesTP[p] then return end

	local b = Instance.new("TextButton")
	b.Name = p.DisplayName:lower() .. p.UserId
	b.Size = UDim2.new(1, -6, 0, 46)
	b.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
	b.RichText = true
	b.Text = textoBotaoTP(p, distanciaAte(p))
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.Parent = listaTP
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	do
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = b
	end

	b.MouseButton1Click:Connect(function()
		teleportarTP(p, b)
	end)

	botoesTP[p] = b
end

-- Enter na busca: vai para o primeiro jogador que aparece na lista filtrada
buscaTP.FocusLost:Connect(function(enter)
	if not enter or buscaTP.Text == "" then return end
	local melhorP, melhorB
	for p, b in pairs(botoesTP) do
		if b.Visible and (not melhorB or b.Name < melhorB.Name) then
			melhorP, melhorB = p, b
		end
	end
	if melhorP then
		teleportarTP(melhorP, melhorB)
	end
end)

for _, p in ipairs(Players:GetPlayers()) do
	criarBotaoTP(p)
end
Players.PlayerAdded:Connect(criarBotaoTP)
Players.PlayerRemoving:Connect(removerBotaoTP)

-- distâncias atualizadas duas vezes por segundo, só com o painel aberto
task.spawn(function()
	while true do
		task.wait(0.5)
		if painelTP.Visible then atualizarDistanciasTP() end
	end
end)

botaoTP.MouseButton1Click:Connect(function()
	painelTP.Visible = not painelTP.Visible
	if painelTP.Visible then
		posicionarAoLado(painelTP)
		atualizarDistanciasTP()
	end
end)

end -- fim do bloco (libera variáveis locais)
------------------------------------------------------------
-- VIEW (espectar jogador: a câmera passa a mostrar a visão dele)
------------------------------------------------------------
local iniciarView, pararView
do
	local viewAlvo = nil -- jogador que está sendo observado
	local COR_BTN = Color3.fromRGB(45, 45, 52)
	local COR_BTN_ON = Color3.fromRGB(40, 120, 70)

	-- Painel com a lista de jogadores (igual ao do TP)
	local painelView = Instance.new("Frame")
	painelView.Name = "PainelView"
	painelView.AnchorPoint = Vector2.new(1, 0.5)
	painelView.Position = UDim2.new(0.5, -160, 0.5, 0)
	painelView.Size = UDim2.new(0, 270, 0, 400)
	painelView.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	painelView.Visible = false
	painelView.Parent = gui
	Instance.new("UICorner", painelView).CornerRadius = UDim.new(0, 14)

	local tituloView = Instance.new("TextLabel")
	tituloView.Size = UDim2.new(1, 0, 0, 40)
	tituloView.BackgroundTransparency = 1
	tituloView.Text = "Ver jogador..."
	tituloView.TextColor3 = Color3.new(1, 1, 1)
	tituloView.Font = Enum.Font.GothamBold
	tituloView.TextSize = 20
	tituloView.Active = true
	tituloView.Parent = painelView
	tornarMovel(tituloView, painelView)

	local buscaView = Instance.new("TextBox")
	buscaView.Name = "BuscaView"
	buscaView.Position = UDim2.new(0.05, 0, 0, 46)
	buscaView.Size = UDim2.new(0.9, 0, 0, 30)
	buscaView.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
	buscaView.PlaceholderText = "Buscar jogador..."
	buscaView.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
	buscaView.Text = ""
	buscaView.TextColor3 = Color3.new(1, 1, 1)
	buscaView.Font = Enum.Font.GothamBold
	buscaView.TextSize = 14
	buscaView.ClearTextOnFocus = false
	buscaView.TextXAlignment = Enum.TextXAlignment.Left
	buscaView.Parent = painelView
	Instance.new("UICorner", buscaView).CornerRadius = UDim.new(0, 8)
	do
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = buscaView
	end

	local listaView = Instance.new("ScrollingFrame")
	listaView.Position = UDim2.new(0.05, 0, 0, 84)
	listaView.Size = UDim2.new(0.9, 0, 1, -94)
	listaView.BackgroundTransparency = 1
	listaView.BorderSizePixel = 0
	listaView.ScrollBarThickness = 4
	listaView.CanvasSize = UDim2.new(0, 0, 0, 0)
	listaView.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listaView.Parent = painelView
	local layoutView = Instance.new("UIListLayout")
	layoutView.Padding = UDim.new(0, 6)
	layoutView.SortOrder = Enum.SortOrder.Name
	layoutView.Parent = listaView

	-- Barra de cima enquanto está vendo: ◀ nome ▶ SAIR
	local barra = Instance.new("Frame")
	barra.Name = "BarraView"
	barra.AnchorPoint = Vector2.new(0.5, 0)
	barra.Position = UDim2.new(0.5, 0, 0, 14)
	barra.Size = UDim2.fromOffset(280, 42)
	barra.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	barra.BackgroundTransparency = 0.15
	barra.Visible = false
	barra.ZIndex = 9
	barra.Parent = gui
	Instance.new("UICorner", barra).CornerRadius = UDim.new(0, 12)
	local contornoBarra = Instance.new("UIStroke")
	contornoBarra.Color = Color3.new(1, 1, 1)
	contornoBarra.Transparency = 0.6
	contornoBarra.Thickness = 1.2
	contornoBarra.Parent = barra

	local function botaoBarra(texto, x, w, cor)
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(x, 5)
		b.Size = UDim2.fromOffset(w, 32)
		b.BackgroundColor3 = cor or COR_BTN
		b.Text = texto
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 14
		b.ZIndex = 10
		b.Parent = barra
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
		return b
	end
	local botaoAnt = botaoBarra("◀", 6, 32)
	local botaoProx = botaoBarra("▶", 184, 32)
	local botaoSair = botaoBarra("SAIR", 224, 50, COR_OFF)

	local nomeView = Instance.new("TextLabel")
	nomeView.Position = UDim2.fromOffset(42, 0)
	nomeView.Size = UDim2.fromOffset(138, 42)
	nomeView.BackgroundTransparency = 1
	nomeView.Text = ""
	nomeView.TextColor3 = Color3.new(1, 1, 1)
	nomeView.Font = Enum.Font.GothamBold
	nomeView.TextSize = 14
	nomeView.TextTruncate = Enum.TextTruncate.AtEnd
	nomeView.Active = true -- arrastar o nome move a barra
	nomeView.ZIndex = 10
	nomeView.Parent = barra
	tornarMovel(nomeView, barra)

	local botoesView = {} -- [Player] = TextButton

	local function pintarLista()
		for p, b in pairs(botoesView) do
			b.BackgroundColor3 = (p == viewAlvo) and COR_BTN_ON or COR_BTN
		end
	end

	-- Jogadores (menos você) em ordem de nome
	local function listaOrdenada()
		local lista = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then lista[#lista + 1] = p end
		end
		table.sort(lista, function(a, b) return a.DisplayName:lower() < b.DisplayName:lower() end)
		return lista
	end

	local function meuHumanoid()
		local _, hum = pegarPersonagem()
		if hum then return hum end
		return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	end

	pararView = function()
		if not viewAlvo then return end
		viewAlvo = nil
		local cam = workspace.CurrentCamera
		local hum = meuHumanoid()
		if cam and hum then cam.CameraSubject = hum end
		barra.Visible = false
		botaoView.Text = "ESPECTAR"
		VIDRO.aplicar(botaoView, false)
		pintarLista()
	end

	iniciarView = function(p)
		if not p or p == player or not p.Parent then return false end
		viewAlvo = p
		nomeView.Text = p.DisplayName
		barra.Visible = true
		painelView.Visible = false
		botaoView.Text = "ESPECTAR: " .. p.DisplayName
		VIDRO.aplicar(botaoView, true)
		pintarLista()
		return true
	end

	local function ciclar(passo)
		local lista = listaOrdenada()
		if #lista == 0 then
			pararView()
			return
		end
		local idx = 0
		for i, p in ipairs(lista) do
			if p == viewAlvo then idx = i break end
		end
		iniciarView(lista[(idx - 1 + passo) % #lista + 1])
	end
	botaoAnt.MouseButton1Click:Connect(function() ciclar(-1) end)
	botaoProx.MouseButton1Click:Connect(function() ciclar(1) end)
	botaoSair.MouseButton1Click:Connect(pararView)

	-- Segue o jogador todo frame (depois do script da câmera): cobre ele renascer e você renascer
	RunService:BindToRenderStep("ViewSeguir", Enum.RenderPriority.Camera.Value + 3, function()
		if not viewAlvo then return end
		if not viewAlvo.Parent then
			pararView()
			return
		end
		local cam = workspace.CurrentCamera
		local hum = viewAlvo.Character and viewAlvo.Character:FindFirstChildOfClass("Humanoid")
		if cam and hum and cam.CameraSubject ~= hum then
			cam.CameraSubject = hum
		end
	end)

	-- Lista de jogadores
	local function filtrarView()
		local q = buscaView.Text:lower()
		for p, b in pairs(botoesView) do
			b.Visible = q == "" or p.DisplayName:lower():find(q, 1, true) ~= nil or p.Name:lower():find(q, 1, true) ~= nil
		end
	end
	buscaView:GetPropertyChangedSignal("Text"):Connect(filtrarView)

	local function criarBotaoView(p)
		if p == player or botoesView[p] then return end
		local b = Instance.new("TextButton")
		b.Name = p.DisplayName:lower() .. p.UserId
		b.Size = UDim2.new(1, -6, 0, 46)
		b.BackgroundColor3 = (p == viewAlvo) and COR_BTN_ON or COR_BTN
		b.RichText = true
		b.Text = string.format('<b>%s</b>\n<font size="12" color="rgb(160,160,170)">@%s</font>',
			escaparRich(p.DisplayName), escaparRich(p.Name))
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 14
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.TextTruncate = Enum.TextTruncate.AtEnd
		b.Parent = listaView
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = b
		b.MouseButton1Click:Connect(function() iniciarView(p) end)
		botoesView[p] = b
	end

	for _, p in ipairs(Players:GetPlayers()) do criarBotaoView(p) end
	Players.PlayerAdded:Connect(criarBotaoView)
	Players.PlayerRemoving:Connect(function(p)
		local b = botoesView[p]
		if b then
			b:Destroy()
			botoesView[p] = nil
		end
		if p == viewAlvo then pararView() end
	end)

	-- Botão VIEW do menu: desligado abre a lista; ligado volta para a sua câmera
	botaoView.MouseButton1Click:Connect(function()
		if viewAlvo then
			pararView()
		else
			painelView.Visible = not painelView.Visible
			if painelView.Visible then posicionarAoLado(painelView) end
		end
	end)
end

------------------------------------------------------------
-- XRAY (mapa semitransparente, só no seu cliente) com onda de revelação e SONAR
------------------------------------------------------------
-- Ao ligar: uma onda parte de você e o mapa vai ficando transparente conforme ela passa (com fade suave).
-- Ligado: a cada poucos segundos um sonar (anel de energia) sai de você e "acende" por um instante
-- as paredes por onde passa. Ao desligar: o mapa volta ao normal aos poucos.
local transparenciaXray = 0.6
local definirXray
local aplicarCaixaXray

do
	local RAIO_ONDA = 450        -- studs: até onde a onda de revelação vai
	local DURACAO_ONDA = 1.1     -- segundos que a onda leva para chegar lá (sai rápido e desacelera)
	local SONAR = MENU.sonar     -- intervalo / alcance / duracao / ligado (ajustáveis na categoria Config)
	local COR_SONAR = Color3.fromRGB(90, 220, 255)
	local TAMANHO_BALDE = 10     -- studs por faixa de distância (organiza as partes pela onda)
	local RAIO_PERTO = 120       -- studs: o que está até aqui entra primeiro (uma busca só)
	local MAX_PERTO = 1500       -- limite de partes dessa busca (evita engasgo em mapa denso)
	local FADE_ENTRADA = 8       -- velocidade do fade de cada parte (maior = mais rápido; 8 = ~0.12s)

	-- Orçamentos de tempo por frame (segundos). Menor = mais suave, mas o mapa demora mais para ficar transparente.
	local ORC_VARREDURA = 0.002  -- varrer o mapa e registrar partes novas
	local ORC_VARREDURA_ONDA = 0.004 -- idem, só enquanto a onda de entrada corre (o mapa acompanha o anel)
	local ORC_FADE = 0.002       -- aplicar o fade de entrada nas partes
	local ORC_TRABALHO = 0.0015  -- reaplicar a caixa / desfazer ao desligar
	local ECO_INTERVALO = 0.12   -- segundos entre as buscas do eco do sonar
	local ECO_MAX_PARTES = 250   -- máximo de partes que cada busca do eco devolve

	-- Tabelas com chave fraca: partes destruídas saem da memória sozinhas (sem vazamento em sessão longa)
	local fraco = { __mode = "k" }
	local partes = setmetatable({}, fraco)    -- [BasePart] = nível 0..1 (quanto já ficou transparente)
	local inicios = setmetatable({}, fraco)   -- [BasePart] = instante em que começou o fade de entrada
	local ecos = setmetatable({}, fraco)      -- [BasePart] = instante em que o sonar passou
	local cachePersonagem = setmetatable({}, fraco) -- [Model] = true (tem Humanoid) ou instante da última checagem

	local ativas = {}     -- lista de partes fazendo o fade de entrada
	local cursorAtivas = 1
	local baldes = {}     -- [faixa] = { partes esperando a onda chegar }
	local aneis = {}      -- anéis/ondas visíveis no momento
	local pendentes = {}  -- fila de instâncias novas para registrar (perto de você + DescendantAdded)
	local iniPend, nPend = 1, 0
	local pilha, nPilha = {}, 0 -- varredura do mapa por pilha (sem montar uma tabela gigante de uma vez)
	local trabalho = nil  -- tarefa em fatias: { lista, i, n, modo = "aplicar" | "zerar" }
	local conexaoAdd
	local fadeGlobal = 1  -- 1 = normal, cai a 0 ao desligar
	local saindo = false
	local ondaAtiva = false
	local raioOnda = 0
	local tOnda = 0       -- progresso da onda de entrada (0..1)
	local baldeAtual = 0
	local origemOnda = Vector3.zero
	local proximoSonar = 0
	local ultimoEco = 0
	local proximoAplicarEco = 0
	local ultimo

	local ecoParams = OverlapParams.new()
	ecoParams.MaxParts = ECO_MAX_PARTES

	-- É parte de personagem/NPC? (com cache por Model: não sobe a árvore inteira para cada parte do mapa)
	local function ehPersonagem(parte)
		local agora = os.clock()
		local m = parte.Parent
		while m and m ~= workspace do
			if m:IsA("Model") then
				local c = cachePersonagem[m]
				if c == true then return true end
				if c == nil or agora - c > 3 then
					if m:FindFirstChildOfClass("Humanoid") then
						cachePersonagem[m] = true
						return true
					end
					cachePersonagem[m] = agora -- "não é personagem", rechecado depois de 3s (o Humanoid pode chegar tarde)
				end
			end
			m = m.Parent
		end
		return false
	end

	-- Anel de sonar no chão: 3 camadas (brilho, linha, rastro) em um disco fino, visível por cima de tudo
	-- (antes era uma casca esférica; vista de dentro ela ficava invisível, por isso a animação "sumia")
	local function criarAnel(origem, tipo, alcance)
		local bloco = Instance.new("Part")
		bloco.Name = "XrayAnel"
		bloco.Anchored = true
		bloco.CanCollide = false
		bloco.CanQuery = false
		bloco.CanTouch = false
		bloco.CastShadow = false
		bloco.Transparency = 1
		bloco.Size = Vector3.new(1, 0.1, 1)
		bloco.CFrame = CFrame.new(origem - Vector3.new(0, 2.6, 0))
		bloco.Parent = workspace.CurrentCamera

		local faixas = {}
		local onda = tipo == "onda"
		local camadas = {
			{ escala = 0.96, espessura = onda and 20 or 12, peso = 0.16, cor = COR_SONAR },                       -- brilho
			{ escala = 0.96, espessura = onda and 6 or 4, peso = onda and 0.95 or 0.7, cor = COR_SONAR },         -- linha
			{ escala = 0.88, espessura = onda and 3 or 2, peso = onda and 0.5 or 0.3, cor = Color3.fromRGB(215, 248, 255) }, -- rastro
		}
		for _, face in ipairs({ Enum.NormalId.Top, Enum.NormalId.Bottom }) do
			local sg = Instance.new("SurfaceGui")
			sg.Face = face
			sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
			sg.CanvasSize = Vector2.new(512, 512)
			sg.AlwaysOnTop = true
			sg.LightInfluence = 0
			sg.Adornee = bloco
			sg.Parent = bloco
			for _, c in ipairs(camadas) do
				local quadro = Instance.new("Frame")
				quadro.AnchorPoint = Vector2.new(0.5, 0.5)
				quadro.Position = UDim2.fromScale(0.5, 0.5)
				quadro.Size = UDim2.fromScale(c.escala, c.escala)
				quadro.BackgroundTransparency = 1
				quadro.Parent = sg
				Instance.new("UICorner", quadro).CornerRadius = UDim.new(0.5, 0)
				local contorno = Instance.new("UIStroke")
				contorno.Color = c.cor
				contorno.Thickness = c.espessura
				contorno.Transparency = 1
				contorno.Parent = quadro
				faixas[#faixas + 1] = { contorno = contorno, peso = c.peso }
			end
		end

		local anel = {
			tipo = tipo, bloco = bloco, faixas = faixas,
			origem = origem, raio = 0, alcance = alcance,
			vel = alcance / SONAR.duracao,
		}
		aneis[#aneis + 1] = anel
		return anel
	end

	local function atualizarAnel(a)
		local prog = math.clamp(a.raio / a.alcance, 0, 1)
		local d = math.clamp(a.raio * 2, 1, 2000)
		a.bloco.Size = Vector3.new(d, 0.1, d)
		a.bloco.CFrame = CFrame.new(a.origem - Vector3.new(0, 2.6, 0))
		local apagar = 1 - prog ^ 2.2 -- some suave perto do alcance máximo
		for _, f in ipairs(a.faixas) do
			f.contorno.Transparency = 1 - f.peso * apagar
		end
	end

	local function destruirAnel(a)
		a.bloco:Destroy()
	end

	local function limparAneis()
		for _, a in ipairs(aneis) do destruirAnel(a) end
		aneis = {}
	end

	-- Aplica o nível de transparência de uma parte (com o fator do eco do sonar, se houver)
	local function aplicarNivel(parte, agora)
		local n = partes[parte]
		if not n or n <= 0 then return end
		local fator = 1
		local t = ecos[parte]
		if t then
			local f = 1 - (agora - t) / 0.6
			if f > 0 then fator = 1 - 0.65 * f end
		end
		local v = n * transparenciaXray * fadeGlobal * fator
		if parte.LocalTransparencyModifier ~= v then -- só escreve se mudou (escrever é o que custa)
			parte.LocalTransparencyModifier = v
		end
	end

	-- Coloca a parte na fila do fade de entrada
	local function ativar(parte)
		if partes[parte] ~= nil and inicios[parte] == nil then
			inicios[parte] = os.clock()
			ativas[#ativas + 1] = parte
		end
	end

	-- Registra uma parte do mapa e decide quando ela entra na onda
	local function registrar(obj)
		if partes[obj] ~= nil or not obj.Parent then return end
		if not obj:IsA("BasePart") or obj:IsA("Terrain") then return end
		if obj.Transparency >= 1 or ehPersonagem(obj) then return end
		local cam = workspace.CurrentCamera
		if cam and obj:IsDescendantOf(cam) then return end -- não afeta os próprios efeitos
		partes[obj] = 0
		if not ondaAtiva then
			ativar(obj)
			return
		end
		local dist = (obj.Position - origemOnda).Magnitude
		if dist <= raioOnda then
			ativar(obj)
		else
			local b = math.floor(dist / TAMANHO_BALDE)
			local lista = baldes[b]
			if not lista then lista = {} baldes[b] = lista end
			lista[#lista + 1] = obj
		end
	end

	-- Fade de entrada em fatias de tempo: nunca gasta mais que ORC_FADE por frame
	local function processarFade(agora)
		local total = #ativas
		if total == 0 then return end
		local limite = os.clock() + ORC_FADE
		local i = cursorAtivas
		local feitos = 0
		while feitos < total and #ativas > 0 do
			if i > #ativas then i = 1 end
			local parte = ativas[i]
			local n0 = partes[parte]
			if n0 == nil or not parte.Parent then
				partes[parte] = nil
				inicios[parte] = nil
				ativas[i] = ativas[#ativas]
				ativas[#ativas] = nil
			else
				local n = math.clamp((agora - inicios[parte]) * FADE_ENTRADA, 0, 1)
				if n ~= n0 then
					partes[parte] = n
					aplicarNivel(parte, agora)
				end
				if n >= 1 then
					ativas[i] = ativas[#ativas]
					ativas[#ativas] = nil
				else
					i += 1
				end
			end
			feitos += 1
			if feitos % 40 == 0 and os.clock() > limite then break end
		end
		cursorAtivas = i
	end

	-- Varredura em fatias: primeiro a fila (o que está perto + o que apareceu), depois o resto do mapa
	local function processarVarredura()
		if nPend == 0 and nPilha == 0 then return end
		local limite = os.clock() + (ondaAtiva and ORC_VARREDURA_ONDA or ORC_VARREDURA)
		local feitos = 0
		while iniPend <= nPend do
			local obj = pendentes[iniPend]
			pendentes[iniPend] = nil
			iniPend += 1
			registrar(obj)
			feitos += 1
			if feitos % 32 == 0 and os.clock() > limite then return end
		end
		if nPend > 0 then pendentes, iniPend, nPend = {}, 1, 0 end

		local cam = workspace.CurrentCamera
		while nPilha > 0 do
			local obj = pilha[nPilha]
			pilha[nPilha] = nil
			nPilha -= 1
			if obj ~= cam and not obj:IsA("Terrain") then
				if obj:IsA("BasePart") then registrar(obj) end
				-- não entra em personagens/NPCs (as partes deles não participam do xray)
				if not (obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid")) then
					local filhos = obj:GetChildren()
					for k = 1, #filhos do
						nPilha += 1
						pilha[nPilha] = filhos[k]
					end
				end
			end
			feitos += 1
			if feitos % 32 == 0 and os.clock() > limite then return end
		end
	end

	-- Tarefa em fatias sobre todas as partes registradas (reaplicar a caixa ou zerar ao sair)
	local function iniciarTrabalho(modo)
		local lista, n = {}, 0
		for parte in pairs(partes) do
			n += 1
			lista[n] = parte
		end
		trabalho = { lista = lista, i = 1, n = n, modo = modo }
	end

	-- devolve true quando a tarefa termina
	local function processarTrabalho(agora)
		local t = trabalho
		if not t then return false end
		local limite = os.clock() + ORC_TRABALHO
		local lista = t.lista
		local i = t.i
		local zerar = t.modo == "zerar"
		while i <= t.n do
			local parte = lista[i]
			if parte.Parent then
				if zerar then
					if parte.LocalTransparencyModifier ~= 0 then parte.LocalTransparencyModifier = 0 end
				else
					aplicarNivel(parte, agora)
				end
			end
			i += 1
			if i % 40 == 0 and os.clock() > limite then break end
		end
		t.i = i
		if i > t.n then
			trabalho = nil
			return true
		end
		return false
	end

	local function finalizarSaida()
		partes = setmetatable({}, fraco)
		inicios = setmetatable({}, fraco)
		ecos = setmetatable({}, fraco)
		ativas, cursorAtivas = {}, 1
		baldes = {}
		trabalho = nil
		limparAneis()
		saindo = false
		fadeGlobal = 1
	end

	local function ligar()
		fadeGlobal = 1
		pendentes, iniPend, nPend = {}, 1, 0
		pilha, nPilha = { workspace }, 1
		ativas, cursorAtivas = {}, 1
		if saindo then
			-- ligou de novo no meio da saída: reaproveita as partes já registradas (sem varredura pesada)
			saindo = false
			for parte in pairs(partes) do
				if parte.Parent and partes[parte] > 0 then
					partes[parte] = 1
					inicios[parte] = nil
				end
			end
			iniciarTrabalho("aplicar")
		end

		local raiz = pegarPersonagem()
		origemOnda = raiz and raiz.Position or workspace.CurrentCamera.CFrame.Position
		ondaAtiva = true
		raioOnda = 0
		tOnda = 0
		baldeAtual = 0
		baldes = {}
		criarAnel(origemOnda, "onda", RAIO_ONDA)
		proximoSonar = os.clock() + DURACAO_ONDA + 1.2

		-- partes novas entram na fila (o registro de verdade acontece aos poucos, no loop)
		conexaoAdd = workspace.DescendantAdded:Connect(function(obj)
			nPend += 1
			pendentes[nPend] = obj
		end)

		-- o que está perto de você entra primeiro na fila (uma busca só, com limite de partes)
		if raiz then
			local params = OverlapParams.new()
			params.MaxParts = MAX_PERTO
			for _, obj in ipairs(workspace:GetPartBoundsInRadius(origemOnda, RAIO_PERTO, params)) do
				nPend += 1
				pendentes[nPend] = obj
			end
		end
	end

	local function desligar()
		if conexaoAdd then
			conexaoAdd:Disconnect()
			conexaoAdd = nil
		end
		ondaAtiva = false
		baldes = {}
		ativas, cursorAtivas = {}, 1
		pendentes, iniPend, nPend = {}, 1, 0
		pilha, nPilha = {}, 0
		trabalho = nil
		limparAneis()
		saindo = true -- o fade de saída roda no loop abaixo, em fatias
	end

	definirXray = function(v)
		if v == estado.xray then return end
		estado.xray = v
		pintarBotao(botaoXray, "XRAY", v)
		if v then ligar() else desligar() end
	end

	aplicarCaixaXray = function()
		local n = tonumber(caixaXray.Text)
		if n then
			transparenciaXray = math.clamp(n, 0, 0.95)
		end
		caixaXray.Text = tostring(transparenciaXray)
		if estado.xray then
			iniciarTrabalho("aplicar") -- reaplica em fatias, sem travar ao mudar o valor
		end
	end

	RunService.RenderStepped:Connect(function()
		local agora = os.clock()
		local dt = math.min(agora - (ultimo or agora), 0.1)
		ultimo = agora
		if not (estado.xray or saindo) then return end

		-- saída suave: o mapa volta ao normal em ~0.4s, feito em fatias
		if saindo then
			fadeGlobal = math.max(0, fadeGlobal - dt * 2.5)
			if fadeGlobal > 0 then
				if not trabalho or trabalho.modo ~= "aplicar" then iniciarTrabalho("aplicar") end
				if processarTrabalho(agora) then trabalho = nil end -- recomeça a próxima passada
			else
				if not trabalho or trabalho.modo ~= "zerar" then iniciarTrabalho("zerar") end
				if processarTrabalho(agora) then finalizarSaida() end
			end
			return
		end

		local raiz = pegarPersonagem()

		-- onda de revelação: libera as partes por faixa de distância
		if ondaAtiva then
			tOnda = math.min(1, tOnda + dt / DURACAO_ONDA)
			raioOnda = RAIO_ONDA * (1 - (1 - tOnda) ^ 2.2) -- ease-out: parte forte e desacelera
			local limite = math.floor(raioOnda / TAMANHO_BALDE)
			for b = baldeAtual, limite do
				local lista = baldes[b]
				if lista then
					for _, parte in ipairs(lista) do ativar(parte) end
					baldes[b] = nil
				end
			end
			baldeAtual = limite + 1
			if tOnda >= 1 then
				for _, lista in pairs(baldes) do -- o que sobrou (muito longe) entra junto no fim
					for _, parte in ipairs(lista) do ativar(parte) end
				end
				baldes = {}
				ondaAtiva = false
			end
		end

		-- trabalho pesado sempre em fatias de tempo (cada um com seu orçamento)
		processarFade(agora)
		processarVarredura()
		processarTrabalho(agora)

		-- sonar periódico saindo de você
		if not ondaAtiva and raiz and SONAR.ligado and agora >= proximoSonar then
			proximoSonar = agora + SONAR.intervalo
			criarAnel(raiz.Position, "sonar", SONAR.alcance)
		end

		-- anéis crescendo; o sonar "acende" as paredes por onde passa
		for i = #aneis, 1, -1 do
			local a = aneis[i]
			if a.tipo == "onda" then
				a.raio = raioOnda
				if not ondaAtiva then
					destruirAnel(a)
					table.remove(aneis, i)
				else
					atualizarAnel(a)
				end
			else
				a.raio = a.raio + a.vel * dt
				if a.raio >= a.alcance then
					destruirAnel(a)
					table.remove(aneis, i)
				else
					atualizarAnel(a)
					if agora - ultimoEco > ECO_INTERVALO then
						ultimoEco = agora
						for _, parte in ipairs(workspace:GetPartBoundsInRadius(a.origem, a.raio + 4, ecoParams)) do
							local n = partes[parte]
							if n and n > 0 then
								local d = (parte.Position - a.origem).Magnitude
								if d >= a.raio - 5 and d <= a.raio + 4 then
									ecos[parte] = agora
								end
							end
						end
					end
				end
			end
		end

		-- eco do sonar: a parte fica um pouco mais visível e volta suave (20 vezes por segundo basta)
		if agora >= proximoAplicarEco then
			proximoAplicarEco = agora + 0.05
			for parte, t in pairs(ecos) do
				if not parte.Parent then
					ecos[parte] = nil
				else
					if agora - t >= 0.6 then ecos[parte] = nil end
					aplicarNivel(parte, agora)
				end
			end
		end
	end)
end

botaoXray.MouseButton1Click:Connect(function() definirXray(not estado.xray) end)
caixaXray.FocusLost:Connect(aplicarCaixaXray)

------------------------------------------------------------
-- TPTOOL (item que leva você até onde você clicar, em um dash rápido)
local definirTPTool
do -- bloco (libera variáveis locais)
------------------------------------------------------------
-- TELEPORTE SUAVE (dash): em vez de aparecer lá de uma vez, você voa rapidinho até o ponto
-- (acelera, passa direto por paredes e freia na chegada), com os riscos de vento e a tremida do fly
local DASH_VELOCIDADE = 220 -- studs por segundo (aumente para ir mais rápido)
-- TPTOOL (o item): false = voa até lá ultra rápido (uns 0.35s) com riscos de vento, tremida, FOV e estrondo na chegada
--                  true = teleporte instantâneo, sem animação nenhuma
-- (o liga/desliga fica em MENU.cfg.tpToolInstantaneo, categoria Config)
local TPTOOL_VELOCIDADE = 3000 -- studs/s (a duração mínima do voo forte é 0.35s)
do
	local conexao, terminarAtual, conColisao

	-- Efeito de "estrondo sonoro" na chegada do TP (só visual, no seu cliente)
	local ESTRONDO_BLUR = 22 -- força do embaçado na chegada (0 = sem blur)
	local fxGui = Instance.new("ScreenGui")
	fxGui.Name = "EfeitoEstrondo"
	fxGui.ResetOnSpawn = false
	fxGui.IgnoreGuiInset = true
	fxGui.DisplayOrder = 50
	fxGui.Parent = playerGui

	local fxFlash = Instance.new("Frame")
	fxFlash.Size = UDim2.fromScale(1, 1)
	fxFlash.BackgroundColor3 = Color3.new(1, 1, 1)
	fxFlash.BackgroundTransparency = 1
	fxFlash.BorderSizePixel = 0
	fxFlash.Active = false
	fxFlash.Parent = fxGui

	local fxBlur = Instance.new("BlurEffect")
	fxBlur.Name = "BlurEstrondo"
	fxBlur.Size = 0
	fxBlur.Enabled = false
	fxBlur.Parent = game:GetService("Lighting")

	local versaoFx = 0

	local function estrondo()
		versaoFx += 1
		local minha = versaoFx
		-- clarão
		fxFlash.BackgroundTransparency = 0.2
		TweenService:Create(fxFlash, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
		-- embaçado que some rápido
		if ESTRONDO_BLUR > 0 then
			fxBlur.Enabled = true
			fxBlur.Size = ESTRONDO_BLUR
			TweenService:Create(fxBlur, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = 0 }):Play()
			task.delay(0.55, function()
				if minha == versaoFx then fxBlur.Enabled = false end
			end)
		end
		-- tranco da câmera: tremida e FOV extras que vão sumindo
		task.spawn(function()
			local t0 = os.clock()
			while minha == versaoFx do
				local k = 1 - (os.clock() - t0) / 0.6
				if k <= 0 then break end
				estado.dashTremida = 4 * k * k
				estado.dashFov = 12 * k
				task.wait()
			end
			if minha == versaoFx then
				estado.dashTremida = 0
				estado.dashFov = 0
			end
		end)
	end

	-- SAÍDA SEGURA: se o corpo termina dentro de uma parede/chão, vai para o ponto livre mais
	-- próximo (antes de a colisão voltar), para nunca ficar preso nem ser arremessado.
	local paramsLivre = OverlapParams.new()
	paramsLivre.FilterType = Enum.RaycastFilterType.Exclude

	local function ocupado(cf, tam, char)
		paramsLivre.FilterDescendantsInstances = { char }
		for _, parte in ipairs(workspace:GetPartBoundsInBox(cf, tam, paramsLivre)) do
			if parte.CanCollide then
				local m = parte:FindFirstAncestorOfClass("Model")
				if not (m and m:FindFirstChildOfClass("Humanoid")) then -- outros jogadores não contam
					return true
				end
			end
		end
		return false
	end

	-- Retorna true se já estava livre ou foi movido para um lugar livre
	local function livrarCorpo(raiz)
		local char = raiz.Parent
		if not char then return true end
		local cf0, tam = char:GetBoundingBox()
		tam = Vector3.new(math.max(tam.X - 1, 1), math.max(tam.Y - 0.8, 1), math.max(tam.Z - 1, 1))
		if not ocupado(cf0, tam, char) then return true end
		local dirs = {
			Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
			Vector3.new(0.7, 0, 0.7), Vector3.new(-0.7, 0, 0.7), Vector3.new(0.7, 0, -0.7), Vector3.new(-0.7, 0, -0.7),
		}
		for dist = 2, 120, 2 do
			local candidatos = { Vector3.new(0, dist, 0) } -- para cima primeiro (sai do chão/teto)
			for _, d in ipairs(dirs) do
				table.insert(candidatos, d * dist)
			end
			for _, delta in ipairs(candidatos) do
				if not ocupado(cf0 + delta, tam, char) then
					raiz.CFrame = raiz.CFrame + delta
					raiz.AssemblyLinearVelocity = Vector3.zero
					return true
				end
			end
		end
		return false
	end

	-- opcoes (opcional): { velocidade = studs/s, forte = true (efeito de velocidade do som + estrondo na chegada),
	--                      instantaneo = true (aparece lá na hora, já em um ponto livre) }
	iniciarDash = function(destino, opcoes)
		opcoes = opcoes or {}
		local velocidade = opcoes.velocidade or DASH_VELOCIDADE
		local forte = opcoes.forte == true
		if terminarAtual then terminarAtual() end
		versaoFx += 1 -- cancela o tranco de câmera de um estrondo anterior
		local raiz, hum = pegarPersonagem()
		if not raiz then return end

		if opcoes.instantaneo then
			raiz.CFrame = CFrame.new(destino) * raiz.CFrame.Rotation
			raiz.AssemblyLinearVelocity = Vector3.zero
			livrarCorpo(raiz) -- se caiu dentro de uma parede, sai para o lado livre
			return
		end

		local char = raiz.Parent
		local origem = raiz.Position
		local dist = (destino - origem).Magnitude
		if dist < 1 then return end

		local dur = math.clamp(dist / velocidade, forte and 0.35 or 0.2, forte and 1.2 or 1.5)
		local inicio = os.clock()
		local plano = Vector3.new(destino.X - origem.X, 0, destino.Z - origem.Z)
		local rotacao = plano.Magnitude > 0.1 and CFrame.lookAt(Vector3.zero, plano.Unit) or raiz.CFrame.Rotation

		-- atravessa o que estiver no caminho; guarda a colisão para devolver no fim.
		-- A colisão é desligada de novo a cada passo da física (o Humanoid religa sozinho em
		-- algumas partes) e também nas partes novas (ferramenta equipada no meio do voo).
		local colisoes = {}
		local function desligarColisao()
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") and d.CanCollide then
					colisoes[d] = true
					d.CanCollide = false
				end
			end
		end
		desligarColisao()
		conColisao = RunService.Stepped:Connect(desligarColisao)
		local plataformaAntes = hum.PlatformStand
		hum.PlatformStand = true

		local function terminar(chegou)
			if conexao then conexao:Disconnect() conexao = nil end
			if conColisao then conColisao:Disconnect() conColisao = nil end
			terminarAtual = nil
			estado.dashEfeito = 0
			if forte then
				if chegou == true then
					estrondo()
				else
					estado.dashTremida = 0
					estado.dashFov = 0
				end
			end
			-- antes de devolver a colisão, tira o corpo de dentro de qualquer parede
			if raiz.Parent then livrarCorpo(raiz) end
			if not estado.noclip then -- com o Noclip ligado, quem manda na colisão é ele
				for d in pairs(colisoes) do
					if d.Parent then d.CanCollide = true end
				end
			end
			if hum.Parent then hum.PlatformStand = plataformaAntes end
		end
		terminarAtual = terminar

		conexao = RunService.RenderStepped:Connect(function()
			if not raiz.Parent then
				terminar()
				return
			end
			local a = math.clamp((os.clock() - inicio) / dur, 0, 1)
			-- acelera no começo e freia no fim
			local e = a < 0.5 and 4 * a * a * a or 1 - ((-2 * a + 2) ^ 3) / 2
			raiz.CFrame = CFrame.new(origem:Lerp(destino, e)) * rotacao
			raiz.AssemblyLinearVelocity = Vector3.zero
			local onda = math.sin(a * math.pi)
			if forte then
				-- chega ao máximo rápido e segura lá (parece que passou do som), com tremida e FOV extras
				estado.dashEfeito = math.min(1, onda * 1.8)
				estado.dashTremida = 1.6 * onda
				estado.dashFov = 18 * onda
			else
				estado.dashEfeito = onda -- intensidade do efeito de velocidade
			end
			if a >= 1 then terminar(true) end
		end)
	end

	-- morreu/respawnou no meio do dash: cancela
	player.CharacterAdded:Connect(function()
		if terminarAtual then terminarAtual() end
	end)
end

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
			local destino = alvo.Position + Vector3.new(0, 3, 0)
			if MENU.cfg.tpToolInstantaneo then
				-- teleporte na hora, mantendo para onde o personagem estava virado (e sem ficar preso)
				iniciarDash(destino, { instantaneo = true })
			else
				iniciarDash(destino, { velocidade = TPTOOL_VELOCIDADE, forte = true })
			end
		end
	end)

	ferramenta.Parent = player:WaitForChild("Backpack")
	tpTool = ferramenta
end

function definirTPTool(v)
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

end -- fim do bloco (libera variáveis locais)
------------------------------------------------------------
-- REJOIN (reentrar no server)
------------------------------------------------------------
local reentrando = false

-- Deixa o script na fila para rodar sozinho assim que você entrar no servidor de novo.
-- Retorna true, ou false + o motivo de não ter sido possível.
local function prepararReexecucao()
	local fila
	if typeof(queue_on_teleport) == "function" then
		fila = queue_on_teleport
	elseif syn and typeof(syn.queue_on_teleport) == "function" then
		fila = syn.queue_on_teleport
	elseif fluxus and typeof(fluxus.queue_on_teleport) == "function" then
		fila = fluxus.queue_on_teleport
	end
	if not fila then return false, "o executor não tem queue_on_teleport" end

	local carregar
	if URL_SCRIPT ~= "" then
		carregar = string.format("loadstring(game:HttpGet(%q))()", URL_SCRIPT)
	elseif ARQUIVO_SCRIPT ~= "" then
		if not (typeof(isfile) == "function" and isfile(ARQUIVO_SCRIPT)) then
			return false, "arquivo não encontrado: " .. ARQUIVO_SCRIPT
		end
		carregar = string.format("loadstring(readfile(%q))()", ARQUIVO_SCRIPT)
	else
		return false, "preencha ARQUIVO_SCRIPT ou URL_SCRIPT no começo do script"
	end

	local codigo = "if not game:IsLoaded() then game.Loaded:Wait() end task.wait(1) " .. carregar
	local ok = pcall(fila, codigo)
	if not ok then return false, "falha ao enfileirar" end
	return true
end

local function fazerRejoin()
	if reentrando then return end
	reentrando = true
	botaoRejoin.Text = "Reentrando..."

	local okFila, motivo = prepararReexecucao()
	if not okFila then
		warn("Rejoin sem reexecução: " .. tostring(motivo))
	end

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
		botaoRejoin.Text = "REENTRAR"
		reentrando = false
	end
	return okFila, motivo
end
botaoRejoin.MouseButton1Click:Connect(fazerRejoin)

-- Se o teleporte falhar depois de iniciado, libera o botão de novo
TeleportService.TeleportInitFailed:Connect(function()
	botaoRejoin.Text = "REENTRAR"
	reentrando = false
end)

------------------------------------------------------------
-- SHIFT LOCK (força o shift lock, mesmo em jogos que não têm)
------------------------------------------------------------
local definirShiftLock, atualizarShiftLock
do
	local COR_BRANCO = Color3.fromRGB(255, 255, 255)
	local COR_AZUL = Color3.fromRGB(0, 170, 255)
	local ALCANCE_OMBRO = 1.75 -- quanto a câmera fica para o lado (clássico: por cima do ombro)
	local lado = 1 -- 1 = ombro direito, -1 = ombro esquerdo (botão ⇄ troca)
	local ultimoSL
	local travado = false -- cadeado azul (travado) ou branco (solto)
	local aplicado = false -- se já mexemos no personagem/câmera

	-- Cadeado na tela (arraste para mudar de lugar, toque para travar/soltar)
	-- Visual: cadeado de verdade (corpo + argola em U + furo da chave), pequeno, sem fundo redondo.
	-- Contorno escuro bem fino para aparecer em qualquer cenário (céu claro, parede branca...).
	local botaoLock = Instance.new("TextButton")
	botaoLock.Name = "BotaoShiftLock"
	botaoLock.AnchorPoint = Vector2.new(0.5, 0.5)
	botaoLock.Position = UDim2.new(0.9, 0, 0.45, 0)
	botaoLock.Size = UDim2.fromOffset(44, 44) -- só a área de toque; não tem fundo
	botaoLock.BackgroundTransparency = 1
	botaoLock.Text = ""
	botaoLock.AutoButtonColor = false
	botaoLock.Visible = false
	botaoLock.ZIndex = 9
	botaoLock.Parent = gui
	local escala = Instance.new("UIScale") -- usado no "pop" ao tocar
	escala.Parent = botaoLock

	-- Brilho discreto atrás do cadeado (só aparece, azul e respirando, enquanto está travado)
	local halo = Instance.new("Frame")
	halo.Name = "Halo"
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.fromScale(0.5, 0.5)
	halo.Size = UDim2.fromOffset(38, 38)
	halo.BackgroundTransparency = 1
	halo.Active = false
	halo.ZIndex = 1
	halo.Parent = botaoLock
	Instance.new("UICorner", halo).CornerRadius = UDim.new(0.32, 0)
	local contorno = Instance.new("UIStroke")
	contorno.Color = COR_AZUL
	contorno.Thickness = 1.5
	contorno.Transparency = 1
	contorno.Parent = halo

	-- Argola (U): um quadro arredondado com borda; a metade de baixo fica escondida atrás do corpo
	local function fazerArgola(nome, espessura, zindex)
		local f = Instance.new("Frame")
		f.Name = nome
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, 0, 0, 18)
		f.Size = UDim2.fromOffset(14, 20)
		f.BackgroundTransparency = 1
		f.Active = false
		f.ZIndex = zindex
		f.Parent = botaoLock
		Instance.new("UICorner", f).CornerRadius = UDim.new(0.5, 0)
		local c = Instance.new("UIStroke")
		c.Thickness = espessura
		c.Parent = f
		return f, c
	end
	local sombraArgola, sombraArgolaContorno = fazerArgola("SombraArgola", 5.5, 1)
	sombraArgolaContorno.Color = Color3.new(0, 0, 0)
	sombraArgolaContorno.Transparency = 0.6
	local argola, contornoArgola = fazerArgola("Argola", 3, 2)

	-- Corpo do cadeado
	local corpo = Instance.new("Frame")
	corpo.Name = "Corpo"
	corpo.AnchorPoint = Vector2.new(0.5, 0.5)
	corpo.Position = UDim2.new(0.5, 0, 0, 27)
	corpo.Size = UDim2.fromOffset(22, 16)
	corpo.BorderSizePixel = 0
	corpo.Active = false
	corpo.ZIndex = 3
	corpo.Parent = botaoLock
	Instance.new("UICorner", corpo).CornerRadius = UDim.new(0, 4)
	local contornoCorpo = Instance.new("UIStroke")
	contornoCorpo.Color = Color3.new(0, 0, 0)
	contornoCorpo.Thickness = 1.5
	contornoCorpo.Transparency = 0.5
	contornoCorpo.Parent = corpo

	-- Furo da chave (bolinha + haste)
	local COR_FURO = Color3.fromRGB(25, 25, 32)
	local furo = Instance.new("Frame")
	furo.AnchorPoint = Vector2.new(0.5, 0.5)
	furo.Position = UDim2.new(0.5, 0, 0.4, 0)
	furo.Size = UDim2.fromOffset(4, 4)
	furo.BackgroundColor3 = COR_FURO
	furo.BorderSizePixel = 0
	furo.Active = false
	furo.ZIndex = 4
	furo.Parent = corpo
	Instance.new("UICorner", furo).CornerRadius = UDim.new(1, 0)
	local haste = Instance.new("Frame")
	haste.AnchorPoint = Vector2.new(0.5, 0.5)
	haste.Position = UDim2.new(0.5, 0, 0.72, 0)
	haste.Size = UDim2.fromOffset(2, 5)
	haste.BackgroundColor3 = COR_FURO
	haste.BorderSizePixel = 0
	haste.Active = false
	haste.ZIndex = 4
	haste.Parent = corpo

	-- Onda de brilho que sai do cadeado quando trava
	local onda = Instance.new("Frame")
	onda.Name = "OndaLock"
	onda.AnchorPoint = Vector2.new(0.5, 0.5)
	onda.Position = UDim2.fromScale(0.5, 0.5)
	onda.Size = UDim2.fromScale(0.85, 0.85)
	onda.BackgroundTransparency = 1
	onda.BorderSizePixel = 0
	onda.Active = false
	onda.Visible = false
	onda.ZIndex = 1
	onda.Parent = botaoLock
	Instance.new("UICorner", onda).CornerRadius = UDim.new(0.32, 0)
	local contornoOnda = Instance.new("UIStroke")
	contornoOnda.Color = COR_AZUL
	contornoOnda.Thickness = 2
	contornoOnda.Parent = onda

	-- Botão pequeno embaixo do cadeado: troca o ombro da câmera (direita <-> esquerda)
	local botaoLado = Instance.new("TextButton")
	botaoLado.Name = "TrocarOmbro"
	botaoLado.AnchorPoint = Vector2.new(0.5, 0)
	botaoLado.Position = UDim2.new(0.5, 0, 1, 2)
	botaoLado.Size = UDim2.fromOffset(30, 18)
	botaoLado.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	botaoLado.BackgroundTransparency = 0.45
	botaoLado.Text = "⇄"
	botaoLado.TextColor3 = Color3.new(1, 1, 1)
	botaoLado.Font = Enum.Font.GothamBold
	botaoLado.TextSize = 13
	botaoLado.AutoButtonColor = true
	botaoLado.ZIndex = 9
	botaoLado.Parent = botaoLock
	Instance.new("UICorner", botaoLado).CornerRadius = UDim.new(0, 7)
	botaoLado.MouseButton1Click:Connect(function()
		lado = -lado -- a câmera desliza suave para o outro ombro (ver atualizarShiftLock)
	end)

	local pulsoContorno -- brilho que respira enquanto está travado
	local function pintar(animar)
		local cor = travado and COR_AZUL or COR_BRANCO
		local info = TweenInfo.new(animar and 0.25 or 0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(contornoArgola, info, { Color = cor }):Play()
		TweenService:Create(corpo, info, { BackgroundColor3 = cor }):Play()
		-- argola: fechada (travado) ou levantada (solto)
		local infoArgola = TweenInfo.new(animar and 0.3 or 0, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local posArgola = UDim2.new(0.5, 0, 0, travado and 18 or 12)
		TweenService:Create(argola, infoArgola, { Position = posArgola }):Play()
		TweenService:Create(sombraArgola, infoArgola, { Position = posArgola }):Play()

		if pulsoContorno then pulsoContorno:Cancel() pulsoContorno = nil end
		if travado then
			contorno.Transparency = 0.55
			pulsoContorno = TweenService:Create(contorno,
				TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.85 })
			pulsoContorno:Play()
		else
			contorno.Transparency = 1
		end

		if animar then
			-- "pop" do cadeado
			TweenService:Create(escala, TweenInfo.new(0.1), { Scale = 1.18 }):Play()
			task.delay(0.1, function()
				TweenService:Create(escala, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1 }):Play()
			end)
			-- onda de brilho ao travar
			if travado then
				onda.Size = UDim2.fromScale(0.85, 0.85)
				contornoOnda.Transparency = 0
				onda.Visible = true
				TweenService:Create(onda, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.fromScale(1.7, 1.7) }):Play()
				local t = TweenService:Create(contornoOnda, TweenInfo.new(0.5), { Transparency = 1 })
				t.Completed:Connect(function() onda.Visible = false end)
				t:Play()
			end
		end
	end
	pintar(false)

	-- Ao soltar: devolve o mouse e a rotação na hora; a câmera volta ao centro devagar (em atualizarShiftLock)
	local function restaurar()
		if not aplicado then return end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		local _, hum = pegarPersonagem()
		if hum then hum.AutoRotate = true end
	end

	tornarMovel(botaoLock, botaoLock, function()
		travado = not travado
		pintar(true)
		if not travado then restaurar() end
	end)

	definirShiftLock = function(v)
		estado.shiftlock = v
		botaoLock.Visible = v
		pintarBotao(botaoShiftLock, "SHIFTLOCK", v)
		if not v then
			travado = false
			pintar(false)
			restaurar()
		end
	end
	botaoShiftLock.MouseButton1Click:Connect(function() definirShiftLock(not estado.shiftlock) end)

	-- Roda todo frame: trava o mouse no centro e vira o personagem para onde a câmera aponta
	atualizarShiftLock = function()
		local agora = os.clock()
		local dt = math.min(agora - (ultimoSL or agora), 0.1)
		ultimoSL = agora
		local raiz, hum = pegarPersonagem()

		if not (estado.shiftlock and travado) then
			-- soltou: a câmera volta suave para o centro
			if aplicado then
				if hum then
					hum.CameraOffset = hum.CameraOffset:Lerp(Vector3.zero, 1 - math.exp(-dt * 10))
					if hum.CameraOffset.Magnitude < 0.02 then
						hum.CameraOffset = Vector3.zero
						aplicado = false
					end
				else
					aplicado = false
				end
			end
			return
		end
		if not raiz then return end

		aplicado = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		hum.AutoRotate = false
		-- a câmera desliza até o ombro (e para o outro ombro, se trocar)
		hum.CameraOffset = hum.CameraOffset:Lerp(Vector3.new(ALCANCE_OMBRO * lado, 0, 0), 1 - math.exp(-dt * 10))

		-- voando/nadando/sentado, quem gira o personagem é o próprio modo
		if estado.fly or estado.vfly or estado.swim or hum.Sit then return end
		local look = workspace.CurrentCamera.CFrame.LookVector
		local plano = Vector3.new(look.X, 0, look.Z)
		if plano.Magnitude > 0.001 then
			raiz.CFrame = CFrame.lookAt(raiz.Position, raiz.Position + plano)
		end
	end
end

------------------------------------------------------------
-- ANOTAÇÕES (quadrados brancos: + NOVA cria, toque para editar, ✕ exclui)
------------------------------------------------------------
-- Salva em "anotacoes.json" com o writefile do executor (vale para todos os jogos).
-- Sem writefile/readfile, as notas ficam só até fechar o jogo.
do -- bloco (libera variáveis locais)
	local ARQUIVO_NOTAS = "anotacoes.json"
	local ATRASO_SALVAR = 0.8 -- segundos parado de digitar até salvar sozinho

	local botaoNotas = criarLinha(18, "NOTAS", false)
	botaoNotas.Text = "ANOTAÇÕES"

	local painelNotas = Instance.new("Frame")
	painelNotas.Name = "PainelNotas"
	painelNotas.AnchorPoint = Vector2.new(1, 0.5)
	painelNotas.Position = UDim2.new(0.5, -160, 0.5, 0)
	painelNotas.Size = UDim2.new(0, 290, 0, 380)
	painelNotas.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	painelNotas.Visible = false
	painelNotas.Parent = gui
	Instance.new("UICorner", painelNotas).CornerRadius = UDim.new(0, 14)

	local tituloNotas = Instance.new("TextLabel")
	tituloNotas.Size = UDim2.new(1, 0, 0, 40)
	tituloNotas.BackgroundTransparency = 1
	tituloNotas.Text = "Anotações"
	tituloNotas.TextColor3 = Color3.new(1, 1, 1)
	tituloNotas.Font = Enum.Font.GothamBold
	tituloNotas.TextSize = 20
	tituloNotas.Active = true
	tituloNotas.Parent = painelNotas
	tornarMovel(tituloNotas, painelNotas)

	local botaoNova = Instance.new("TextButton")
	botaoNova.Position = UDim2.new(0.05, 0, 0, 44)
	botaoNova.Size = UDim2.new(0.9, 0, 0, 32)
	botaoNova.BackgroundColor3 = Color3.fromRGB(40, 120, 70)
	botaoNova.Text = "+ NOVA"
	botaoNova.TextColor3 = Color3.new(1, 1, 1)
	botaoNova.Font = Enum.Font.GothamBold
	botaoNova.TextSize = 15
	botaoNova.Parent = painelNotas
	Instance.new("UICorner", botaoNova).CornerRadius = UDim.new(0, 8)

	local listaNotas = Instance.new("ScrollingFrame")
	listaNotas.Position = UDim2.new(0.05, 0, 0, 84)
	listaNotas.Size = UDim2.new(0.9, 0, 1, -112)
	listaNotas.BackgroundTransparency = 1
	listaNotas.BorderSizePixel = 0
	listaNotas.ScrollBarThickness = 4
	listaNotas.CanvasSize = UDim2.new(0, 0, 0, 0)
	listaNotas.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listaNotas.Parent = painelNotas
	local layoutNotas = Instance.new("UIListLayout")
	layoutNotas.Padding = UDim.new(0, 8)
	layoutNotas.SortOrder = Enum.SortOrder.LayoutOrder
	layoutNotas.Parent = listaNotas

	local avisoNotas = Instance.new("TextLabel")
	avisoNotas.Position = UDim2.new(0.05, 0, 1, -24)
	avisoNotas.Size = UDim2.new(0.9, 0, 0, 20)
	avisoNotas.BackgroundTransparency = 1
	avisoNotas.Text = ""
	avisoNotas.TextColor3 = Color3.fromRGB(170, 170, 180)
	avisoNotas.Font = Enum.Font.Gotham
	avisoNotas.TextSize = 12
	avisoNotas.TextXAlignment = Enum.TextXAlignment.Left
	avisoNotas.Parent = painelNotas

	local podeSalvar = temArquivos() and typeof(writefile) == "function"
	local carregando = true
	local versaoSalvar = 0
	local contador = 0
	local cartoes = {} -- cada item: { frame = Frame, caixa = TextBox }

	local function salvarNotas()
		if carregando then return end
		if not podeSalvar then
			avisoNotas.Text = "Sem salvar: o executor não tem writefile"
			return
		end
		local ordenados = {}
		for _, c in ipairs(cartoes) do ordenados[#ordenados + 1] = c end
		table.sort(ordenados, function(a, b) return a.frame.LayoutOrder < b.frame.LayoutOrder end)
		local textos = {}
		for _, c in ipairs(ordenados) do textos[#textos + 1] = c.caixa.Text end
		local ok = pcall(function() writefile(ARQUIVO_NOTAS, HttpService:JSONEncode(textos)) end)
		avisoNotas.Text = ok and "Salvo" or "Não foi possível salvar"
	end

	local function agendarSalvar()
		if carregando then return end
		if podeSalvar then avisoNotas.Text = "Salvando..." end
		versaoSalvar += 1
		local minha = versaoSalvar
		task.delay(ATRASO_SALVAR, function()
			if minha == versaoSalvar then salvarNotas() end
		end)
	end

	-- Cria um quadrado branco (a nota mais nova fica em cima)
	local function criarCartao(texto)
		contador += 1
		local cartao = Instance.new("Frame")
		cartao.LayoutOrder = -contador
		cartao.Size = UDim2.new(1, -6, 0, 0)
		cartao.AutomaticSize = Enum.AutomaticSize.Y
		cartao.BackgroundColor3 = Color3.new(1, 1, 1)
		cartao.Parent = listaNotas
		Instance.new("UICorner", cartao).CornerRadius = UDim.new(0, 8)

		local caixa = Instance.new("TextBox")
		caixa.Position = UDim2.fromOffset(0, 0)
		caixa.Size = UDim2.new(1, -34, 0, 70)
		caixa.AutomaticSize = Enum.AutomaticSize.Y
		caixa.BackgroundTransparency = 1
		caixa.Text = texto or ""
		caixa.PlaceholderText = "Escreva aqui..."
		caixa.PlaceholderColor3 = Color3.fromRGB(140, 140, 140)
		caixa.TextColor3 = Color3.new(0, 0, 0)
		caixa.Font = Enum.Font.Gotham
		caixa.TextSize = 14
		caixa.MultiLine = true
		caixa.TextWrapped = true
		caixa.ClearTextOnFocus = false
		caixa.TextXAlignment = Enum.TextXAlignment.Left
		caixa.TextYAlignment = Enum.TextYAlignment.Top
		caixa.Parent = cartao
		do
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 8)
			pad.PaddingTop = UDim.new(0, 8)
			pad.PaddingBottom = UDim.new(0, 8)
			pad.Parent = caixa
		end

		local excluir = Instance.new("TextButton")
		excluir.AnchorPoint = Vector2.new(1, 0)
		excluir.Position = UDim2.new(1, -4, 0, 4)
		excluir.Size = UDim2.fromOffset(26, 26)
		excluir.BackgroundColor3 = COR_OFF
		excluir.Text = "✕"
		excluir.TextColor3 = Color3.new(1, 1, 1)
		excluir.Font = Enum.Font.GothamBold
		excluir.TextSize = 14
		excluir.Parent = cartao
		Instance.new("UICorner", excluir).CornerRadius = UDim.new(0, 6)

		local item = { frame = cartao, caixa = caixa }
		cartoes[#cartoes + 1] = item

		caixa:GetPropertyChangedSignal("Text"):Connect(agendarSalvar)
		caixa.FocusLost:Connect(function()
			versaoSalvar += 1
			salvarNotas()
		end)
		excluir.MouseButton1Click:Connect(function()
			for i, c in ipairs(cartoes) do
				if c == item then table.remove(cartoes, i) break end
			end
			cartao:Destroy()
			versaoSalvar += 1
			salvarNotas()
		end)
		return caixa
	end

	-- Carrega o que foi salvo antes (a primeira da lista fica por último = mais antiga)
	if podeSalvar then
		pcall(function()
			if not isfile(ARQUIVO_NOTAS) then return end
			local lista = HttpService:JSONDecode(readfile(ARQUIVO_NOTAS))
			if type(lista) ~= "table" then return end
			for i = #lista, 1, -1 do
				if type(lista[i]) == "string" then criarCartao(lista[i]) end
			end
		end)
	else
		avisoNotas.Text = "Sem salvar: o executor não tem writefile"
	end
	carregando = false

	botaoNova.MouseButton1Click:Connect(function()
		local caixa = criarCartao("")
		listaNotas.CanvasPosition = Vector2.new(0, 0)
		caixa:CaptureFocus()
	end)

	function MENU.notas()
		painelNotas.Visible = not painelNotas.Visible
		if painelNotas.Visible then posicionarAoLado(painelNotas) end
		return painelNotas.Visible
	end
	botaoNotas.MouseButton1Click:Connect(MENU.notas)
end -- fim do bloco (libera variáveis locais)

------------------------------------------------------------
-- GRUDAR NO CHÃO (acompanha carros e plataformas que se mexem; você ainda anda)
------------------------------------------------------------
-- Todo frame: vê em que peça você está pisando e, se ela se mexeu, move você junto.
do -- bloco (libera variáveis locais)
	local FORCA_GRUDAR = 1 -- 1 = acompanha tudo; se ficar rápido demais num carro, tente 0.5
	local ALCANCE_EXTRA = 3 -- studs de folga abaixo dos pés para achar o chão
	local SALTO_MAXIMO = 60 -- se a peça "pular" mais que isso num frame (teleporte), ignora

	local botaoGrudar = criarLinha(19, "GRUDAR", false)
	estado.grudar = false

	local pecaAntes, cfAntes = nil, nil
	local conexao = nil
	local parametros = RaycastParams.new()
	parametros.FilterType = Enum.RaycastFilterType.Exclude
	parametros.RespectCanCollide = true

	local function zerar()
		pecaAntes, cfAntes = nil, nil
	end

	local function passo()
		local raiz, hum = pegarPersonagem()
		if not raiz or estado.fly or estado.vfly or estado.swim or estado.wall or hum.Sit then
			zerar()
			return
		end
		parametros.FilterDescendantsInstances = { player.Character }
		local alcance = hum.HipHeight + raiz.Size.Y / 2 + ALCANCE_EXTRA
		local r = workspace:Raycast(raiz.Position, Vector3.new(0, -alcance, 0), parametros)
		local peca = r and r.Instance
		if not peca then
			zerar()
			return
		end
		if peca == pecaAntes and cfAntes then
			local delta = peca.CFrame * cfAntes:Inverse()
			local mexeu = delta.Position.Magnitude > 1e-4 or (delta.LookVector - Vector3.new(0, 0, -1)).Magnitude > 1e-5
			if mexeu and delta.Position.Magnitude < SALTO_MAXIMO then
				if FORCA_GRUDAR < 1 then
					delta = CFrame.new().Lerp(delta, FORCA_GRUDAR)
				end
				raiz.CFrame = delta * raiz.CFrame
			end
		end
		pecaAntes, cfAntes = peca, peca.CFrame
	end

	function MENU.grudar(v)
		estado.grudar = v
		pintarBotao(botaoGrudar, "GRUDAR", v)
		zerar()
		if conexao then conexao:Disconnect() conexao = nil end
		if v then
			conexao = RunService.Heartbeat:Connect(passo)
		end
	end
	botaoGrudar.MouseButton1Click:Connect(function() MENU.grudar(not estado.grudar) end)
	botaoGrudar.Text = "GRUDAR NO CHÃO"

	player.CharacterAdded:Connect(zerar)
end -- fim do bloco (libera variáveis locais)

------------------------------------------------------------
-- ANDAR NAS PAREDES (chão, parede e teto; contorna quinas e acompanha rampas)
------------------------------------------------------------
-- A "gravidade" passa a puxar o personagem para a superfície em que ele está.
-- A câmera continua normal (não gira junto). Usa a mesma ideia do GRUDAR: se a peça se mexe, você vai junto.
do -- bloco (libera variáveis locais)
	local ALCANCE_EXTRA = 2.2 -- folga abaixo dos pés para achar a superfície
	local ALCANCE_FRENTE = 2.8 -- distância para ver uma parede à frente (quina de dentro)
	local ALCANCE_QUINA = 3 -- quanto olha para frente para contornar uma quina de fora
	local SUAVIDADE = 12 -- quão rápido o corpo gira para acompanhar a superfície
	local PULO_FORCA, PULO_TEMPO = 45, 0.2

	local botaoWall = criarLinha(20, "WALL", false)
	estado.wall = false

	local conexao, bv, bg
	local normalAlvo = Vector3.yAxis -- normal da superfície em que está (usada nos raios)
	local normalSuave = Vector3.yAxis -- normal suavizada (usada para girar o corpo)
	local frente = Vector3.new(0, 0, -1) -- para onde o corpo está virado (no plano da superfície)
	local pecaAntes, cfAntes = nil, nil
	local solto = true -- true = jogo normal (nenhuma superfície por perto ainda)
	local pulo = 0
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true

	local function projetar(v, n) return v - n * v:Dot(n) end

	local function planoOuPadrao(v, n, padrao)
		local p = projetar(v, n)
		if p.Magnitude < 0.05 then p = padrao end
		return p.Unit
	end

	local function largar(raiz, hum)
		if bv then bv:Destroy() bv = nil end
		if bg then bg:Destroy() bg = nil end
		if raiz and raiz.Parent then
			local plano = Vector3.new(frente.X, 0, frente.Z)
			if plano.Magnitude < 0.05 then
				local l = workspace.CurrentCamera.CFrame.LookVector
				plano = Vector3.new(l.X, 0, l.Z)
			end
			if plano.Magnitude > 0.01 then
				raiz.CFrame = CFrame.lookAt(raiz.Position, raiz.Position + plano.Unit)
			end
			raiz.AssemblyLinearVelocity = Vector3.zero
			raiz.AssemblyAngularVelocity = Vector3.zero
		end
		if hum and hum.Parent then hum.PlatformStand = false end
		pecaAntes, cfAntes = nil, nil
		normalAlvo, normalSuave = Vector3.yAxis, Vector3.yAxis
		solto = true
	end

	local function agarrar(raiz, hum, normal)
		if bv then bv:Destroy() end
		if bg then bg:Destroy() end
		bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
		bv.Velocity = Vector3.zero
		bv.Parent = raiz
		bg = Instance.new("BodyGyro")
		bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
		bg.P = 9e4
		bg.D = 1200
		bg.CFrame = raiz.CFrame
		bg.Parent = raiz
		hum.PlatformStand = true
		normalAlvo, normalSuave = normal, normal
		local l = workspace.CurrentCamera.CFrame.LookVector
		frente = planoOuPadrao(l, normal, raiz.CFrame.LookVector)
		pecaAntes, cfAntes = nil, nil
		solto = false
	end

	local function passo(dt)
		local raiz, hum = pegarPersonagem()
		if not raiz then
			solto = true
			bv, bg = nil, nil
			return
		end
		-- Fly, VFly, Swim ou sentado: o WALL espera
		if estado.fly or estado.vfly or estado.swim or hum.SeatPart then
			if not solto then largar(raiz, hum) end
			return
		end

		params.FilterDescendantsInstances = { player.Character }
		local altura = hum.HipHeight + raiz.Size.Y / 2
		local alc = altura + ALCANCE_EXTRA
		local pos = raiz.Position

		-- Solto: só procura chão por perto (jogo normal) para agarrar
		if solto then
			local r = workspace:Raycast(pos, Vector3.new(0, -(alc + 3), 0), params)
			if r then agarrar(raiz, hum, r.Normal) end
			return
		end
		if not bv or bv.Parent ~= raiz or not bg then
			agarrar(raiz, hum, normalAlvo)
		end

		local n = normalAlvo
		local camCF = workspace.CurrentCamera.CFrame

		-- Entrada: analógico/teclado relativo à câmera, levado para o plano da superfície
		local mover = hum.MoveDirection
		local rFlat = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
		rFlat = rFlat.Magnitude > 0.01 and rFlat.Unit or Vector3.xAxis
		local fFlat = Vector3.yAxis:Cross(rFlat)
		local ix, iz = mover:Dot(rFlat), mover:Dot(fFlat)

		local look = camCF.LookVector
		local fSup = projetar(look, n) + projetar(camCF.UpVector, n) * math.clamp(-look:Dot(n), 0, 1)
		if fSup.Magnitude < 0.05 then fSup = projetar(camCF.UpVector, n) end
		if fSup.Magnitude < 0.05 then fSup = frente end
		fSup = fSup.Unit
		local rSup = projetar(camCF.RightVector, n)
		rSup = rSup.Magnitude > 0.05 and rSup.Unit or fSup:Cross(n)
		local desejado = rSup * ix + fSup * iz
		if desejado.Magnitude > 1 then desejado = desejado.Unit end
		local andando = desejado.Magnitude > 0.1
		local dirMov = andando and desejado.Unit or nil

		-- 1) parede à frente (quina de dentro): passa a andar nela
		local trocou = false
		if dirMov then
			local r = workspace:Raycast(pos, dirMov * ALCANCE_FRENTE, params)
			if r and r.Normal:Dot(n) < 0.5 then
				normalAlvo = r.Normal
				n = normalAlvo
				trocou = true
			end
		end

		-- 2) chão sob os pés (segue rampas e curvas)
		local chao
		if not trocou then
			chao = workspace:Raycast(pos, -n * alc, params)
			if chao then
				local suave = 1 - math.exp(-dt * SUAVIDADE)
				normalAlvo = normalAlvo:Lerp(chao.Normal, suave).Unit
				n = normalAlvo
			elseif dirMov then
				-- 3) acabou o chão (quina de fora): procura a superfície que dobra para baixo
				local origem = pos + dirMov * ALCANCE_QUINA - n * (altura + 0.5)
				local r = workspace:Raycast(origem, -dirMov * (ALCANCE_QUINA + 0.8), params)
				if r then
					normalAlvo = r.Normal
					n = normalAlvo
					trocou = true
				end
			end
		end

		if not chao and not trocou then
			largar(raiz, hum) -- nada por perto: volta ao jogo normal
			return
		end

		-- Peça que se mexe (carro, plataforma): leva você junto, como o GRUDAR
		if pulo <= 0 then
			local peca = chao and chao.Instance or nil
			if peca and peca == pecaAntes and cfAntes then
				local delta = peca.CFrame * cfAntes:Inverse()
				if delta.Position.Magnitude > 1e-4 or (delta.LookVector - Vector3.new(0, 0, -1)).Magnitude > 1e-5 then
					if delta.Position.Magnitude < 60 then
						raiz.CFrame = delta * raiz.CFrame
					end
				end
			end
			if peca then pecaAntes, cfAntes = peca, peca.CFrame else pecaAntes, cfAntes = nil, nil end
		else
			pecaAntes, cfAntes = nil, nil
		end

		-- Velocidade: anda no plano + cola na superfície mantendo a altura dos pés
		local vNormal = 0
		if pulo > 0 then
			pulo = pulo - dt
			vNormal = PULO_FORCA
		elseif chao then
			local dist = (pos - chao.Position):Dot(chao.Normal)
			vNormal = math.clamp((altura - dist) * 12, -40, 40)
		end
		bv.Velocity = desejado * hum.WalkSpeed + n * vNormal

		-- Corpo: de pé na superfície, virado para onde anda
		if andando then
			frente = frente:Lerp(dirMov, 1 - math.exp(-dt * 10))
		end
		normalSuave = normalSuave:Lerp(n, 1 - math.exp(-dt * SUAVIDADE)).Unit
		local alto = normalSuave
		local olhar = planoOuPadrao(frente, alto, fSup)
		frente = olhar
		bg.CFrame = CFrame.fromMatrix(pos, olhar:Cross(alto), alto, -olhar)
	end

	function MENU.wall(v)
		estado.wall = v
		pintarBotao(botaoWall, "WALL", v)
		if conexao then conexao:Disconnect() conexao = nil end
		local raiz, hum = pegarPersonagem()
		if not solto then largar(raiz, hum) end
		solto = true
		pulo = 0
		if v then
			conexao = RunService.Heartbeat:Connect(passo)
		end
	end
	botaoWall.MouseButton1Click:Connect(function() MENU.wall(not estado.wall) end)
	botaoWall.Text = "ANDAR NAS PAREDES"

	UserInputService.JumpRequest:Connect(function()
		if estado.wall and not solto and pulo <= 0 then pulo = PULO_TEMPO end
	end)

	player.CharacterAdded:Connect(function()
		bv, bg = nil, nil
		pecaAntes, cfAntes = nil, nil
		normalAlvo, normalSuave = Vector3.yAxis, Vector3.yAxis
		solto = true
		pulo = 0
	end)
end -- fim do bloco (libera variáveis locais)

------------------------------------------------------------
-- TECLADO (barra de comandos digitados)
------------------------------------------------------------
local function iniciarTeclado()
	local toque = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local tecladoLigado = true -- a barra fica sempre no canto da tela
	local barraAberta = false
	local listaAjuda = {}
	local entradas = {} -- { nomes = {...}, desc = "..." } -> usado para filtrar/completar a lista
	local manterBarra = false -- true = o comando pediu para a barra continuar aberta (cmds)
	local comandos = {} -- [palavra] = function(args) -> sucesso, mensagem
	local LARGURA_FECHADA, ALTURA_FECHADA = 88, 18 -- tira fina quando fechada
	local LARGURA_PAINEL = 250 -- painel aberto (caixa + lista juntos)
	local ALTURA_CAIXA, ALTURA_LINHA, MAX_LINHAS = 26, 22, 7
	local tAbriu = 0 -- quando a barra abriu (ignora perda de foco logo no começo)
	local tocandoPainel = false -- dedo/mouse apertando dentro do painel (não fecha)

	local function novo(classe, props, pai)
		local o = Instance.new(classe)
		for k, v in pairs(props) do o[k] = v end
		o.Parent = pai
		return o
	end

	----------------------------------------------------------
	-- Interface: tira fina "> comandos" (arrastável) + painel único aberto
	----------------------------------------------------------
	local cmdFrame = novo("Frame", {
		Name = "BarraComandos",
		AnchorPoint = Vector2.new(1, 1),
		Position = toque and UDim2.new(1, -130, 1, -6) or UDim2.new(1, -16, 1, -16), -- no celular fica ao lado do botão de pulo
		Size = UDim2.fromOffset(LARGURA_FECHADA, ALTURA_FECHADA),
		BackgroundTransparency = 1,
		Visible = true,
		ZIndex = 10,
	}, gui)

	local icone = novo("TextButton", {
		Name = "Icone",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(18, 18, 22),
		BackgroundTransparency = 0.2,
		AutoButtonColor = false,
		Text = "> comandos",
		TextColor3 = Color3.fromRGB(170, 170, 182),
		Font = Enum.Font.Gotham,
		TextSize = 11,
	}, cmdFrame)
	novo("UICorner", { CornerRadius = UDim.new(0, 4) }, icone)
	novo("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.82 }, icone)

	-- Painel único: caixa de digitar em cima e a lista de comandos logo abaixo
	local painelCmd = novo("Frame", {
		Name = "PainelComandos",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -40),
		Size = UDim2.fromOffset(LARGURA_PAINEL, ALTURA_CAIXA + 16 + MAX_LINHAS * ALTURA_LINHA),
		BackgroundColor3 = Color3.fromRGB(18, 18, 22),
		BackgroundTransparency = 0.08,
		Active = true,
		Visible = false,
		ZIndex = 11,
	}, gui)
	novo("UICorner", { CornerRadius = UDim.new(0, 6) }, painelCmd)
	novo("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.82 }, painelCmd)

	local caixaCmd = novo("TextBox", {
		Name = "Comando",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, ALTURA_CAIXA),
		BackgroundColor3 = Color3.fromRGB(32, 32, 38),
		Text = "",
		PlaceholderText = "comando (cmds = lista)",
		PlaceholderColor3 = Color3.fromRGB(120, 120, 130),
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
	}, painelCmd)
	novo("UICorner", { CornerRadius = UDim.new(0, 4) }, caixaCmd)
	novo("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, caixaCmd)
	-- iOS: sem a caixa de texto nativa (o quadrado branco); digita direto na barra
	pcall(function() caixaCmd.ShowNativeInput = false end)

	-- Aviso curto com o resultado do comando (aparece em cima da tira)
	local toast = novo("TextLabel", {
		Name = "Aviso",
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Color3.fromRGB(18, 18, 22),
		BackgroundTransparency = 0.1,
		TextWrapped = true,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Visible = false,
	}, cmdFrame)
	novo("UICorner", { CornerRadius = UDim.new(0, 6) }, toast)
	novo("UIPadding", {
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
	}, toast)
	novo("UISizeConstraint", { MaxSize = Vector2.new(260, 160) }, toast)

	-- Lista de comandos (dentro do mesmo painel, com rolagem)
	local rolagem = novo("ScrollingFrame", {
		Position = UDim2.fromOffset(6, ALTURA_CAIXA + 10),
		Size = UDim2.new(1, -12, 1, -(ALTURA_CAIXA + 16)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, painelCmd)
	novo("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }, rolagem)

	-- Toque/clique dentro do painel não pode fechar a barra (completar comando, rolar a lista)
	painelCmd.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			tocandoPainel = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if tocandoPainel and (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) then
			task.delay(0.25, function() tocandoPainel = false end)
		end
	end)

	-- Topo da tira na tela, calculado pelas propriedades (AbsolutePosition demora um quadro para atualizar)
	local function topoDaBarra()
		local pos, tam, a = cmdFrame.Position, cmdFrame.Size, cmdFrame.AnchorPoint
		return pos.Y.Scale * tamanhoTela().Y + pos.Y.Offset - a.Y * tam.Y.Offset
	end

	-- Aviso fica em cima da tira (ou embaixo, se a tira estiver no topo da tela)
	local function posicionarAcima(obj)
		if topoDaBarra() < 90 then
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

	-- Completa o comando tocado na lista e deixa o cursor pronto para os argumentos
	local function completarComando(nome)
		local antes = caixaCmd.Text:match("^(.*,)") or "" -- tudo até a última vírgula
		caixaCmd.Text = antes .. (antes ~= "" and " " or "") .. nome .. " "
		caixaCmd:CaptureFocus()
		caixaCmd.CursorPosition = #caixaCmd.Text + 1
	end

	local linhasSugestao = {}

	-- Monta a lista de comandos que combinam com o que está sendo digitado (vazio = todos)
	local function atualizarSugestoes(texto)
		for _, l in ipairs(linhasSugestao) do l:Destroy() end
		table.clear(linhasSugestao)

		local trecho = (texto or ""):match("([^,]*)$") or "" -- só o último comando digitado
		local palavra = ((trecho:match("^%s*(%S*)") or ""):lower():gsub("^/", ""))

		local achados = {}
		for i, e in ipairs(entradas) do
			local melhor, nomeMelhor
			for _, n in ipairs(e.nomes) do
				local nota
				if palavra == "" then nota = 2
				elseif n == palavra then nota = 1
				elseif n:sub(1, #palavra) == palavra then nota = 2
				elseif n:find(palavra, 1, true) then nota = 3 end
				if nota and (not melhor or nota < melhor) then
					melhor, nomeMelhor = nota, n
				end
			end
			if melhor then
				achados[#achados + 1] = { e = e, nota = melhor, i = i, nome = palavra == "" and e.nomes[1] or nomeMelhor }
			end
		end
		table.sort(achados, function(a, b)
			if a.nota ~= b.nota then return a.nota < b.nota end
			return a.i < b.i
		end)

		for k, a in ipairs(achados) do
			local linha = novo("TextButton", {
				LayoutOrder = k,
				Size = UDim2.new(1, -6, 0, ALTURA_LINHA),
				BackgroundColor3 = Color3.fromRGB(40, 40, 48),
				BackgroundTransparency = 0.6,
				Text = a.e.desc,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(205, 205, 215),
				Font = Enum.Font.Gotham,
				TextSize = 11,
				AutoButtonColor = true,
			}, rolagem)
			novo("UICorner", { CornerRadius = UDim.new(0, 4) }, linha)
			novo("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, linha)
			linha.Activated:Connect(function() completarComando(a.nome) end)
			linhasSugestao[#linhasSugestao + 1] = linha
		end

		if #achados == 0 then
			linhasSugestao[1] = novo("TextLabel", {
				Size = UDim2.new(1, -6, 0, ALTURA_LINHA),
				BackgroundTransparency = 1,
				Text = "Nenhum comando assim",
				TextColor3 = Color3.fromRGB(140, 140, 150),
				Font = Enum.Font.Gotham,
				TextSize = 11,
			}, rolagem)
		end
		rolagem.CanvasPosition = Vector2.new(0, 0)
	end

	-- Painel (caixa em cima, lista logo abaixo) abre no lugar da tira, colado no canto de baixo da tela.
	-- Só sobe se o teclado da tela estiver realmente cobrindo essa posição.
	local function ajustarPainel()
		local tela = tamanhoTela()
		local fundo = cmdFrame.AbsolutePosition.Y + cmdFrame.AbsoluteSize.Y -- base da tira
		local direita = cmdFrame.AbsolutePosition.X + cmdFrame.AbsoluteSize.X
		direita = math.clamp(direita, LARGURA_PAINEL + 4, tela.X - 4)
		fundo = math.min(fundo, tela.Y - 4)

		local okV, visivel = pcall(function() return UserInputService.OnScreenKeyboardVisible end)
		if okV and visivel then
			local okP, pos = pcall(function() return UserInputService.OnScreenKeyboardPosition end)
			if okP and typeof(pos) == "Vector2" and pos.Y > 0 and fundo > pos.Y - 6 then
				fundo = pos.Y - 6 -- topo do teclado
			end
		end

		-- em telas baixas, mostra menos linhas para o painel caber
		local fixo = ALTURA_CAIXA + 16
		local linhas = math.clamp(math.floor((fundo - 8 - fixo) / ALTURA_LINHA), 3, MAX_LINHAS)
		painelCmd.Size = UDim2.fromOffset(LARGURA_PAINEL, fixo + linhas * ALTURA_LINHA)
		painelCmd.Position = UDim2.fromOffset(direita, fundo)
	end

	local function mostrarLista()
		ajustarPainel()
		toast.Visible = false
		painelCmd.Visible = true
	end

	local function abrirAjuda() -- lista completa (comando cmds)
		atualizarSugestoes("")
		mostrarLista()
	end

	-- Teclado da tela mexeu (abriu, fechou, mudou de tamanho): reposiciona o painel
	pcall(function()
		for _, p in ipairs({ "OnScreenKeyboardVisible", "OnScreenKeyboardPosition", "OnScreenKeyboardSize" }) do
			UserInputService:GetPropertyChangedSignal(p):Connect(function()
				if barraAberta then ajustarPainel() end
			end)
		end
	end)

	local function fecharBarra()
		barraAberta = false
		pcall(function() caixaCmd:ReleaseFocus() end)
		painelCmd.Visible = false
		icone.Visible = true
	end

	local function abrirBarra()
		barraAberta = true
		tAbriu = os.clock()
		toastVersao += 1
		toast.Visible = false
		icone.Visible = false
		atualizarSugestoes(caixaCmd.Text)
		mostrarLista()
		-- abre o teclado na hora; tenta de novo rapidinho se o celular não pegar de primeira
		caixaCmd:CaptureFocus()
		task.spawn(function()
			for _ = 1, 4 do
				task.wait(0.08)
				if not barraAberta or caixaCmd:IsFocused() then return end
				caixaCmd:CaptureFocus()
			end
		end)
	end

	-- Toque rápido na tira abre a barra; arrastar move a tira
	tornarMovel(icone, cmdFrame, function()
		if not barraAberta then abrirBarra() end
	end)

	-- A lista filtra enquanto você digita
	caixaCmd:GetPropertyChangedSignal("Text"):Connect(function()
		if barraAberta then
			atualizarSugestoes(caixaCmd.Text)
			mostrarLista()
		end
	end)

	-- Aberta sem foco (ex.: rolou a lista): tocar fora do painel fecha
	UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if not barraAberta or (t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1) then return end
		task.delay(0.06, function()
			if barraAberta and not caixaCmd:IsFocused() and not tocandoPainel and os.clock() - tAbriu > 0.35 then
				fecharBarra()
			end
		end)
	end)

	-- No PC: a tecla , (vírgula) abre a barra (como no Infinite Yield)
	UserInputService.InputBegan:Connect(function(input, processado)
		if processado or not tecladoLigado or barraAberta then return end
		if input.KeyCode ~= Enum.KeyCode.Comma then return end
		local antes = caixaCmd.Text
		abrirBarra()
		task.spawn(function()
			RunService.RenderStepped:Wait()
			if caixaCmd.Text == antes .. "," then caixaCmd.Text = antes end -- tira a vírgula que foi digitada
		end)
	end)

	----------------------------------------------------------
	-- Comandos
	----------------------------------------------------------
	-- Comando simples
	local function comando(nomes, descricao, f)
		for _, n in ipairs(nomes) do comandos[n] = f end
		listaAjuda[#listaAjuda + 1] = descricao
		entradas[#entradas + 1] = { nomes = nomes, desc = descricao }
	end

	-- Comando liga/desliga: "nome" liga e "unnome" desliga
	local function alternavel(nomes, descricao, f)
		local todos = {}
		for _, n in ipairs(nomes) do
			comandos[n] = function(args) return f(true, args) end
			comandos["un" .. n] = function(args) return f(false, args) end
			todos[#todos + 1] = n
			todos[#todos + 1] = "un" .. n
		end
		listaAjuda[#listaAjuda + 1] = descricao
		entradas[#entradas + 1] = { nomes = todos, desc = descricao }
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
	comandoDeVoo({ "vf" }, "vf [vel] / unvf - voar sentado em veículo", "VFly", caixaVFly, definirVFly,
		function() return velocidadeVFly end, function(v) velocidadeVFly = v end)
	comandoDeVoo({ "swim", "sw" }, "swim [vel] / unswim - nadar no ar", "Swim", caixaSwim, definirSwim,
		function() return velocidadeSwim end, function(v) velocidadeSwim = v end)

	alternavel({ "np", "noclip" }, "np ou noclip / unnp ou unnoclip - atravessar paredes", function(ligar)
		definirNoclip(ligar)
		return true, "Noclip " .. (ligar and "ligado" or "desligado")
	end)

	alternavel({ "xy" }, "xy [0 a 0.95] / unxy - mapa transparente", function(ligar, args)
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

	alternavel({ "cm" }, "cm / uncm - contorno nos jogadores", function(ligar)
		definirChams(ligar)
		return true, "Chams " .. (ligar and "ligado" or "desligado")
	end)

	alternavel({ "aim" }, "aim [tamanho] / unaim - aimbot (bolinha verde = alcance)", function(ligar, args)
		local tam
		if ligar and args[1] then
			tam = tonumber(args[1])
			if not tam then return false, "Valor inválido: " .. args[1] end
		end
		definirAimbot(ligar, tam)
		return true, "Aimbot " .. (ligar and "ligado" or "desligado")
	end)

	alternavel({ "sl" }, "sl / unsl - cadeado de shift lock na tela", function(ligar)
		definirShiftLock(ligar)
		return true, "ShiftLock " .. (ligar and "ligado" or "desligado")
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
		-- mesma animação do botão TP do menu (voo supersônico + efeitos)
		iniciarDash(alvo.Position + Vector3.new(0, 3, 0), { velocidade = DASH_VELOCIDADE_TP, forte = true, instantaneo = MENU.cfg.tpInstantaneo })
		return true, "TP -> " .. alvoJogador.DisplayName
	end)

	alternavel({ "view" }, "view <jogador> / unview - ver pela câmera de um jogador", function(ligar, args)
		if not ligar then
			pararView()
			return true, "View desligado"
		end
		if #args == 0 then return false, "Uso: view <jogador>" end
		local alvoJogador = acharJogador(table.concat(args, " "))
		if not alvoJogador then return false, "Jogador não encontrado: " .. table.concat(args, " ") end
		iniciarView(alvoJogador)
		return true, "Vendo " .. alvoJogador.DisplayName
	end)

	comando({ "set" }, "set [nome] - salvar spawn aqui", function(args)
		local raiz = pegarPersonagem()
		if not raiz then return false, "Personagem indisponível" end
		local caixaNome = criarLinhaSpawn(raiz.CFrame)
		if #args > 0 then caixaNome.Text = table.concat(args, " ") end
		salvarSpawns()
		return true, "Spawn salvo: " .. caixaNome.Text
	end)

	comando({ "go" }, "go [nome ou nº] - ir a um spawn (sem nome = lista)", function(args)
		local lista = {}
		for linha, dados in pairs(spawnsSalvos) do
			lista[#lista + 1] = { ordem = linha.LayoutOrder, dados = dados }
		end
		table.sort(lista, function(a, b) return a.ordem < b.ordem end)

		if #args == 0 then
			if #lista == 0 then return false, "Nenhum spawn salvo (use set)" end
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
		iniciarDash(achado.cf.Position + Vector3.new(0, 3, 0), { velocidade = DASH_VELOCIDADE_TP, forte = true, instantaneo = MENU.cfg.tpInstantaneo })
		return true, "Indo para " .. achado.nome.Text
	end)

	comando({ "rj", "rejoin" }, "rj - reentrar no servidor (rejoin)", function()
		local okFila, motivo = fazerRejoin()
		if okFila == nil then return true, "Já está reentrando..." end
		if okFila == false then
			return true, "Reentrando... (sem reexecutar: " .. tostring(motivo) .. ")"
		end
		return true, "Reentrando... (o script volta sozinho)"
	end)

	comando({ "sit" }, "sit - sentar o personagem", function()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return false, "Sem personagem vivo" end
		hum.Sit = true
		return true
	end)

	-- NOTAS: abre/fecha o bloco de anotações
	comando({ "notas", "notes" }, "notas - abrir/fechar as anotações", function()
		local aberto = MENU.notas()
		return true, aberto and "Anotações abertas" or "Anotações fechadas"
	end)

	-- GRUDAR: acompanha plataformas e carros que se mexem
	alternavel({ "grudar", "gc" }, "grudar / ungrudar - ficar preso ao chão que se move", function(ligar)
		MENU.grudar(ligar)
		return true, "Grudar " .. (ligar and "ligado" or "desligado")
	end)

	-- WALL: andar nas paredes e no teto
	alternavel({ "wall" }, "wall / unwall - andar nas paredes e no teto", function(ligar)
		MENU.wall(ligar)
		return true, "Wall " .. (ligar and "ligado" or "desligado")
	end)

	-- SPEED e JUMP: velocidade de andar e força do pulo (valem de novo depois de renascer)
	local velAndar, forcaPulo = nil, nil -- nil = padrão do jogo
	local padraoVel, padraoPulo = 16, 50
	local conMov

	local function meuHumanoid()
		local char = player.Character
		return char and char:FindFirstChildOfClass("Humanoid")
	end

	local function atualizarMov()
		if velAndar or forcaPulo then
			if conMov then return end
			conMov = RunService.Heartbeat:Connect(function()
				local hum = meuHumanoid()
				if not hum then return end
				if velAndar and hum.WalkSpeed ~= velAndar then hum.WalkSpeed = velAndar end
				if forcaPulo then
					if not hum.UseJumpPower then hum.UseJumpPower = true end
					if hum.JumpPower ~= forcaPulo then hum.JumpPower = forcaPulo end
				end
			end)
		elseif conMov then
			conMov:Disconnect()
			conMov = nil
		end
	end

	alternavel({ "speed" }, "speed [1 a 500] / unspeed - velocidade de andar", function(ligar, args)
		local hum = meuHumanoid()
		if ligar then
			local n = args[1] and tonumber(args[1]) or 50
			if not n or n < 1 or n > 500 then return false, "speed: use um número de 1 a 500" end
			if not velAndar and hum then padraoVel = hum.WalkSpeed end
			velAndar = n
		else
			velAndar = nil
			if hum then hum.WalkSpeed = padraoVel end
		end
		atualizarMov()
		return true
	end)

	alternavel({ "jump" }, "jump [1 a 500] / unjump - força do pulo", function(ligar, args)
		local hum = meuHumanoid()
		if ligar then
			local n = args[1] and tonumber(args[1]) or 100
			if not n or n < 1 or n > 500 then return false, "jump: use um número de 1 a 500" end
			if not forcaPulo and hum then padraoPulo = hum.JumpPower end
			forcaPulo = n
		else
			forcaPulo = nil
			if hum then hum.JumpPower = padraoPulo end
		end
		atualizarMov()
		return true
	end)

	-- ANTI-AFK: evita ser expulso por ficar parado (começa ligado)
	local antiAfkLigado = true
	do
		local okVU, VirtualUser = pcall(function() return game:GetService("VirtualUser") end)
		if okVU and VirtualUser then
			player.Idled:Connect(function()
				if not antiAfkLigado then return end
				pcall(function()
					VirtualUser:CaptureController()
					VirtualUser:ClickButton2(Vector2.new())
				end)
			end)
		end
	end

	alternavel({ "afk" }, "afk / unafk - anti-AFK (não ser expulso por ficar parado)", function(ligar)
		antiAfkLigado = ligar
		return true
	end)

	-- ZOOM: aproxima/afasta a câmera além do limite normal do jogo
	local zoomOriginal -- { min, max } do jogo, guardado na primeira vez
	local ZOOM_MIN_LIVRE, ZOOM_MAX_LIVRE = 0.5, 5000

	alternavel({ "zoom" }, "zoom [distância] / unzoom - câmera mais perto ou mais longe (sem número = zoom livre)", function(ligar, args)
		if not ligar then
			if zoomOriginal then
				player.CameraMinZoomDistance = zoomOriginal[1]
				player.CameraMaxZoomDistance = zoomOriginal[2]
				zoomOriginal = nil
			end
			return true
		end

		local n
		if args[1] then
			n = tonumber(args[1])
			if not n or n < ZOOM_MIN_LIVRE or n > ZOOM_MAX_LIVRE then
				return false, "zoom: use um número de " .. ZOOM_MIN_LIVRE .. " a " .. ZOOM_MAX_LIVRE
			end
		end

		if not zoomOriginal then
			zoomOriginal = { player.CameraMinZoomDistance, player.CameraMaxZoomDistance }
		end

		if n then
			-- trava a distância por um instante para a câmera ir até ela, depois solta (dá para rolar/pinçar)
			player.CameraMinZoomDistance = n
			player.CameraMaxZoomDistance = n
			task.spawn(function()
				RunService.RenderStepped:Wait()
				RunService.RenderStepped:Wait()
				if not zoomOriginal then return end -- unzoom no meio
				player.CameraMinZoomDistance = ZOOM_MIN_LIVRE
				player.CameraMaxZoomDistance = ZOOM_MAX_LIVRE
			end)
		else
			player.CameraMinZoomDistance = ZOOM_MIN_LIVRE
			player.CameraMaxZoomDistance = ZOOM_MAX_LIVRE
		end
		return true
	end)

	-- AVISOS: mostra na tela quando um jogador entra ou sai do servidor (começa desligado)
	local avisosLigados = false
	local avisoGui = novo("ScreenGui", {
		Name = "AvisosJogadores",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
	}, playerGui)
	local avisoLista = novo("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.fromOffset(240, 120),
	}, avisoGui)
	novo("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, avisoLista)
	local avisoOrdem = 0
	local MAX_AVISOS = 4

	local function avisarJogador(p, entrou)
		if not avisosLigados then return end
		avisoOrdem += 1
		local nome = p.DisplayName
		if p.DisplayName ~= p.Name then nome = nome .. " (@" .. p.Name .. ")" end
		local rotulo = novo("TextLabel", {
			LayoutOrder = avisoOrdem,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = Color3.fromRGB(18, 18, 22),
			BackgroundTransparency = 0.15,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = entrou and Color3.fromRGB(150, 255, 170) or Color3.fromRGB(255, 150, 150),
			Text = (entrou and "+ " or "- ") .. nome .. (entrou and " entrou" or " saiu"),
		}, avisoLista)
		novo("UICorner", { CornerRadius = UDim.new(0, 6) }, rotulo)
		novo("UIPadding", {
			PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
		}, rotulo)

		-- no máximo MAX_AVISOS na tela: o mais antigo sai
		local visiveis = {}
		for _, f in ipairs(avisoLista:GetChildren()) do
			if f:IsA("TextLabel") then visiveis[#visiveis + 1] = f end
		end
		table.sort(visiveis, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		while #visiveis > MAX_AVISOS do
			table.remove(visiveis, 1):Destroy()
		end

		task.delay(4, function()
			if rotulo.Parent then rotulo:Destroy() end
		end)
	end

	Players.PlayerAdded:Connect(function(p) avisarJogador(p, true) end)
	Players.PlayerRemoving:Connect(function(p) avisarJogador(p, false) end)

	alternavel({ "avisos" }, "avisos / unavisos - mostrar quando jogadores entram e saem", function(ligar)
		avisosLigados = ligar
		return true
	end)

	-- FLYJUMP: pulo infinito, cada toque no pular dá um novo pulo, mesmo no ar (começa desligado)
	local flyJumpLigado = false

	UserInputService.JumpRequest:Connect(function()
		if not flyJumpLigado then return end
		local hum = meuHumanoid()
		if not hum or hum.Health <= 0 or hum.SeatPart then return end
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end)

	alternavel({ "flyjump", "fj" }, "flyjump ou fj / unflyjump ou unfj - pulo infinito (pula de novo no ar)", function(ligar)
		flyJumpLigado = ligar
		return true
	end)

	-- FPS 1, 2 e 3: deixa o jogo mais leve (só mexe no que o cliente controla; unfps desfaz tudo)
	-- 1 = sem sombras e sem texturas simples | 2 = + sem efeitos, animações dos outros e menos distância
	-- 3 = + tudo "lego" (plástico liso, sem malhas texturizadas)
	local Lighting = game:GetService("Lighting")
	local fpsNivel = 0
	local fpsOrig = setmetatable({}, { __mode = "k" }) -- [objeto] = { propriedade = valor original }
	local fpsRemovidos = {} -- [SurfaceAppearance] = pai original
	local fpsAnimadores = {} -- [Animator] = conexão
	local fpsConexoes = {}
	local fpsQualidade -- QualityLevel original
	local fpsVersao = 0

	local function fpsGuardar(obj, prop, valor)
		local t = fpsOrig[obj]
		if not t then
			t = {}
			fpsOrig[obj] = t
		end
		if t[prop] == nil then t[prop] = obj[prop] end
		obj[prop] = valor
	end

	local function fpsDoPersonagem(obj)
		local a = obj.Parent
		while a and a ~= workspace do
			if Players:GetPlayerFromCharacter(a) then return true end
			a = a.Parent
		end
		return false
	end

	local function fpsAplicarObjeto(obj, nivel)
		if obj:IsA("BasePart") then
			fpsGuardar(obj, "CastShadow", false)
			if nivel >= 3 then
				fpsGuardar(obj, "Material", Enum.Material.Plastic)
				fpsGuardar(obj, "Reflectance", 0)
				if obj:IsA("MeshPart") then
					fpsGuardar(obj, "TextureID", "")
					fpsGuardar(obj, "RenderFidelity", Enum.RenderFidelity.Performance)
				elseif obj:IsA("UnionOperation") then
					fpsGuardar(obj, "RenderFidelity", Enum.RenderFidelity.Performance)
				end
			end
			return
		end
		if obj:IsA("Decal") then -- Decal e Texture (rostos dos personagens ficam)
			if not fpsDoPersonagem(obj) then fpsGuardar(obj, "Transparency", 1) end
			return
		end
		if nivel >= 3 and (obj:IsA("SurfaceAppearance") or obj:IsA("Clothing") or obj:IsA("ShirtGraphic")) then
			fpsRemovidos[obj] = obj.Parent
			obj.Parent = nil
			return
		end
		if nivel >= 2 then
			if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Fire")
				or obj:IsA("Smoke") or obj:IsA("Sparkles") or obj:IsA("Light") or obj:IsA("PostEffect") then
				if obj.Enabled then fpsGuardar(obj, "Enabled", false) end -- os efeitos que já estão desligados (inclusive os do script) ficam como estão
			elseif obj:IsA("Animator") and not fpsAnimadores[obj] then
				local meu = player.Character
				if not (meu and obj:IsDescendantOf(meu)) then
					for _, t in ipairs(obj:GetPlayingAnimationTracks()) do t:Stop(0) end
					fpsAnimadores[obj] = obj.AnimationPlayed:Connect(function(t) t:Stop(0) end)
				end
			end
		end
	end

	local function fpsRestaurar()
		for _, c in ipairs(fpsConexoes) do c:Disconnect() end
		table.clear(fpsConexoes)
		for an, c in pairs(fpsAnimadores) do c:Disconnect() end
		table.clear(fpsAnimadores)
		for obj, t in pairs(fpsOrig) do
			for prop, valor in pairs(t) do
				pcall(function() obj[prop] = valor end)
			end
		end
		table.clear(fpsOrig)
		for obj, pai in pairs(fpsRemovidos) do
			if pai and pai.Parent then pcall(function() obj.Parent = pai end) end
		end
		table.clear(fpsRemovidos)
		if fpsQualidade then
			pcall(function() settings().Rendering.QualityLevel = fpsQualidade end)
			fpsQualidade = nil
		end
	end

	local function definirFps(nivel)
		fpsVersao += 1
		local minha = fpsVersao
		fpsRestaurar()
		fpsNivel = nivel
		if nivel == 0 then return end

		-- globais
		pcall(fpsGuardar, Lighting, "GlobalShadows", false)
		pcall(fpsGuardar, workspace.Terrain, "Decoration", false)
		if nivel >= 3 then
			pcall(function()
				local t = workspace.Terrain
				fpsGuardar(t, "WaterWaveSize", 0)
				fpsGuardar(t, "WaterReflectance", 0)
			end)
		end
		if nivel >= 2 then
			pcall(function()
				local r = settings().Rendering
				fpsQualidade = r.QualityLevel
				r.QualityLevel = Enum.QualityLevel.Level01
			end)
		end

		-- o que for criado depois também entra
		local function novoObjeto(obj) pcall(fpsAplicarObjeto, obj, fpsNivel) end
		fpsConexoes[#fpsConexoes + 1] = workspace.DescendantAdded:Connect(novoObjeto)
		fpsConexoes[#fpsConexoes + 1] = Lighting.DescendantAdded:Connect(novoObjeto)

		-- o que já existe (em lotes, para não travar)
		task.spawn(function()
			local contador = 0
			for _, raiz in ipairs({ Lighting, workspace }) do
				for _, obj in ipairs(raiz:GetDescendants()) do
					if fpsVersao ~= minha then return end
					pcall(fpsAplicarObjeto, obj, nivel)
					contador += 1
					if contador % 400 == 0 then task.wait() end
				end
			end
		end)
	end

	comando({ "fps1" }, "fps1 - leve: sem sombras e texturas simples", function()
		definirFps(1)
		return true
	end)
	comando({ "fps2" }, "fps2 - médio: fps1 + sem efeitos, animações dos outros e menos distância", function()
		definirFps(2)
		return true
	end)
	comando({ "fps3" }, "fps3 - máximo: fps2 + tudo lego (plástico liso, sem roupas e texturas)", function()
		definirFps(3)
		return true
	end)
	comando({ "unfps" }, "unfps - voltar o visual normal", function()
		definirFps(0)
		return true
	end)

	-- RÉGUA: com a régua ligada, toque em dois pontos do mapa e ela mostra a distância em studs
	local reguaLigada = false
	local reguaPontos = {} -- Vector3 (no máximo 2)
	local reguaObjetos = {}
	local reguaToque -- { pos = Vector2, t = tempo } do toque que está em andamento
	local COR_REGUA = Color3.fromRGB(255, 220, 80)

	local function limparRegua()
		for _, o in ipairs(reguaObjetos) do o:Destroy() end
		table.clear(reguaObjetos)
		table.clear(reguaPontos)
	end

	-- Parte invisível com um desenho que acompanha a câmera (tamanho fixo na tela)
	local function reguaAncora(posicao)
		local a = novo("Part", {
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), Position = posicao,
		}, workspace.CurrentCamera)
		reguaObjetos[#reguaObjetos + 1] = a
		return a
	end

	local function reguaMarca(posicao)
		local a = reguaAncora(posicao)
		local b = novo("BillboardGui", { Size = UDim2.fromOffset(12, 12), AlwaysOnTop = true }, a)
		local ponto = novo("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = COR_REGUA,
		}, b)
		novo("UICorner", { CornerRadius = UDim.new(1, 0) }, ponto)
		novo("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5 }, ponto)
	end

	local function reguaLinha(p1, p2)
		local dist = (p2 - p1).Magnitude
		if dist > 0.01 then
			local linha = novo("Part", {
				Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
				Material = Enum.Material.Neon, Color = COR_REGUA,
				Size = Vector3.new(0.12, 0.12, dist),
				CFrame = CFrame.lookAt(p1, p2) * CFrame.new(0, 0, -dist / 2),
			}, workspace.CurrentCamera)
			reguaObjetos[#reguaObjetos + 1] = linha
		end

		local meio = reguaAncora((p1 + p2) / 2)
		local b = novo("BillboardGui", {
			Size = UDim2.fromOffset(110, 24), StudsOffset = Vector3.new(0, 1.5, 0), AlwaysOnTop = true,
		}, meio)
		novo("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(18, 18, 22),
			BackgroundTransparency = 0.15,
			Text = string.format("%.1f studs", dist),
			TextColor3 = COR_REGUA,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
		}, b)
		novo("UICorner", { CornerRadius = UDim.new(0, 6) }, b:FindFirstChildOfClass("TextLabel"))
	end

	-- Onde o toque bateu no mapa (ignora o seu personagem)
	local function reguaPontoDoToque(posTela)
		local cam = workspace.CurrentCamera
		local raio = cam:ScreenPointToRay(posTela.X, posTela.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character, cam }
		local res = workspace:Raycast(raio.Origin, raio.Direction * 5000, params)
		return res and res.Position
	end

	local function reguaTocou(posTela)
		local ponto = reguaPontoDoToque(posTela)
		if not ponto then return end
		if #reguaPontos >= 2 then limparRegua() end -- terceiro toque recomeça
		reguaPontos[#reguaPontos + 1] = ponto
		reguaMarca(ponto)
		if #reguaPontos == 2 then reguaLinha(reguaPontos[1], reguaPontos[2]) end
	end

	UserInputService.InputBegan:Connect(function(input, processado)
		if not reguaLigada or processado then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			reguaToque = { pos = Vector2.new(input.Position.X, input.Position.Y), t = os.clock() }
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local ini = reguaToque
		if not ini then return end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
		reguaToque = nil
		if not reguaLigada then return end
		local fim = Vector2.new(input.Position.X, input.Position.Y)
		-- só conta toque curto e parado (arrastar é mexer a câmera)
		if (fim - ini.pos).Magnitude > 12 or os.clock() - ini.t > 0.45 then return end
		reguaTocou(fim)
	end)

	alternavel({ "regua", "ruler" }, "regua / unregua - toque em 2 pontos e veja a distância em studs", function(ligar)
		reguaLigada = ligar
		reguaToque = nil
		limparRegua()
		return true
	end)

	-- FREECAM: câmera livre enquanto o personagem fica parado
	-- Andar: analógico/WASD (vai para onde a câmera olha) | Subir/descer: Espaço/E e Shift/Q ou inclinar a câmera
	-- Girar: arrastar o dedo na tela (celular) ou segurar o botão direito do mouse (PC)
	local fcLigada = false
	local fcVel = 60
	local fcYaw, fcPitch, fcPos = 0, 0, Vector3.zero
	local fcAncoradaAntes
	local fcRaiz
	local fcConexoes = {}
	local FC_NOME_LOOP = "FreecamScript"

	local function pararFreecam()
		if not fcLigada then return end
		fcLigada = false
		pcall(function() RunService:UnbindFromRenderStep(FC_NOME_LOOP) end)
		for _, c in ipairs(fcConexoes) do c:Disconnect() end
		table.clear(fcConexoes)

		if fcRaiz and fcRaiz.Parent and fcAncoradaAntes ~= nil then
			fcRaiz.Anchored = fcAncoradaAntes
		end
		fcRaiz, fcAncoradaAntes = nil, nil

		local cam = workspace.CurrentCamera
		local hum = meuHumanoid()
		cam.CameraType = Enum.CameraType.Custom
		if hum then cam.CameraSubject = hum end
	end

	local function iniciarFreecam(vel)
		fcVel = vel
		if fcLigada then return true end
		local raiz = pegarPersonagem()
		if not raiz then return false, "Sem personagem vivo" end

		local cam = workspace.CurrentCamera
		local look = cam.CFrame.LookVector
		fcYaw = math.atan2(-look.X, -look.Z)
		fcPitch = math.asin(math.clamp(look.Y, -1, 1))
		fcPos = cam.CFrame.Position

		fcLigada = true
		fcRaiz = raiz
		fcAncoradaAntes = raiz.Anchored
		raiz.Anchored = true -- personagem parado
		cam.CameraType = Enum.CameraType.Scriptable

		-- Girar a câmera
		fcConexoes[#fcConexoes + 1] = UserInputService.InputChanged:Connect(function(input, processado)
			local t = input.UserInputType
			local girar = false
			if t == Enum.UserInputType.MouseMovement then
				girar = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			elseif t == Enum.UserInputType.Touch then
				girar = not processado -- o analógico e os botões já "consomem" o toque
			end
			if not girar then return end
			fcYaw = fcYaw - input.Delta.X * 0.005
			fcPitch = math.clamp(fcPitch - input.Delta.Y * 0.005, -math.rad(89), math.rad(89))
		end)

		-- Renascer/morrer sai da freecam
		fcConexoes[#fcConexoes + 1] = player.CharacterAdded:Connect(pararFreecam)

		RunService:BindToRenderStep(FC_NOME_LOOP, Enum.RenderPriority.Camera.Value + 1, function(dt)
			local r, hum = pegarPersonagem()
			if not r then
				pararFreecam()
				return
			end
			local c = workspace.CurrentCamera
			if c.CameraType ~= Enum.CameraType.Scriptable then c.CameraType = Enum.CameraType.Scriptable end
			r.Anchored = true -- o jogo pode ter soltado

			local dir = direcaoDeVoo(hum)
			fcPos = fcPos + dir * fcVel * math.min(dt, 0.1)
			c.CFrame = CFrame.new(fcPos) * CFrame.Angles(0, fcYaw, 0) * CFrame.Angles(fcPitch, 0, 0)
		end)
		return true
	end

	alternavel({ "freecam", "fc" }, "freecam [velocidade] / unfreecam - câmera livre com o personagem parado", function(ligar, args)
		if not ligar then
			pararFreecam()
			return true
		end
		local n = args[1] and tonumber(args[1]) or fcVel
		if not n or n < 1 or n > 500 then return false, "freecam: use uma velocidade de 1 a 500" end
		return iniciarFreecam(n)
	end)

	-- ORBITAR: gira em volta de um jogador, atravessando paredes. Velocidade em graus por segundo, distância em studs
	local pararSeguir -- definido no SEGUIR, mais abaixo
	local pararCabeca -- definido no SENTAR NA CABEÇA, mais abaixo
	local orbLigada = false
	local orbAlvo -- Player
	local orbVel, orbDist = 90, 12
	local orbAngulo = 0
	local orbConexoes = {}
	local orbColisoes = {}
	local orbPlataformaAntes = false
	local orbHum, orbRaiz

	-- Tira o corpo de dentro de uma parede (sobe até achar espaço livre)
	local function orbLivrar(raiz)
		local char = raiz.Parent
		if not char then return end
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local tam = char:GetExtentsSize()
		local cf = raiz.CFrame
		for i = 0, 40 do
			local c = cf + Vector3.new(0, i * 3, 0)
			local livre = true
			for _, parte in ipairs(workspace:GetPartBoundsInBox(c, tam, params)) do
				if parte.CanCollide then livre = false break end
			end
			if livre then
				raiz.CFrame = c
				raiz.AssemblyLinearVelocity = Vector3.zero
				return
			end
		end
	end

	local function pararOrbita()
		if not orbLigada then return end
		orbLigada = false
		for _, c in ipairs(orbConexoes) do c:Disconnect() end
		table.clear(orbConexoes)
		if orbRaiz and orbRaiz.Parent then orbLivrar(orbRaiz) end
		if not estado.noclip then -- com o Noclip ligado, quem manda na colisão é ele
			for d in pairs(orbColisoes) do
				if d.Parent then d.CanCollide = true end
			end
		end
		table.clear(orbColisoes)
		if orbHum and orbHum.Parent then orbHum.PlatformStand = orbPlataformaAntes end
		orbAlvo, orbRaiz, orbHum = nil, nil, nil
	end

	local function iniciarOrbita(alvoJogador)
		local raiz, hum = pegarPersonagem()
		if not raiz then return false, "Sem personagem vivo" end
		local char = raiz.Parent
		pararOrbita()
		if pararSeguir then pararSeguir() end
		if pararCabeca then pararCabeca() end
		if estado.fly then definirFly(false) end -- o Fly brigaria com o movimento

		orbLigada = true
		orbAlvo, orbRaiz, orbHum = alvoJogador, raiz, hum
		orbAngulo = 0
		orbPlataformaAntes = hum.PlatformStand
		hum.PlatformStand = true

		-- começa do lado em que você já está
		local alvoRaiz = alvoJogador.Character and alvoJogador.Character:FindFirstChild("HumanoidRootPart")
		if alvoRaiz then
			local d = raiz.Position - alvoRaiz.Position
			if Vector3.new(d.X, 0, d.Z).Magnitude > 0.1 then orbAngulo = math.atan2(d.Z, d.X) end
		end

		-- colisão desligada a cada passo da física (o Humanoid religa sozinho em algumas partes)
		orbConexoes[#orbConexoes + 1] = RunService.Stepped:Connect(function()
			if not (orbRaiz and orbRaiz.Parent) then return end
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") and d.CanCollide then
					orbColisoes[d] = true
					d.CanCollide = false
				end
			end
		end)

		orbConexoes[#orbConexoes + 1] = RunService.RenderStepped:Connect(function(dt)
			if not (orbRaiz and orbRaiz.Parent) or orbHum.Health <= 0 then
				pararOrbita()
				return
			end
			if not (orbAlvo and orbAlvo.Parent) then -- o jogador saiu do servidor
				pararOrbita()
				return
			end
			local centroRaiz = orbAlvo.Character and orbAlvo.Character:FindFirstChild("HumanoidRootPart")
			if not centroRaiz then return end -- renascendo: espera

			orbAngulo = orbAngulo + math.rad(orbVel) * math.min(dt, 0.1)
			local centro = centroRaiz.Position
			local pos = centro + Vector3.new(math.cos(orbAngulo), 0, math.sin(orbAngulo)) * orbDist
			local olhar = Vector3.new(centro.X, pos.Y, centro.Z) -- de frente para o jogador, sem inclinar
			orbRaiz.CFrame = CFrame.lookAt(pos, olhar)
			orbRaiz.AssemblyLinearVelocity = Vector3.zero
			orbRaiz.AssemblyAngularVelocity = Vector3.zero
		end)

		-- renascer sai da órbita
		orbConexoes[#orbConexoes + 1] = player.CharacterAdded:Connect(pararOrbita)
		return true
	end

	alternavel({ "orbitar", "orbit" }, "orbitar <jogador> [velocidade] [distância] / unorbitar - girar em volta de um jogador", function(ligar, args)
		if not ligar then
			pararOrbita()
			return true
		end
		if not args[1] then return false, "Uso: orbitar <jogador> [velocidade] [distância]" end

		-- só números com a órbita ligada = muda velocidade e distância ao vivo
		local soNumero = tonumber(args[1]) ~= nil
		local velTexto, distTexto = args[2], args[3]
		if soNumero then velTexto, distTexto = args[1], args[2] end

		local vel, dist = orbVel, orbDist
		if velTexto then
			vel = tonumber(velTexto)
			if not vel or vel == 0 or math.abs(vel) > 1440 then return false, "velocidade: de 1 a 1440 (negativo gira ao contrário)" end
		end
		if distTexto then
			dist = tonumber(distTexto)
			if not dist or dist < 2 or dist > 500 then return false, "distância: de 2 a 500 studs" end
		end

		if soNumero then
			if not orbLigada then return false, "Uso: orbitar <jogador> [velocidade] [distância]" end
			orbVel, orbDist = vel, dist
			return true
		end

		local alvoJogador = acharJogador(args[1])
		if not alvoJogador then return false, "Jogador não encontrado: " .. args[1] end
		orbVel, orbDist = vel, dist
		return iniciarOrbita(alvoJogador)
	end)

	-- SEGUIR: longe (mais de SEGUIR_LONGE studs) vai em dash; perto anda até SEGUIR_ATRAS studs atrás do jogador e pula se travar
	local SEGUIR_LONGE, SEGUIR_ATRAS = 80, 5
	local SEGUIR_VEL_DASH = 400 -- studs por segundo no dash do seguir
	local segLigado = false
	local segAlvo -- Player
	local segConexoes = {}
	local segProximoDash = 0
	local segParadoDesde -- quando começou a ficar travado
	local segUltimoPulo = 0
	local segUltimoMover = 0
	local segHum

	function pararSeguir()
		if not segLigado then return end
		segLigado = false
		for _, c in ipairs(segConexoes) do c:Disconnect() end
		table.clear(segConexoes)
		if segHum and segHum.Parent then
			segHum:Move(Vector3.zero)
			segHum:MoveTo(segHum.Parent:GetPivot().Position) -- para onde está
		end
		segAlvo, segHum = nil, nil
	end

	local function iniciarSeguir(alvoJogador)
		local raiz, hum = pegarPersonagem()
		if not raiz then return false, "Sem personagem vivo" end
		pararSeguir()
		pararOrbita()
		if pararCabeca then pararCabeca() end
		if estado.fly then definirFly(false) end -- seguir anda no chão

		segLigado = true
		segAlvo, segHum = alvoJogador, hum
		segProximoDash, segParadoDesde, segUltimoPulo, segUltimoMover = 0, nil, 0, 0

		segConexoes[#segConexoes + 1] = RunService.Heartbeat:Connect(function()
			local minhaRaiz, meuHum = pegarPersonagem()
			if not minhaRaiz then
				pararSeguir()
				return
			end
			if not (segAlvo and segAlvo.Parent) then -- o jogador saiu do servidor
				pararSeguir()
				return
			end
			local alvoRaiz = segAlvo.Character and segAlvo.Character:FindFirstChild("HumanoidRootPart")
			if not alvoRaiz then return end -- renascendo: espera

			local agora = os.clock()
			local ponto = alvoRaiz.Position - alvoRaiz.CFrame.LookVector * SEGUIR_ATRAS
			local dist = (alvoRaiz.Position - minhaRaiz.Position).Magnitude

			-- LONGE: dash até ficar atrás do jogador
			if dist > SEGUIR_LONGE then
				segParadoDesde = nil
				if agora >= segProximoDash then
					local duracao = math.clamp(dist / SEGUIR_VEL_DASH, 0.2, 1.5)
					segProximoDash = agora + duracao + 0.15
					iniciarDash(ponto + Vector3.new(0, 3, 0), { velocidade = SEGUIR_VEL_DASH })
				end
				return
			end
			if agora < segProximoDash then return end -- ainda no dash

			-- PERTO: anda até o ponto atrás do jogador
			local falta = Vector3.new(ponto.X - minhaRaiz.Position.X, 0, ponto.Z - minhaRaiz.Position.Z).Magnitude
			if falta > 2 then
				if agora - segUltimoMover > 0.1 then
					segUltimoMover = agora
					meuHum:MoveTo(ponto)
				end

				-- pula se estiver tentando andar e não sair do lugar, ou se o jogador estiver bem mais alto
				local v = minhaRaiz.AssemblyLinearVelocity
				local vel = Vector3.new(v.X, 0, v.Z).Magnitude
				if vel < 2 and falta > 3 then
					segParadoDesde = segParadoDesde or agora
				else
					segParadoDesde = nil
				end
				local travado = segParadoDesde and agora - segParadoDesde > 0.35
				local alvoMaisAlto = alvoRaiz.Position.Y - minhaRaiz.Position.Y > 4 and falta < 12
				if (travado or alvoMaisAlto) and agora - segUltimoPulo > 0.6 then
					segUltimoPulo = agora
					meuHum.Jump = true
				end
			else
				segParadoDesde = nil
			end
		end)

		-- renascer para de seguir
		segConexoes[#segConexoes + 1] = player.CharacterAdded:Connect(pararSeguir)
		return true
	end

	alternavel({ "seguir", "follow" }, "seguir <jogador> / unseguir - seguir um jogador (longe: dash, perto: anda atrás dele)", function(ligar, args)
		if not ligar then
			pararSeguir()
			return true
		end
		if #args == 0 then return false, "Uso: seguir <jogador>" end
		local alvoJogador = acharJogador(table.concat(args, " "))
		if not alvoJogador then return false, "Jogador não encontrado: " .. table.concat(args, " ") end
		return iniciarSeguir(alvoJogador)
	end)

	-- SENTAR NA CABEÇA: senta na cabeça do jogador escolhido e vai junto com ele.
	-- Só sai se ele reiniciar (ou morrer/sair do servidor) ou se você pular.
	local cabLigada = false
	local cabAlvo -- Player
	local cabAlvoChar
	local cabConexoes = {}
	local cabColisoes = {}
	local cabRaiz, cabHum

	function pararCabeca()
		if not cabLigada then return end
		cabLigada = false
		for _, c in ipairs(cabConexoes) do c:Disconnect() end
		table.clear(cabConexoes)
		if not estado.noclip then -- com o Noclip ligado, quem manda na colisão é ele
			for d in pairs(cabColisoes) do
				if d.Parent then d.CanCollide = true end
			end
		end
		table.clear(cabColisoes)
		if cabHum and cabHum.Parent then cabHum.Sit = false end
		if cabRaiz and cabRaiz.Parent then cabRaiz.AssemblyLinearVelocity = Vector3.zero end
		cabAlvo, cabAlvoChar, cabRaiz, cabHum = nil, nil, nil, nil
	end

	local function iniciarCabeca(alvoJogador)
		local raiz, hum = pegarPersonagem()
		if not raiz then return false, "Sem personagem vivo" end
		local alvoChar = alvoJogador.Character
		local alvoHum = alvoChar and alvoChar:FindFirstChildOfClass("Humanoid")
		if not (alvoChar and alvoChar:FindFirstChild("Head") and alvoHum and alvoHum.Health > 0) then
			return false, alvoJogador.DisplayName .. " indisponível"
		end

		pararCabeca()
		pararOrbita()
		pararSeguir()
		if estado.fly then definirFly(false) end

		cabLigada = true
		cabAlvo, cabAlvoChar, cabRaiz, cabHum = alvoJogador, alvoChar, raiz, hum
		local char = raiz.Parent
		hum.Sit = true

		local function acompanhar()
			if not (cabRaiz and cabRaiz.Parent) or cabHum.Health <= 0 then
				pararCabeca()
				return
			end
			-- ele reiniciou, morreu ou saiu: solta
			local ch = cabAlvo and cabAlvo.Parent and cabAlvo.Character
			local h = ch and ch:FindFirstChildOfClass("Humanoid")
			if ch ~= cabAlvoChar or not h or h.Health <= 0 then
				pararCabeca()
				return
			end
			local cabeca = ch:FindFirstChild("Head")
			local alvoRaiz = ch:FindFirstChild("HumanoidRootPart")
			if not (cabeca and alvoRaiz) then return end

			if not cabHum.Sit then cabHum.Sit = true end
			local pos = cabeca.Position + Vector3.new(0, cabeca.Size.Y / 2 + 1.1, 0)
			cabRaiz.CFrame = CFrame.new(pos) * alvoRaiz.CFrame.Rotation
			cabRaiz.AssemblyLinearVelocity = Vector3.zero
			cabRaiz.AssemblyAngularVelocity = Vector3.zero
		end

		-- sem colisão com o jogador (não empurra nem enrosca)
		cabConexoes[#cabConexoes + 1] = RunService.Stepped:Connect(function()
			if not (cabRaiz and cabRaiz.Parent) then return end
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") and d.CanCollide then
					cabColisoes[d] = true
					d.CanCollide = false
				end
			end
			acompanhar()
		end)
		cabConexoes[#cabConexoes + 1] = RunService.RenderStepped:Connect(acompanhar)

		-- pular sai
		cabConexoes[#cabConexoes + 1] = UserInputService.JumpRequest:Connect(pararCabeca)
		cabConexoes[#cabConexoes + 1] = player.CharacterAdded:Connect(pararCabeca)
		return true
	end

	alternavel({ "hsit", "headsit", "sentarcabeca" }, "hsit <jogador> / unhsit - sentar na cabeça de um jogador (pular sai)", function(ligar, args)
		if not ligar then
			pararCabeca()
			return true
		end
		if #args == 0 then return false, "Uso: hsit <jogador>" end
		local alvoJogador = acharJogador(table.concat(args, " "))
		if not alvoJogador then return false, "Jogador não encontrado: " .. table.concat(args, " ") end
		return iniciarCabeca(alvoJogador)
	end)

	comando({ "menu", "m" }, "menu ou m - abrir/fechar o menu", function()
		alternarPainel()
		return true, aberto and "Menu aberto" or "Menu fechado"
	end)

	comando({ "cmds", "help", "ajuda", "?" }, "cmds, help ou ajuda - mostrar a lista completa", function()
		manterBarra = true
		return true
	end)

	----------------------------------------------------------
	-- GALERIA SECRETA: o comando "xv" abre/fecha. Não aparece no menu, na ajuda
	-- nem na lista de sugestões da barra (por isso não usa comando()).
	-- 12 espaços: 3 fileiras com 4 fotos. Toque numa foto para ampliar; toque de novo para voltar.
	----------------------------------------------------------
	do
		-- >>> COLE AQUI OS LINKS DAS 12 FOTOS (deixe "" nos espaços vazios) <<<
		local LINKS_GALERIA = {
			"", "", "", "",
			"", "", "", "",
			"", "", "", "",
		}
		local COLUNAS, LINHAS = 4, 3
		local galeria, ampliada
		local fotos = {}   -- [i] = ImageButton do espaço
		local carregada = false

		local function baixar(i, link)
			local arquivo = "galeria_foto" .. i .. ".png"
			local marca = "galeria_foto" .. i .. ".txt" -- guarda qual link gerou o arquivo
			local atual = isfile(arquivo) and isfile(marca) and readfile(marca) == link
			if not atual then
				writefile(arquivo, game:HttpGet(link))
				writefile(marca, link)
			end
			return getcustomasset(arquivo)
		end

		local function montar()
			local g = Instance.new("ScreenGui")
			g.Name = "Galeria"
			g.ResetOnSpawn = false
			g.IgnoreGuiInset = gui.IgnoreGuiInset
			g.DisplayOrder = 30
			g.Enabled = false
			g.Parent = playerGui

			local tela = tamanhoTela()
			local pad, altBarra = 8, 30
			local celula = (math.min(520, tela.X - 20) - pad * (COLUNAS + 1)) / COLUNAS
			local maxAlt = tela.Y - 20
			if altBarra + pad * (LINHAS + 1) + celula * LINHAS > maxAlt then -- tela baixa: diminui as fotos
				celula = (maxAlt - altBarra - pad * (LINHAS + 1)) / LINHAS
			end
			celula = math.max(celula, 20)
			local larg = pad * (COLUNAS + 1) + celula * COLUNAS
			local alt = altBarra + pad * (LINHAS + 1) + celula * LINHAS

			local p = Instance.new("Frame")
			p.Name = "PainelGaleria"
			p.Size = UDim2.fromOffset(larg, alt)
			p.Position = UDim2.fromOffset((tela.X - larg) / 2, (tela.Y - alt) / 2)
			p.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
			p.BackgroundTransparency = 0.12
			p.ClipsDescendants = true
			p.Parent = g
			Instance.new("UICorner", p).CornerRadius = UDim.new(0, 14)
			local contorno = Instance.new("UIStroke")
			contorno.Color = Color3.new(1, 1, 1)
			contorno.Thickness = 1.2
			contorno.Transparency = 0.6
			contorno.Parent = p

			-- Barra de cima: arraste para mover; ✕ fecha
			local barra = Instance.new("Frame")
			barra.Size = UDim2.new(1, 0, 0, altBarra)
			barra.BackgroundTransparency = 1
			barra.Active = true
			barra.Parent = p
			tornarMovel(barra, p)
			local fechar = Instance.new("TextButton")
			fechar.AnchorPoint = Vector2.new(1, 0)
			fechar.Position = UDim2.new(1, -4, 0, 2)
			fechar.Size = UDim2.fromOffset(26, 26)
			fechar.BackgroundTransparency = 1
			fechar.Text = "✕"
			fechar.TextColor3 = Color3.new(1, 1, 1)
			fechar.Font = Enum.Font.GothamBold
			fechar.TextSize = 16
			fechar.Parent = barra
			fechar.MouseButton1Click:Connect(function() g.Enabled = false end)

			-- Os 12 espaços (3 fileiras de 4)
			for i = 1, COLUNAS * LINHAS do
				local linha = math.floor((i - 1) / COLUNAS)
				local coluna = (i - 1) % COLUNAS
				local f = Instance.new("ImageButton")
				f.Name = "Foto" .. i
				f.Position = UDim2.fromOffset(pad + coluna * (celula + pad), altBarra + pad + linha * (celula + pad))
				f.Size = UDim2.fromOffset(celula, celula)
				f.BackgroundColor3 = Color3.new(1, 1, 1)
				f.BackgroundTransparency = 0.92
				f.AutoButtonColor = false
				f.Image = ""
				f.ScaleType = Enum.ScaleType.Crop
				f.Parent = p
				Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
				local c = Instance.new("UIStroke")
				c.Color = Color3.new(1, 1, 1)
				c.Thickness = 1
				c.Transparency = 0.75
				c.Parent = f
				fotos[i] = f
				f.MouseButton1Click:Connect(function()
					if f.Image ~= "" then
						ampliada.Image = f.Image
						ampliada.Visible = true
					end
				end)
			end

			-- Foto ampliada (cobre o painel; toque para voltar)
			ampliada = Instance.new("ImageButton")
			ampliada.Name = "Ampliada"
			ampliada.Size = UDim2.new(1, 0, 1, 0)
			ampliada.BackgroundColor3 = Color3.new(0, 0, 0)
			ampliada.BackgroundTransparency = 0.25
			ampliada.AutoButtonColor = false
			ampliada.ScaleType = Enum.ScaleType.Fit
			ampliada.ZIndex = 10
			ampliada.Visible = false
			ampliada.Parent = p
			ampliada.MouseButton1Click:Connect(function() ampliada.Visible = false end)

			galeria = g
		end

		local function carregar() -- baixa as fotos em segundo plano, só na primeira vez
			if carregada then return end
			carregada = true
			task.spawn(function()
				for i, link in ipairs(LINKS_GALERIA) do
					if link ~= "" and fotos[i] then
						local ok, imagem = pcall(baixar, i, link)
						if ok and imagem then fotos[i].Image = imagem end
					end
				end
			end)
		end

		comandos["xv"] = function()
			if not galeria then montar() end
			galeria.Enabled = not galeria.Enabled
			if galeria.Enabled then
				ampliada.Visible = false
				carregar()
			end
			return true -- sem mensagem: ninguém precisa saber que existe
		end
	end

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

	-- Retorna true se o comando pediu para a barra continuar aberta (cmds)
	local function executarLinha(texto)
		texto = texto:match("^%s*(.-)%s*$")
		if texto == "" then return false end

		local mensagens, tudoCerto = {}, true
		for trecho in texto:gmatch("[^,]+") do
			local ok, msg = executarComando(trecho)
			if msg then mensagens[#mensagens + 1] = msg end
			tudoCerto = tudoCerto and ok
		end

		if #mensagens > 0 then
			mostrarToast(table.concat(mensagens, "\n"), tudoCerto)
		end
		if tudoCerto then
			if manterBarra then
				manterBarra = false
				caixaCmd.Text = ""
				abrirAjuda()
				task.defer(function() caixaCmd:CaptureFocus() end)
				return true
			end
			caixaCmd.Text = ""
		end
		return false
	end

	-- Parou de digitar (Enter, teclado fechado ou toque fora) = a barra volta para a tira fina
	caixaCmd.FocusLost:Connect(function(enter)
		if not barraAberta then return end
		if enter then
			-- executa o comando e só depois fecha
			if not executarLinha(caixaCmd.Text) then fecharBarra() end
			return
		end
		if os.clock() - tAbriu < 0.35 then return end -- foco ainda está pegando no celular
		task.delay(0.12, function()
			-- tocar num comando da lista completa o texto e devolve o foco: não fecha
			if not barraAberta or caixaCmd:IsFocused() or tocandoPainel then return end
			fecharBarra()
		end)
	end)

end
iniciarTeclado()

------------------------------------------------------------
-- CONFIGURAÇÕES POR FUNÇÃO (categoria "Config": um liga/desliga para cada função)
-- Vale na hora e fica salvo em "config_script.json" (writefile do executor;
-- sem ele vale só até fechar o jogo).
------------------------------------------------------------
do
	local HttpService = game:GetService("HttpService")
	local ARQUIVO_CFG = "config_script.json"
	local CFG = MENU.cfg
	local ordem = 300
	local itens = {}

	local function salvar()
		if not (typeof(writefile) == "function") then return end
		local t = {}
		for _, it in ipairs(itens) do t[it.chave] = it.get() end
		pcall(function() writefile(ARQUIVO_CFG, HttpService:JSONEncode(t)) end)
	end

	local function aplicar(it, v)
		v = v and true or false
		it.set(v)
		it.botao.Text = it.rotulo .. ": " .. (v and "LIGADO" or "DESLIGADO")
		VIDRO.aplicar(it.botao, v)
	end

	local function novoBotao(texto)
		ordem = ordem + 1
		local f = Instance.new("Frame")
		f.Name = "CelulaConfig" .. ordem
		f.LayoutOrder = ordem
		f.Size = UDim2.new(1, 0, 0, ALTURA_BOTAO)
		f.BackgroundTransparency = 1
		f:SetAttribute("Categoria", "Config")
		f.Visible = (MENU.atual == "Config")
		f.Parent = grade
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, 0, 1, 0)
		b.Text = texto
		b.Font = Enum.Font.GothamBold
		b.TextSize = 14
		b.TextScaled = true
		b.Parent = f
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = 14
		lim.MinTextSize = 8
		lim.Parent = b
		return b
	end

	local function opcao(chave, texto, get, set)
		local b = novoBotao(texto)
		local it = { chave = chave, rotulo = texto, get = get, set = set, padrao = get(), botao = b }
		itens[#itens + 1] = it
		aplicar(it, get())
		b.MouseButton1Click:Connect(function() aplicar(it, not get()) salvar() end)
	end

	opcao("super", "FLY: SUPER VOO", function() return SUPER.habilitado ~= false end, function(v) SUPER.habilitado = v end)
	opcao("swimEfeitos", "SWIM: EFEITOS", function() return CFG.swimEfeitos end, function(v) CFG.swimEfeitos = v end)
	opcao("noclipTransp", "NOCLIP: TRANSPARÊNCIA", function() return CFG.noclipTransp end, function(v) CFG.noclipTransp = v end)
	opcao("barraVida", "ESP: BARRA DE VIDA", function() return CFG.barraVida end, function(v) CFG.barraVida = v end)
	opcao("alertaChams", "CHAMS: ALERTA VERMELHO", function() return CFG.alertaChams end, function(v) CFG.alertaChams = v end)
	opcao("sonar", "XRAY: SONAR", function() return MENU.sonar.ligado end, function(v) MENU.sonar.ligado = v end)
	opcao("tpInstantaneo", "TP: INSTANTÂNEO", function() return CFG.tpInstantaneo end, function(v) CFG.tpInstantaneo = v end)
	opcao("tpToolInstantaneo", "TPTOOL: INSTANTÂNEO", function() return CFG.tpToolInstantaneo end, function(v) CFG.tpToolInstantaneo = v end)

	local br = novoBotao("RESTAURAR PADRÕES")
	VIDRO.aplicar(br, false)
	br.MouseButton1Click:Connect(function()
		for _, it in ipairs(itens) do aplicar(it, it.padrao) end
		salvar()
	end)

	-- carrega o que estava salvo
	pcall(function()
		if typeof(isfile) == "function" and typeof(readfile) == "function" and isfile(ARQUIVO_CFG) then
			local t = HttpService:JSONDecode(readfile(ARQUIVO_CFG))
			for _, it in ipairs(itens) do
				if t[it.chave] ~= nil then aplicar(it, t[it.chave]) end
			end
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
	atualizarShiftLock()
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
	atualizarSetasVFly()
	atualizarBotaoVertical()
end)
