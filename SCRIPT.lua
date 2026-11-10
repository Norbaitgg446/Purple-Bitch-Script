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
	-- Deixe "" nas que não for usar. Pode usar de 1 a 4.
	local LINKS_FOTOS = {
		"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTjMDaLibyw_z3-75JPKtAxs7BIO66Fqutk0A_NLEZARoPFTCiNsN0-l5N7&s=10", -- foto 1
		"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRo72Vsot2aEMyHqbb1Nij43mYDpQUqGgGLHYvYOu84BD4Y-agSFZXu4U0&s=10", -- foto 2
		"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTdsojKLsiKD8WGLWCtDIQ5OHQJaT_35CgmRYYBYCt6sZKTzGT181tVR6Y&s=10", -- foto 3
		"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcR3fzheHWw3pkVYtTMu1lK00H1X86EpBXBfg1FsQWxCsqWsxw_YgGjt9MQ&s=10", -- foto 4
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

-- Duas colunas lado a lado; cada coluna é uma lista de cima pra baixo.
-- Ordens 1 a ULTIMA_COLUNA_ESQ ficam na esquerda, o resto na direita.
local ULTIMA_COLUNA_ESQ = 9
local function criarColuna(nome, posX, lado)
	local col = Instance.new("Frame")
	col.Name = nome
	col.Position = UDim2.new(posX, lado, 0, 0)
	col.Size = UDim2.new(0.5, -ESPACO / 2, 0, 0)
	col.AutomaticSize = Enum.AutomaticSize.Y
	col.BackgroundTransparency = 1
	col.Parent = grade
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, ESPACO)
	lay.Parent = col
	return col
end
local colunaEsq = criarColuna("ColunaEsquerda", 0, 0)
local colunaDir = criarColuna("ColunaDireita", 0.5, ESPACO / 2)

-- Cria uma célula: botão liga/desliga (+ caixa de velocidade opcional, colada no botão)
local function criarLinha(ordem, nome, comVelocidade, velocidadePadrao)
	local celulaFrame = Instance.new("Frame")
	celulaFrame.Name = "Celula" .. nome
	celulaFrame.LayoutOrder = ordem
	celulaFrame.Size = UDim2.new(1, 0, 0, ALTURA_BOTAO)
	celulaFrame.BackgroundTransparency = 1
	celulaFrame.Parent = (ordem <= ULTIMA_COLUNA_ESQ) and colunaEsq or colunaDir

	local b = Instance.new("TextButton")
	b.Name = "Botao" .. nome
	b.Position = UDim2.new(0, 0, 0, 0)
	b.Size = UDim2.new(0.68, 0, 1, 0) -- todos os botões têm o mesmo tamanho
	b.Text = nome .. ": DESLIGADO"
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
botaoTP.Text = "TP"
local botaoSpawns = criarLinha(11, "SPAWNS", false)
botaoSpawns.Text = "SPAWNS"
local botaoView = criarLinha(12, "VIEW", false)
botaoView.Text = "VIEW"
local botaoRejoin = criarLinha(13, "REJOIN", false)
botaoRejoin.Text = "REJOIN"


local dica = Instance.new("TextLabel")
dica.Name = "Dicas"
dica.LayoutOrder = 2
dica.Size = UDim2.new(1, 0, 0, 0)
dica.AutomaticSize = Enum.AutomaticSize.Y
dica.BackgroundTransparency = 1
dica.TextWrapped = true
dica.TextXAlignment = Enum.TextXAlignment.Left
dica.TextYAlignment = Enum.TextYAlignment.Top
dica.Text = "Mover: arraste o título do painel ou o botão MENU. Tamanho: arraste o ◢ do canto.\nFly: WASD/analógico para mover, mire a câmera para subir/descer.\nEspaço/E = subir, Shift/Q = descer.\nVFLY: use sentado em um veículo. Aparecem setas na tela (esquerda: ▲▼◀▶ andam; direita: SOBE/DESCE) para jogos em que o analógico não move o veículo; arraste o ≡ para mudar de lugar.\nNOCLIP: atravessa paredes (sem o Fly você cai pelo chão).\nSWIM: nada no ar como se estivesse na água.\nSPAWNS: salve posições (ficam gravadas por jogo, se o executor permitir), renomeie, veja a distância e clique em IR para voar até lá. O nome aparece discreto em cima do spawn quando você está perto.\nVIEW: escolha um jogador para ver pela câmera dele (espectar). Na barra de cima, ◀ ▶ trocam de jogador e SAIR volta pra você. Comando: view <jogador> / unview.\nTP: digite na busca para filtrar; a lista mostra a distância. Clique no nome (ou dê Enter na busca para ir no primeiro da lista) para voar até o jogador em velocidade supersônica.\nXRAY: deixa o mapa transparente (caixa: 0 = normal, 0.95 = quase invisível).\nTPTOOL: dá um item no inventário; equipe e clique/toque onde quer ir (você voa até lá em uma fração de segundo, com os efeitos de velocidade e o estrondo na chegada).\nSHIFTLOCK: mostra o cadeado na tela (arraste para mover). Toque nele: azul = travado, branco = solto. O ⇄ embaixo troca o ombro da câmera. Comando: sl / unsl.\nAIMBOT: bolinha verde no centro = alcance (digite o tamanho na caixa). A mira muda ao travar: na cabeça os tracinhos fecham (vermelho), no tronco eles abrem (laranja); a vida do alvo aparece pequena no canto da bolinha. ALVO troca cabeça/tronco, PAREDE = mirar através de paredes, TIME = ignorar seu time. Comando: aim [tamanho] / unaim.\nBARRA DE COMANDOS: a barrinha "> comandos" no canto de baixo da tela (arraste para mover). Toque nela e a barra abre com a lista de comandos em cima, que filtra enquanto você digita (toque num comando para completar). Ex.: fly 80, unfly, np, xy, rj. No PC, a tecla , (vírgula) também abre a barra. Vários comandos de uma vez: fly 80, np."
dica.TextColor3 = Color3.fromRGB(170, 170, 180)
dica.Font = Enum.Font.Gotham
dica.TextSize = 12
dica.Parent = conteudo

-- (os botões ▲▼ foram removidos; subir/descer = inclinar a câmera, ou Espaço/E e Shift/Q no teclado)
local function atualizarBotaoVertical()
	if not (estado.fly or estado.vfly or estado.swim) then
		subindo, descendo = false, false
	end
end

local function pintarBotao(b, nome, ligado)
	b.Text = nome .. (ligado and ": LIGADO" or ": DESLIGADO")
	VIDRO.aplicar(b, ligado)
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
	fundoVida.Position = UDim2.new(0.5, 0, 0, 56)
	fundoVida.Size = UDim2.fromOffset(90, 6)
	fundoVida.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	fundoVida.BackgroundTransparency = 0.3
	fundoVida.BorderSizePixel = 0
	fundoVida.Parent = conteudo
	Instance.new("UICorner", fundoVida).CornerRadius = UDim.new(1, 0)
	local contornoVida = Instance.new("UIStroke")
	contornoVida.Color = Color3.new(0, 0, 0)
	contornoVida.Thickness = 1
	contornoVida.Transparency = 0.4
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
	icone.Position = UDim2.new(0.5, 0, 0, 0)
	icone.Size = UDim2.fromOffset(18, 18)
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
	iconeTexto.TextSize = 14
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

local function atualizarESP()
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

local function definirESP(v)
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
				local cor = corPorDistancia(dist)
				h.FillColor = cor
				h.OutlineColor = cor

				-- pulso suave: mais rápido de perto, mais lento de longe; cada jogador com fase própria
				local fase = (p.UserId % 628) / 100
				local velocidade = 1.6 + 1.6 * (1 - math.clamp(dist / DIST_LONGE, 0, 1))
				local onda = math.sin(agora * velocidade + fase)
				h.FillTransparency = math.clamp(TRANSPARENCIA_PREENCHIMENTO + onda * AMPLITUDE_PULSO, 0, 1)
				h.OutlineTransparency = 0.08 + (onda * 0.5 + 0.5) * 0.17
			end
		end
	end)
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
local vBV, vBG -- (VFLY) declarados aqui para o efeito de velocidade também enxergar

-- POSE DE HERÓI: mexe nas juntas do corpo (R15 e R6) enquanto voa
local poseMov = 0 -- 0 = parado (em pé), 1 = voando (deitado, braço esticado)
local poseChar, poseJuntas
local poseLean = 0 -- inclinação calculada em atualizarFly e usada na pose
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
	if animateDesligado then
		animateDesligado.Disabled = false
		animateDesligado = nil
	end
end

local function aplicarPoseFly(char, hum, inclinacao)
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
		-- PARADO: mãos na cintura (braço abre um pouco, gira e o cotovelo dobra)
		-- VOANDO: braço direito esticado à frente, esquerdo ao lado do corpo
		pose(j.ombroD, CFrame.Angles(0, 0, R(35)) * CFrame.Angles(0, R(90), 0), CFrame.Angles(R(170), 0, 0))
		pose(j.ombroE, CFrame.Angles(0, 0, -R(35)) * CFrame.Angles(0, -R(90), 0), CFrame.Angles(R(-15), 0, 0))
		pose(j.cotoveloD, CFrame.Angles(R(105), 0, 0), CFrame.new())
		pose(j.cotoveloE, CFrame.Angles(R(105), 0, 0), CFrame.Angles(R(25), 0, 0))
		-- pernas: levemente abertas parado, esticadas para trás voando
		pose(j.quadrilD, CFrame.Angles(0, 0, R(6)), CFrame.Angles(R(-10), 0, 0))
		pose(j.quadrilE, CFrame.Angles(0, 0, -R(6)), CFrame.Angles(R(-25), 0, 0))
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

local function pararFly()
	limparPoseFly()
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
	flyBG.D = 1200
	flyBG.CFrame = raiz.CFrame
	flyBG.Parent = raiz

	hum.PlatformStand = true
end

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

		-- carga do super voo: enche enquanto fica na velocidade máxima, esvazia se desacelerar
		if SUPER.ativo then
			if alvo < 0.5 then
				SUPER.ativo = false
				carga = 0
			end
		else
			if efeitoIntens >= 0.95 and (estado.fly or estado.vfly) then
				carga = math.min(1, carga + dt / SUPER.tempoCarga)
			else
				carga = math.max(0, carga - dt * 1.5)
			end
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
	local alvoVel = dir * velocidadeFly * MULTIPLICADOR_FLY * (SUPER.ativo and SUPER.mult or 1)
	flyBV.Velocity = flyBV.Velocity:Lerp(alvoVel, 1 - math.exp(-dt * (SUPER.ativo and 12 or 8)))

	-- O personagem vira para onde a câmera aponta; em movimento deita como herói voando
	local movendo = dir.Magnitude > 0.05
	poseMov = poseMov + ((movendo and 1 or 0) - poseMov) * (1 - math.exp(-dt * 6))

	local look = workspace.CurrentCamera.CFrame.LookVector
	local pitch = math.asin(math.clamp(look.Y, -1, 1))

	-- O corpo acompanha a câmera SEMPRE (mesmo parado):
	-- olhou pra baixo = deita de barriga pra baixo; olhou pra cima = deita de barriga pra cima
	local inclinacao = pitch * GANHO_INCLINACAO
	if POSE_HEROI then
		-- ao se mover, ainda "deita" mais (pose de herói), mantendo a liberdade de cima/baixo
		inclinacao = math.clamp(inclinacao - math.rad(75) * poseMov, -math.rad(150), math.rad(100))
	end

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
		local alvo = CFrame.new(raiz.Position) * yaw * CFrame.Angles(inclinacao, 0, 0)
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

local function atualizarSetasVFly()
	clusterMovV.Visible = estado.vfly
	clusterAltV.Visible = estado.vfly
	if not estado.vfly then
		for k in pairs(setasV) do setasV[k] = false end
	end
end

local function pararVFly()
	ultimoVFly = nil
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

local function definirVFly(v)
	estado.vfly = v
	pintarBotao(botaoVFly, "VFLY", v)
	atualizarSetasVFly()
	atualizarBotaoVertical()
end
botaoVFly.MouseButton1Click:Connect(function() definirVFly(not estado.vfly) end)

------------------------------------------------------------
-- SWIM (nadar no ar)
------------------------------------------------------------
local swimBV
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

local function pararSwim()
	if swimBV then swimBV:Destroy() swimBV = nil end
	ultimoSwim = nil
	destravarEstadoNado()
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

local function definirSwim(v)
	estado.swim = v
	pintarBotao(botaoSwim, "SWIM", v)
	atualizarBotaoVertical()
end
botaoSwim.MouseButton1Click:Connect(function() definirSwim(not estado.swim) end)

------------------------------------------------------------
-- EFEITO DE ÁGUA DO SWIM (tela azulada, bolhas subindo, ondinhas de luz, balanço suave)
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

	-- Ondinhas de luz (faixas suaves que balançam e deslizam na parte de cima da tela)
	local ondas = {}
	for i = 1, 8 do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false
		f.Visible = false
		f.Parent = aguaGui
		local g = Instance.new("UIGradient") -- some nas pontas
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		ondas[i] = {
			frame = f,
			y = 0.05 + (i - 1) * 0.055 + math.random() * 0.02, -- altura (fração da tela)
			x = math.random(),                                  -- posição horizontal
			larg = 0.35 + math.random() * 0.35,
			vel = (0.015 + math.random() * 0.03) * (math.random() < 0.5 and -1 or 1),
			fase = math.random() * math.pi * 2,
			grossura = math.random(2, 4),
		}
	end

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

		local ligado = estado.swim and not estado.fly and swimBV ~= nil
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

		for _, o in ipairs(ondas) do
			local f = o.frame
			if agua <= 0 then
				f.Visible = false
			else
				f.Visible = true
				o.x = (o.x + o.vel * dt) % 1.4
				local y = o.y + math.sin(t * 0.9 + o.fase) * 0.012
				f.Position = UDim2.fromOffset((o.x - 0.2) * tela.X, y * tela.Y)
				f.Size = UDim2.fromOffset(o.larg * tela.X, o.grossura)
				f.BackgroundTransparency = 1 - agua * (0.18 + 0.1 * math.sin(t * 1.4 + o.fase * 2))
			end
		end

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
-- EFEITOS DO NOCLIP: paredes ficam transparentes perto de você, aura de poder, personagem translúcido
-- (tudo só no seu cliente: ninguém mais vê, e o mapa de verdade não muda)
------------------------------------------------------------
do
	local RAIO_PAREDE = 8          -- studs: paredes dentro desse raio ficam transparentes
	local TRANSP_PAREDE = 0.75     -- 0 = normal, 1 = invisível
	local TRANSP_PERSONAGEM = 0.35 -- personagem meio transparente com o noclip ligado (0 = normal)
	local COR_AURA = Color3.fromRGB(90, 200, 255)

	local afetadas = {}  -- [BasePart] = nível 0..1 (quanto já ficou transparente)
	local perto = {}     -- [BasePart] = true se está dentro do raio agora
	local nivelPersonagem = 0
	local nivelAura = 0
	local tocandoAntes = false
	local ultimaBusca = 0

	-- Aura de poder (esfera de campo de força que aparece quando você está dentro de uma parede)
	local aura = Instance.new("Part")
	aura.Name = "AuraNoclip"
	aura.Shape = Enum.PartType.Ball
	aura.Material = Enum.Material.ForceField
	aura.Color = COR_AURA
	aura.Size = Vector3.new(5, 5, 5)
	aura.Anchored = true
	aura.CanCollide = false
	aura.CanQuery = false
	aura.CanTouch = false
	aura.CastShadow = false
	aura.Transparency = 1
	aura.Parent = workspace.CurrentCamera

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Pulso (anel de energia) quando você entra em uma parede
	local function pulso(posicao)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Material = Enum.Material.Neon
		p.Color = COR_AURA
		p.Size = Vector3.new(3, 3, 3)
		p.Position = posicao
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 0.55
		p.Parent = workspace.CurrentCamera
		local t = TweenService:Create(p, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(15, 15, 15),
			Transparency = 1,
		})
		t:Play()
		t.Completed:Connect(function() p:Destroy() end)
	end

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
					d.LocalTransparencyModifier = nivelPersonagem * TRANSP_PERSONAGEM
				end
			end
		end

		-- 2) Busca (a cada 0.08s) das paredes perto e se você está dentro de alguma
		local tocando = false
		if ligado and agora - ultimaBusca > 0.08 then
			ultimaBusca = agora
			params.FilterDescendantsInstances = { char, aura }
			perto = {}
			for _, parte in ipairs(workspace:GetPartBoundsInRadius(raiz.Position, RAIO_PAREDE, params)) do
				if parte.CanCollide and parte.Transparency < 1 and not ehDeJogador(parte) then
					perto[parte] = true
					if afetadas[parte] == nil then afetadas[parte] = 0 end
				end
			end
			for _, parte in ipairs(workspace:GetPartBoundsInBox(raiz.CFrame, Vector3.new(2.5, 4.5, 2.5), params)) do
				if parte.CanCollide and not ehDeJogador(parte) then
					tocando = true
					break
				end
			end
			if tocando and not tocandoAntes then
				pulso(raiz.Position)
			end
			tocandoAntes = tocando
			aura:SetAttribute("tocando", tocando)
		elseif not ligado then
			perto = {}
			tocandoAntes = false
			aura:SetAttribute("tocando", false)
		end

		-- 3) Paredes ficando transparentes / voltando ao normal aos poucos
		local passo = 1 - math.exp(-dt * 7)
		for parte, nivel in pairs(afetadas) do
			if not parte.Parent then
				afetadas[parte] = nil
			else
				nivel = nivel + ((perto[parte] and 1 or 0) - nivel) * passo
				if nivel < 0.01 and not perto[parte] then
					parte.LocalTransparencyModifier = 0
					afetadas[parte] = nil
				else
					afetadas[parte] = nivel
					parte.LocalTransparencyModifier = nivel * TRANSP_PAREDE
				end
			end
		end

		-- 4) Aura de poder acompanhando o personagem enquanto está dentro de parede
		local alvoAura = (ligado and aura:GetAttribute("tocando")) and 1 or 0
		nivelAura = nivelAura + (alvoAura - nivelAura) * (1 - math.exp(-dt * 8))
		if nivelAura > 0.01 and raiz then
			local pulsar = 1 + math.sin(agora * 7) * 0.06
			aura.Size = Vector3.new(5, 5, 5) * pulsar
			aura.CFrame = raiz.CFrame * CFrame.Angles(0, agora * 0.8, 0)
			aura.Transparency = 1 - 0.5 * nivelAura
		else
			aura.Transparency = 1
		end
	end)
end

------------------------------------------------------------
-- SPAWNS (salvar posições, renomear e teleportar)
------------------------------------------------------------
local iniciarDash -- definido mais abaixo (no bloco do TPTOOL); SPAWNS e TP usam
local DASH_VELOCIDADE_TP = 700 -- studs por segundo no teleporte do TP e dos SPAWNS (aumente para ir mais rápido)
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

local spawnsSalvos = {} -- [Frame da linha] = { nome = TextBox, cf = CFrame, dist = TextLabel, marca = Part }
local contadorSpawn = 0
local carregandoSpawns = true -- true enquanto lê o arquivo (não regrava no meio)

-- Salvamento em arquivo (só funciona se o seu executor tiver writefile/readfile; senão ignora)
local HttpService = game:GetService("HttpService")
local ARQUIVO_SPAWNS = "spawns_" .. tostring(game.PlaceId) .. ".json"
local function temArquivos()
	return typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
end

local function salvarSpawns()
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

local function criarLinhaSpawn(cframeSalvo, nomeSalvo)
	contadorSpawn += 1

	local linha = Instance.new("Frame")
	linha.Size = UDim2.new(1, -6, 0, 52)
	linha.BackgroundTransparency = 1
	linha.LayoutOrder = contadorSpawn
	linha.Parent = listaSpawn

	-- Nome editável (clique e digite)
	local nome = Instance.new("TextBox")
	nome.Size = UDim2.new(0.55, 0, 0, 34)
	nome.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
	nome.Text = nomeSalvo or ("Spawn " .. contadorSpawn)
	nome.PlaceholderText = "nome"
	nome.TextColor3 = Color3.new(1, 1, 1)
	nome.PlaceholderColor3 = Color3.fromRGB(140, 140, 140)
	nome.Font = Enum.Font.GothamBold
	nome.TextSize = 14
	nome.ClearTextOnFocus = false
	nome.TextTruncate = Enum.TextTruncate.AtEnd
	nome.Parent = linha
	Instance.new("UICorner", nome).CornerRadius = UDim.new(0, 8)

	-- Distância até o spawn (embaixo do nome)
	local dist = Instance.new("TextLabel")
	dist.Position = UDim2.new(0, 4, 0, 36)
	dist.Size = UDim2.new(0.55, -4, 0, 14)
	dist.BackgroundTransparency = 1
	dist.Text = "—"
	dist.TextColor3 = Color3.fromRGB(160, 160, 170)
	dist.Font = Enum.Font.Gotham
	dist.TextSize = 12
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
	ir.Position = UDim2.new(0.58, 0, 0, 0)
	ir.Size = UDim2.new(0.24, 0, 0, 34)
	ir.BackgroundColor3 = COR_ON
	ir.Text = "IR"
	ir.TextColor3 = Color3.new(1, 1, 1)
	ir.Font = Enum.Font.GothamBold
	ir.TextSize = 14
	ir.Parent = linha
	Instance.new("UICorner", ir).CornerRadius = UDim.new(0, 8)

	ir.MouseButton1Click:Connect(function()
		if pegarPersonagem() then
			iniciarDash(cframeSalvo.Position + Vector3.new(0, 3, 0), { velocidade = DASH_VELOCIDADE_TP, forte = true })
		end
	end)

	-- Apagar o spawn
	local apagar = Instance.new("TextButton")
	apagar.Position = UDim2.new(0.85, 0, 0, 0)
	apagar.Size = UDim2.new(0.15, 0, 0, 34)
	apagar.BackgroundColor3 = COR_OFF
	apagar.Text = "X"
	apagar.TextColor3 = Color3.new(1, 1, 1)
	apagar.Font = Enum.Font.GothamBold
	apagar.TextSize = 14
	apagar.Parent = linha
	Instance.new("UICorner", apagar).CornerRadius = UDim.new(0, 8)

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

local function escaparRich(t)
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
		iniciarDash(alvo.Position + Vector3.new(0, 3, 0), { velocidade = DASH_VELOCIDADE_TP, forte = true })
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
		botaoView.Text = "VIEW"
		VIDRO.aplicar(botaoView, false)
		pintarLista()
	end

	iniciarView = function(p)
		if not p or p == player or not p.Parent then return false end
		viewAlvo = p
		nomeView.Text = p.DisplayName
		barra.Visible = true
		painelView.Visible = false
		botaoView.Text = "VIEW: " .. p.DisplayName
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

do
	local RAIO_ONDA = 500        -- studs: até onde a onda de revelação vai
	local DURACAO_ONDA = 0.7     -- segundos que a onda leva para chegar lá (era 2.2)
	local SONAR_INTERVALO = 4    -- segundos entre um sonar e outro
	local SONAR_ALCANCE = 120    -- studs que cada sonar alcança
	local SONAR_DURACAO = 1.8    -- segundos que o sonar leva para chegar no alcance
	local COR_SONAR = Color3.fromRGB(90, 220, 255)
	local TAMANHO_BALDE = 10     -- studs por faixa de distância (organiza as partes pela onda)
	local RAIO_PERTO = 250       -- studs: o que está até aqui é pego primeiro, na hora
	local FADE_ENTRADA = 8       -- velocidade do fade de cada parte (maior = mais rápido; 8 = ~0.12s)
	local ORCAMENTO_FRAME = 0.008 -- segundos por frame gastos varrendo o mapa (maior = mais rápido, mais risco de engasgar)

	local partes = {}     -- [BasePart] = nível 0..1 (quanto já ficou transparente)
	local ativas = {}     -- [BasePart] = true enquanto faz o fade de entrada
	local baldes = {}     -- [faixa] = { partes esperando a onda chegar }
	local ecos = {}       -- [BasePart] = instante em que o sonar passou
	local aneis = {}      -- anéis/ondas visíveis no momento
	local conexao
	local versao = 0
	local fadeGlobal = 1  -- 1 = normal, cai a 0 ao desligar
	local saindo = false
	local ondaAtiva = false
	local raioOnda = 0
	local baldeAtual = 0
	local origemOnda = Vector3.zero
	local proximoSonar = 0
	local ultimoEco = 0
	local ultimo

	local ecoParams = OverlapParams.new()

	-- Anel de energia no chão + casca de campo de força (só visual, no seu cliente)
	local function criarAnel(origem, tipo, alcance)
		local pasta = workspace.CurrentCamera
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
		bloco.Parent = pasta

		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Top
		sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		sg.CanvasSize = Vector2.new(512, 512)
		sg.AlwaysOnTop = true
		sg.LightInfluence = 0
		sg.Adornee = bloco
		sg.Parent = bloco
		local quadro = Instance.new("Frame")
		quadro.Size = UDim2.fromScale(1, 1)
		quadro.BackgroundTransparency = 1
		quadro.Parent = sg
		Instance.new("UICorner", quadro).CornerRadius = UDim.new(0.5, 0)
		local contorno = Instance.new("UIStroke")
		contorno.Color = COR_SONAR
		contorno.Thickness = tipo == "onda" and 7 or 4
		contorno.Transparency = 1
		contorno.Parent = quadro

		local esfera = Instance.new("Part")
		esfera.Name = "XrayCasca"
		esfera.Shape = Enum.PartType.Ball
		esfera.Material = Enum.Material.ForceField
		esfera.Color = COR_SONAR
		esfera.Anchored = true
		esfera.CanCollide = false
		esfera.CanQuery = false
		esfera.CanTouch = false
		esfera.CastShadow = false
		esfera.Transparency = 1
		esfera.Size = Vector3.new(1, 1, 1)
		esfera.CFrame = CFrame.new(origem)
		esfera.Parent = pasta

		local anel = {
			tipo = tipo, bloco = bloco, esfera = esfera, contorno = contorno,
			origem = origem, raio = 0, alcance = alcance,
			vel = alcance / (tipo == "onda" and DURACAO_ONDA or SONAR_DURACAO),
		}
		aneis[#aneis + 1] = anel
		return anel
	end

	local function atualizarAnel(a)
		local prog = math.clamp(a.raio / a.alcance, 0, 1)
		local d = math.clamp(a.raio * 2, 1, 2000)
		a.bloco.Size = Vector3.new(d, 0.1, d)
		a.bloco.CFrame = CFrame.new(a.origem - Vector3.new(0, 2.6, 0))
		a.esfera.Size = Vector3.new(d, d, d)
		local forca = a.tipo == "onda" and 0.9 or 0.65
		a.contorno.Transparency = 1 - forca * (1 - prog ^ 1.6)
		a.esfera.Transparency = 1 - (a.tipo == "onda" and 0.12 or 0.07) * (1 - prog)
	end

	local function destruirAnel(a)
		a.bloco:Destroy()
		a.esfera:Destroy()
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
		parte.LocalTransparencyModifier = n * transparenciaXray * fadeGlobal * fator
	end

	local function ativar(parte)
		if partes[parte] ~= nil then ativas[parte] = true end
	end

	-- Registra uma parte do mapa e decide quando ela entra na onda
	local function registrar(obj)
		if not obj:IsA("BasePart") or obj:IsA("Terrain") or partes[obj] ~= nil then return end
		if obj.Transparency >= 1 or ehParteDePersonagem(obj) then return end
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

	local function finalizarSaida()
		for parte in pairs(partes) do
			if parte.Parent then parte.LocalTransparencyModifier = 0 end
		end
		partes, ativas, baldes, ecos = {}, {}, {}, {}
		limparAneis()
		saindo = false
		fadeGlobal = 1
	end

	local function ligar()
		if saindo then finalizarSaida() end
		versao += 1
		local minhaVersao = versao
		fadeGlobal = 1

		local raiz = pegarPersonagem()
		origemOnda = raiz and raiz.Position or workspace.CurrentCamera.CFrame.Position
		ondaAtiva = true
		raioOnda = 0
		baldeAtual = 0
		baldes = {}
		criarAnel(origemOnda, "onda", RAIO_ONDA)
		proximoSonar = os.clock() + DURACAO_ONDA + 1.2

		conexao = workspace.DescendantAdded:Connect(registrar)
		task.spawn(function()
			-- 1) o que está perto de você primeiro (uma busca só: aparece quase na hora)
			if raiz then
				for _, obj in ipairs(workspace:GetPartBoundsInRadius(origemOnda, RAIO_PERTO, OverlapParams.new())) do
					registrar(obj)
				end
			end
			-- 2) o resto do mapa, em fatias de tempo (antes: só 300 partes por frame, o que demorava em mapa grande)
			local t0 = os.clock()
			for _, obj in ipairs(workspace:GetDescendants()) do
				if minhaVersao ~= versao or not estado.xray then return end
				registrar(obj)
				if os.clock() - t0 > ORCAMENTO_FRAME then
					task.wait()
					t0 = os.clock()
				end
			end
		end)
	end

	local function desligar()
		versao += 1
		if conexao then
			conexao:Disconnect()
			conexao = nil
		end
		ondaAtiva = false
		baldes = {}
		for _, a in ipairs(aneis) do destruirAnel(a) end
		aneis = {}
		saindo = true -- o fade de saída roda no loop abaixo
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
		if estado.xray or saindo then
			local agora = os.clock()
			for parte in pairs(partes) do
				if parte.Parent then aplicarNivel(parte, agora) end
			end
		end
	end

	RunService.RenderStepped:Connect(function()
		local agora = os.clock()
		local dt = math.min(agora - (ultimo or agora), 0.1)
		ultimo = agora
		if not (estado.xray or saindo) then return end

		-- saída suave: o mapa volta ao normal em ~0.4s
		if saindo then
			fadeGlobal = fadeGlobal - dt * 2.5
			if fadeGlobal <= 0 then
				finalizarSaida()
			else
				for parte in pairs(partes) do
					if parte.Parent then aplicarNivel(parte, agora) end
				end
			end
			return
		end

		local raiz = pegarPersonagem()

		-- onda de revelação: libera as partes por faixa de distância
		if ondaAtiva then
			raioOnda = math.min(RAIO_ONDA, raioOnda + (RAIO_ONDA / DURACAO_ONDA) * dt)
			local limite = math.floor(raioOnda / TAMANHO_BALDE)
			for b = baldeAtual, limite do
				local lista = baldes[b]
				if lista then
					for _, parte in ipairs(lista) do ativar(parte) end
					baldes[b] = nil
				end
			end
			baldeAtual = limite + 1
			if raioOnda >= RAIO_ONDA then
				for _, lista in pairs(baldes) do -- o que sobrou (muito longe) entra junto no fim
					for _, parte in ipairs(lista) do ativar(parte) end
				end
				baldes = {}
				ondaAtiva = false
			end
		end

		-- partes entrando (fade de ~0.3s)
		for parte in pairs(ativas) do
			if not parte.Parent then
				ativas[parte] = nil
				partes[parte] = nil
			else
				local n = math.min(1, partes[parte] + dt * FADE_ENTRADA)
				partes[parte] = n
				if n >= 1 then ativas[parte] = nil end
				aplicarNivel(parte, agora)
			end
		end

		-- sonar periódico saindo de você
		if not ondaAtiva and raiz and agora >= proximoSonar then
			proximoSonar = agora + SONAR_INTERVALO
			criarAnel(raiz.Position, "sonar", SONAR_ALCANCE)
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
					if agora - ultimoEco > 0.05 then
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

		-- eco do sonar: a parte fica um pouco mais visível e volta suave
		for parte, t in pairs(ecos) do
			if not parte.Parent then
				ecos[parte] = nil
			else
				if agora - t >= 0.6 then ecos[parte] = nil end
				aplicarNivel(parte, agora)
			end
		end
	end)
end

botaoXray.MouseButton1Click:Connect(function() definirXray(not estado.xray) end)
caixaXray.FocusLost:Connect(aplicarCaixaXray)

------------------------------------------------------------
-- TPTOOL (item que leva você até onde você clicar, em um dash rápido)
------------------------------------------------------------
-- TELEPORTE SUAVE (dash): em vez de aparecer lá de uma vez, você voa rapidinho até o ponto
-- (acelera, passa direto por paredes e freia na chegada), com os riscos de vento e a tremida do fly
local DASH_VELOCIDADE = 220 -- studs por segundo (aumente para ir mais rápido)
-- TPTOOL (o item): false = voa até lá ultra rápido (uns 0.35s) com riscos de vento, tremida, FOV e estrondo na chegada
--                  true = teleporte instantâneo, sem animação nenhuma
local TPTOOL_INSTANTANEO = false
local TPTOOL_VELOCIDADE = 3000 -- studs/s (a duração mínima do voo forte é 0.35s)
do
	local conexao, terminarAtual

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

	local function anelEstrondo(atraso, espessura)
		task.delay(atraso, function()
			local tela = fxGui.AbsoluteSize
			if tela.X <= 0 then tela = workspace.CurrentCamera.ViewportSize end
			local anel = Instance.new("Frame")
			anel.AnchorPoint = Vector2.new(0.5, 0.5)
			anel.Position = UDim2.fromScale(0.5, 0.5)
			anel.Size = UDim2.fromOffset(40, 40)
			anel.BackgroundTransparency = 1
			anel.BorderSizePixel = 0
			anel.Active = false
			anel.Parent = fxGui
			Instance.new("UICorner", anel).CornerRadius = UDim.new(0.5, 0)
			local contorno = Instance.new("UIStroke")
			contorno.Color = Color3.fromRGB(235, 248, 255)
			contorno.Thickness = espessura
			contorno.Transparency = 0.1
			contorno.Parent = anel
			local info = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local d = tela.Magnitude * 1.1
			TweenService:Create(anel, info, { Size = UDim2.fromOffset(d, d) }):Play()
			TweenService:Create(contorno, info, { Transparency = 1, Thickness = 1 }):Play()
			task.delay(0.6, function() anel:Destroy() end)
		end)
	end

	local function estrondo()
		versaoFx += 1
		local minha = versaoFx
		-- clarão
		fxFlash.BackgroundTransparency = 0.2
		TweenService:Create(fxFlash, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
		-- ondas de choque saindo do centro da tela
		anelEstrondo(0, 8)
		anelEstrondo(0.09, 4)
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

	-- opcoes (opcional): { velocidade = studs/s, forte = true (efeito de velocidade do som + estrondo na chegada) }
	iniciarDash = function(destino, opcoes)
		opcoes = opcoes or {}
		local velocidade = opcoes.velocidade or DASH_VELOCIDADE
		local forte = opcoes.forte == true
		if terminarAtual then terminarAtual() end
		versaoFx += 1 -- cancela o tranco de câmera de um estrondo anterior
		local raiz, hum = pegarPersonagem()
		if not raiz then return end

		local char = raiz.Parent
		local origem = raiz.Position
		local dist = (destino - origem).Magnitude
		if dist < 1 then return end

		local dur = math.clamp(dist / velocidade, forte and 0.35 or 0.2, forte and 1.2 or 1.5)
		local inicio = os.clock()
		local plano = Vector3.new(destino.X - origem.X, 0, destino.Z - origem.Z)
		local rotacao = plano.Magnitude > 0.1 and CFrame.lookAt(Vector3.zero, plano.Unit) or raiz.CFrame.Rotation

		-- atravessa o que estiver no caminho; guarda a colisão para devolver no fim
		local colisoes = {}
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide then
				colisoes[d] = true
				d.CanCollide = false
			end
		end
		local plataformaAntes = hum.PlatformStand
		hum.PlatformStand = true

		local function terminar(chegou)
			if conexao then conexao:Disconnect() conexao = nil end
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
			for d in pairs(colisoes) do
				if d.Parent then d.CanCollide = true end
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
			if TPTOOL_INSTANTANEO then
				-- teleporte na hora, mantendo para onde o personagem estava virado
				raiz.CFrame = CFrame.new(destino) * raiz.CFrame.Rotation
				raiz.AssemblyLinearVelocity = Vector3.zero
			else
				iniciarDash(destino, { velocidade = TPTOOL_VELOCIDADE, forte = true })
			end
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
		botaoRejoin.Text = "REJOIN"
		reentrando = false
	end
	return okFila, motivo
end
botaoRejoin.MouseButton1Click:Connect(fazerRejoin)

-- Se o teleporte falhar depois de iniciado, libera o botão de novo
TeleportService.TeleportInitFailed:Connect(function()
	botaoRejoin.Text = "REJOIN"
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
	local botaoLock = Instance.new("TextButton")
	botaoLock.Name = "BotaoShiftLock"
	botaoLock.AnchorPoint = Vector2.new(0.5, 0.5)
	botaoLock.Position = UDim2.new(0.9, 0, 0.45, 0)
	botaoLock.Size = UDim2.fromOffset(52, 52)
	botaoLock.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	botaoLock.BackgroundTransparency = 0.35
	botaoLock.Text = ""
	botaoLock.AutoButtonColor = false
	botaoLock.Visible = false
	botaoLock.ZIndex = 9
	botaoLock.Parent = gui
	Instance.new("UICorner", botaoLock).CornerRadius = UDim.new(1, 0)

	local contorno = Instance.new("UIStroke")
	contorno.Thickness = 2
	contorno.Parent = botaoLock

	-- Desenho do cadeado: argola + corpo
	local argola = Instance.new("Frame")
	argola.AnchorPoint = Vector2.new(0.5, 0.5)
	argola.Position = UDim2.new(0.5, 0, 0.36, 0)
	argola.Size = UDim2.fromOffset(15, 17)
	argola.BackgroundTransparency = 1
	argola.ZIndex = 1
	argola.Parent = botaoLock
	Instance.new("UICorner", argola).CornerRadius = UDim.new(0.5, 0)
	local contornoArgola = Instance.new("UIStroke")
	contornoArgola.Thickness = 3
	contornoArgola.Parent = argola

	local corpo = Instance.new("Frame")
	corpo.AnchorPoint = Vector2.new(0.5, 0.5)
	corpo.Position = UDim2.new(0.5, 0, 0.6, 0)
	corpo.Size = UDim2.fromOffset(24, 18)
	corpo.BorderSizePixel = 0
	corpo.ZIndex = 2
	corpo.Parent = botaoLock
	Instance.new("UICorner", corpo).CornerRadius = UDim.new(0, 4)

	-- Onda de brilho que sai do cadeado quando trava
	local onda = Instance.new("Frame")
	onda.Name = "OndaLock"
	onda.AnchorPoint = Vector2.new(0.5, 0.5)
	onda.Position = UDim2.fromScale(0.5, 0.5)
	onda.Size = UDim2.fromScale(1, 1)
	onda.BackgroundTransparency = 1
	onda.BorderSizePixel = 0
	onda.Active = false
	onda.Visible = false
	onda.ZIndex = 8
	onda.Parent = botaoLock
	Instance.new("UICorner", onda).CornerRadius = UDim.new(1, 0)
	local contornoOnda = Instance.new("UIStroke")
	contornoOnda.Color = COR_AZUL
	contornoOnda.Thickness = 3
	contornoOnda.Parent = onda

	-- Botão pequeno embaixo do cadeado: troca o ombro da câmera (direita <-> esquerda)
	local botaoLado = Instance.new("TextButton")
	botaoLado.Name = "TrocarOmbro"
	botaoLado.AnchorPoint = Vector2.new(0.5, 0)
	botaoLado.Position = UDim2.new(0.5, 0, 1, 6)
	botaoLado.Size = UDim2.fromOffset(34, 22)
	botaoLado.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	botaoLado.BackgroundTransparency = 0.35
	botaoLado.Text = "⇄"
	botaoLado.TextColor3 = Color3.new(1, 1, 1)
	botaoLado.Font = Enum.Font.GothamBold
	botaoLado.TextSize = 15
	botaoLado.AutoButtonColor = true
	botaoLado.ZIndex = 9
	botaoLado.Parent = botaoLock
	Instance.new("UICorner", botaoLado).CornerRadius = UDim.new(0, 8)
	botaoLado.MouseButton1Click:Connect(function()
		lado = -lado -- a câmera desliza suave para o outro ombro (ver atualizarShiftLock)
	end)

	local pulsoContorno -- brilho que respira enquanto está travado
	local function pintar(animar)
		local cor = travado and COR_AZUL or COR_BRANCO
		local info = TweenInfo.new(animar and 0.25 or 0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(contorno, info, { Color = cor }):Play()
		TweenService:Create(contornoArgola, info, { Color = cor }):Play()
		TweenService:Create(corpo, info, { BackgroundColor3 = cor }):Play()
		-- argola: fechada (travado) ou levantada (solto)
		TweenService:Create(argola, TweenInfo.new(animar and 0.3 or 0, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0.36, travado and 0 or -6),
		}):Play()

		if pulsoContorno then pulsoContorno:Cancel() pulsoContorno = nil end
		contorno.Transparency = 0
		if travado then
			pulsoContorno = TweenService:Create(contorno,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 })
			pulsoContorno:Play()
		end

		if animar then
			-- "pop" do botão
			TweenService:Create(botaoLock, TweenInfo.new(0.1), { Size = UDim2.fromOffset(60, 60) }):Play()
			task.delay(0.1, function()
				TweenService:Create(botaoLock, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(52, 52) }):Play()
			end)
			-- onda de brilho ao travar
			if travado then
				onda.Size = UDim2.fromScale(1, 1)
				contornoOnda.Transparency = 0
				onda.Visible = true
				TweenService:Create(onda, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.fromScale(2, 2) }):Play()
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
-- TECLADO (barra de comandos digitados)
------------------------------------------------------------
do
	local toque = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local tecladoLigado = true -- a barra fica sempre no canto da tela
	local barraAberta = false
	local listaAjuda = {}
	local entradas = {} -- { nomes = {...}, desc = "..." } -> usado para filtrar/completar a lista
	local manterBarra = false -- true = o comando pediu para a barra continuar aberta (cmds)
	local comandos = {} -- [palavra] = function(args) -> sucesso, mensagem
	local LARGURA_ABERTA = 282
	local LARGURA_FECHADA, ALTURA_FECHADA = 96, 24 -- barrinha fina quando fechada
	local posSalva -- posição da barrinha antes de subir (celular)

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
		Position = toque and UDim2.new(1, -130, 1, -6) or UDim2.new(1, -16, 1, -16), -- no celular fica ao lado do botão de pulo
		Size = UDim2.fromOffset(LARGURA_FECHADA, ALTURA_FECHADA),
		BackgroundTransparency = 1,
		Visible = true,
		ZIndex = 10,
	}, gui)

	local icone = novo("TextButton", {
		Name = "Icone",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(LARGURA_FECHADA, ALTURA_FECHADA),
		BackgroundColor3 = Color3.fromRGB(25, 25, 30),
		BackgroundTransparency = 0.25,
		Text = "> comandos",
		TextColor3 = Color3.fromRGB(190, 190, 200),
		Font = Enum.Font.Gotham,
		TextSize = 12,
	}, cmdFrame)
	novo("UICorner", { CornerRadius = UDim.new(0, 6) }, icone)
	novo("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.7 }, icone)

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
		ShowNativeInput = false, -- no celular: digita direto na barra, sem a caixa branca com OK
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
		Text = "Comandos (use , para vários)",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
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
	novo("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, rolagem)

	-- Coloca avisos/lista em cima da barra (ou embaixo, se ela estiver no topo da tela)
	-- Topo da barra na tela, calculado pelas propriedades (AbsolutePosition demora um quadro para atualizar)
	local function topoDaBarra()
		local pos, tam, a = cmdFrame.Position, cmdFrame.Size, cmdFrame.AnchorPoint
		return pos.Y.Scale * tamanhoTela().Y + pos.Y.Offset - a.Y * tam.Y.Offset
	end

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
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Color3.fromRGB(45, 45, 52),
				BackgroundTransparency = 0.3,
				Text = a.e.desc,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(220, 220, 230),
				Font = Enum.Font.Gotham,
				TextSize = 12,
				AutoButtonColor = true,
			}, rolagem)
			novo("UICorner", { CornerRadius = UDim.new(0, 6) }, linha)
			novo("UIPadding", {
				PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
				PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
			}, linha)
			linha.Activated:Connect(function() completarComando(a.nome) end)
			linhasSugestao[#linhasSugestao + 1] = linha
		end

		if #achados == 0 then
			linhasSugestao[1] = novo("TextLabel", {
				Size = UDim2.new(1, -8, 0, 26),
				BackgroundTransparency = 1,
				Text = "Nenhum comando assim",
				TextColor3 = Color3.fromRGB(150, 150, 160),
				Font = Enum.Font.Gotham,
				TextSize = 12,
			}, rolagem)
		end
		rolagem.CanvasPosition = Vector2.new(0, 0)
	end

	-- Mostra a lista em cima da barra (ou embaixo, se a barra estiver no topo), do tamanho do espaço livre
	local function mostrarLista()
		local y = topoDaBarra()
		local livre = (y < 90) and (tamanhoTela().Y - y - 56) or (y - 12)
		ajuda.Size = UDim2.fromOffset(LARGURA_ABERTA, math.clamp(livre, 90, 230))
		posicionarAcima(ajuda)
		toast.Visible = false
		ajuda.Visible = true
	end

	local function abrirAjuda() -- lista completa (comando cmds)
		atualizarSugestoes("")
		mostrarLista()
	end
	fecharAjuda.Activated:Connect(function() ajuda.Visible = false end)

	local function fecharBarra()
		barraAberta = false
		caixaCmd:ReleaseFocus()
		caixaCmd.Visible = false
		botaoEnviar.Visible = false
		ajuda.Visible = false
		icone.Text = "> comandos"
		icone.TextSize = 12
		icone.Size = UDim2.fromOffset(LARGURA_FECHADA, ALTURA_FECHADA)
		cmdFrame.Size = UDim2.fromOffset(LARGURA_FECHADA, ALTURA_FECHADA)
		if posSalva then -- celular: volta para o canto de baixo
			cmdFrame.Position = posSalva
			posSalva = nil
		end
	end

	local function abrirBarra()
		barraAberta = true
		-- se o ícone estiver perto da borda esquerda, empurra a barra para dentro da tela
		if toque then
			-- celular: sobe a barra para ficar acima do teclado da tela
			posSalva = cmdFrame.Position
			cmdFrame.Position = UDim2.new(1, -16, 1, -190)
		else
			local direita = cmdFrame.AbsolutePosition.X + cmdFrame.AbsoluteSize.X
			local falta = LARGURA_ABERTA - direita
			if falta > 0 then
				local p = cmdFrame.Position
				cmdFrame.Position = UDim2.new(p.X.Scale, p.X.Offset + falta, p.Y.Scale, p.Y.Offset)
			end
		end
		icone.Text = "X"
		icone.TextSize = 14
		icone.Size = UDim2.fromOffset(40, 40)
		cmdFrame.Size = UDim2.fromOffset(LARGURA_ABERTA, 40)
		caixaCmd.Visible = true
		botaoEnviar.Visible = true
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

	-- Toque rápido no ícone abre/fecha a barra; arrastar move o ícone
	tornarMovel(icone, cmdFrame, function()
		if barraAberta then fecharBarra() else abrirBarra() end
	end)

	-- A lista filtra enquanto você digita
	caixaCmd:GetPropertyChangedSignal("Text"):Connect(function()
		if barraAberta then
			atualizarSugestoes(caixaCmd.Text)
			mostrarLista()
		end
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
		minha.AssemblyLinearVelocity = Vector3.zero
		minha.CFrame = alvo.CFrame + Vector3.new(0, 3, 0)
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
		iniciarDash(achado.cf.Position + Vector3.new(0, 3, 0), { velocidade = DASH_VELOCIDADE_TP, forte = true })
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

	comando({ "menu" }, "menu - abrir/fechar o menu", function()
		alternarPainel()
		return true, aberto and "Menu aberto" or "Menu fechado"
	end)

	comando({ "cmds", "help", "?" }, "cmds - mostrar a lista completa", function()
		manterBarra = true
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
		for trecho in texto:gmatch("[^,]+") do
			local ok, msg = executarComando(trecho)
			if msg then mensagens[#mensagens + 1] = msg end
			tudoCerto = tudoCerto and ok
		end

		if #mensagens > 0 then
			ajuda.Visible = false
			mostrarToast(table.concat(mensagens, "\n"), tudoCerto)
		end
		if tudoCerto then
			if manterBarra then
				manterBarra = false
				caixaCmd.Text = ""
				abrirAjuda()
				task.defer(function() caixaCmd:CaptureFocus() end)
			else
				fecharBarra() -- fecha antes de limpar o texto, para a lista não cobrir o aviso
				caixaCmd.Text = ""
			end
		end
	end

	caixaCmd.FocusLost:Connect(function(enter)
		if enter then executarLinha(caixaCmd.Text) end
	end)
	botaoEnviar.Activated:Connect(function()
		executarLinha(caixaCmd.Text)
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
