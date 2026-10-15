local Shops = {}
local SpawnedPeds = {}
local SpawnedSigns = {}
local SpawnedBlips = {}
local ActiveZones = {}
local CarriedBoxProps = {}
local CurrentComputerShop = nil
local FleetVehicleEntity = nil
local SignPoints = {}
local FleetVehicleId,FleetShopId=nil,nil
local MissionPed,MissionZone=nil,nil
local WorldSyncRunning,PendingWorldSync=false,nil

local function addInteractionZone(coords, radius, options)
    for _, option in ipairs(options) do option.distance = math.max(1.5, math.min(4.0, radius or 2.0)) end
    local id = exports.mri_Qinteract:addCoords(coords, options)
    return { remove = function() exports.mri_Qinteract:removeCoords(id) end }
end

local function notify(msg, kind)
    lib.notify({ description = msg, type = kind or 'inform' })
end

-- Ferramenta Visual 3D de Posicionamento de Zonas
local function runVisualZonePlacement(labelTitle)
    local ped = cache.ped
    local offset = GetEntityCoords(ped) + GetEntityForwardVector(ped) * 2.0
    local radius = 1.35
    local confirmed = false

    lib.showTextUI(('[%s]\nSetas: Mover | Scroll: Raio | [ENTER/E] Salvar Zona | [BACKSPACE] Cancelar'):format(labelTitle))

    while not confirmed do
        Wait(0)
        DrawMarker(28, offset.x, offset.y, offset.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            radius, radius, radius, 239, 68, 68, 110, false, false, 2, false, nil, nil, false)

        if IsControlPressed(0, 172) then offset = offset + vec3(0.0, 0.03, 0.0) end
        if IsControlPressed(0, 173) then offset = offset - vec3(0.0, 0.03, 0.0) end
        if IsControlPressed(0, 174) then offset = offset - vec3(0.03, 0.0, 0.0) end
        if IsControlPressed(0, 175) then offset = offset + vec3(0.03, 0.0, 0.0) end
        if IsControlPressed(0, 10)  then offset = offset + vec3(0.0, 0.0, 0.03) end
        if IsControlPressed(0, 11)  then offset = offset - vec3(0.0, 0.0, 0.03) end
        if IsControlJustPressed(0, 241) then radius = math.min(4.0, radius + 0.15) end
        if IsControlJustPressed(0, 242) then radius = math.max(0.6, radius - 0.15) end

        if IsControlJustPressed(0, 191) or IsControlJustPressed(0, 38) then
            confirmed = true
        elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 73) then
            lib.hideTextUI()
            return nil
        end
    end

    lib.hideTextUI()
    Wait(250)
    return {
        x = tonumber(string.format('%.2f', offset.x)),
        y = tonumber(string.format('%.2f', offset.y)),
        z = tonumber(string.format('%.2f', offset.z)),
        radius = tonumber(string.format('%.2f', radius))
    }
end

local function capturePlayerStandingPose(stepTitle)
    lib.showTextUI(('[%s]\nPosicione-se no local desejado: [E] Confirmar | [BACKSPACE] Cancelar'):format(stepTitle))
    while true do
        Wait(0)
        if IsControlJustPressed(0, 38) then
            local c = GetEntityCoords(cache.ped)
            local h = GetEntityHeading(cache.ped)
            lib.hideTextUI()
            Wait(250)
            return {
                x = tonumber(string.format('%.2f', c.x)),
                y = tonumber(string.format('%.2f', c.y)),
                z = tonumber(string.format('%.2f', c.z)),
                w = tonumber(string.format('%.2f', h))
            }
        elseif IsControlJustPressed(0, 177) or IsControlJustPressed(0, 73) then
            lib.hideTextUI()
            return nil
        end
    end
end

-- Assistente de Criação In-Game (/createpawnshop)
RegisterNetEvent('mri_Qpawnshop:client:openCreatorWizard', function()
    local input = lib.inputDialog('Criar Nova Loja de Penhor', {
        { type = 'input',    label = 'Nome da Loja',                          default = 'Penhor Mirror Park', required = true },
        { type = 'input',    label = 'Modelo do NPC Balconista',              default = 's_m_y_barman_01',    required = true },
        { type = 'select',   label = 'Animação do NPC',                       options = Config.PedScenarios,  default = 'WORLD_HUMAN_STAND_IMPATIENT' },
        { type = 'checkbox', label = 'Permitir Compra por Jogadores?',        checked = true },
        { type = 'number',   label = 'Preço de Compra da Loja ($)',           default = 75000 },
        { type = 'number',   label = 'Capital de Giro Inicial no Caixa ($)',  default = 25000 }
    })
    if not input then return end

    notify('Passo 1/5: Posicione o NPC balconista e pressione [E].', 'inform')
    local pedCoords = capturePlayerStandingPose('1. POSIÇÃO DO NPC BALCONISTA')
    if not pedCoords then notify('Criação cancelada.', 'error'); return end

    notify('Passo 2/5: Posicione a zona do Computador de Gestão.', 'inform')
    local computerCoords = runVisualZonePlacement('2. ZONA DO COMPUTADOR DE GESTÃO')
    if not computerCoords then notify('Criação cancelada.', 'error'); return end

    notify('Passo 3/5: Posicione a Estação de Embalagem.', 'inform')
    local packagingCoords = runVisualZonePlacement('3. ÁREA DE EMBALAGEM')
    if not packagingCoords then notify('Criação cancelada.', 'error'); return end

    notify('Passo 4/5: Posicione o ponto de Spawn e Garagem da Frota.', 'inform')
    local garageCoords = capturePlayerStandingPose('4. GARAGEM E SPAWN DE VEÍCULOS')
    if not garageCoords then notify('Criação cancelada.', 'error'); return end

    notify('Passo 5/5: Posicione a placa "À Venda" na entrada.', 'inform')
    local signCoords = capturePlayerStandingPose('5. PLACA DE VENDA DO IMÓVEL')
    if not signCoords then notify('Criação cancelada.', 'error'); return end

    local catInputs, catKeys = {}, {}
    for k, v in pairs(Config.Categories) do
        catKeys[#catKeys + 1] = k
        catInputs[#catInputs + 1] = { type = 'checkbox', label = v.label, checked = true }
    end
    local selectedCats = lib.inputDialog('Categorias Aceitas pela Loja', catInputs)
    local categoriesMap = {}
    for idx, k in ipairs(catKeys) do
        categoriesMap[k] = (not selectedCats) or (selectedCats[idx] == true)
    end

    local blipDialog = lib.inputDialog('Configuração do Blip no Mapa', {
        { type = 'input',  label = 'Nome no Mapa',        default = input[1] },
        { type = 'number', label = 'ID do Ícone (Sprite)',default = 431 },
        { type = 'number', label = 'ID da Cor',           default = 5 },
        { type = 'number', label = 'Escala',              default = 0.8 }
    })

    TriggerServerEvent('mri_Qpawnshop:server:createShop', {
        name = input[1],
        pedModel = input[2],
        pedScenario = input[3],
        ownable = input[4] == true,
        purchasePrice = tonumber(input[5]) or 75000,
        startingEquity = tonumber(input[6]) or 25000,
        coords = {
            ped = pedCoords,
            computer = computerCoords,
            packaging = packagingCoords,
            garage = garageCoords,
            forSaleSign = signCoords
        },
        categories = categoriesMap,
        blip = {
            label = (blipDialog and blipDialog[1]) or input[1],
            sprite = (blipDialog and tonumber(blipDialog[2])) or 431,
            color = (blipDialog and tonumber(blipDialog[3])) or 5,
            scale = (blipDialog and tonumber(blipDialog[4])) or 0.8
        }
    })
end)

RegisterNetEvent('mri_Qpawnshop:client:openStash', function(stashId)
    exports.ox_inventory:openInventory('stash', stashId)
end)

-- Contrato Imobiliário de Compra da Loja
local function openPurchaseAgreement(shop)
    local totalDue = (shop.purchase_price or 75000) + (shop.starting_equity or 25000)
    local content = ([[
### 🏢 Detalhes do Estabelecimento
- **Nome da Empresa:** %s
- **Ramo de Atividade:** Loja de Penhores & Antiguidades
- **Limite de Funcionários:** 10

---
### 💰 Condições Financeiras
- **Valor do Imóvel:** $%s
- **Capital de Giro Inicial:** $%s
- **Total a Pagar:** **$%s**

---
### 📋 Termos e Garantias
- ✔ Transferência imediata de propriedade após o pagamento
- ✔ Capital inicial depositado diretamente no caixa da loja
- ✔ Contratação de até 10 funcionários com permissões customizáveis
- ✔ Acesso a pedidos de exportação, frota de veículos e fornecedores
]]):format(shop.name, shop.purchase_price, shop.starting_equity, totalDue)

    local decision = lib.alertDialog({
        header = '📜 CONTRATO DE COMPRA DE EMPRESA',
        content = content,
        centered = true,
        cancel = true,
        labels = { cancel = 'RECUSAR', confirm = ('ASSINAR E COMPRAR ($%s)'):format(totalDue) }
    })

    if decision == 'confirm' then
        TriggerServerEvent('mri_Qpawnshop:server:buyShop', shop.id)
    end
end

-- Menu de Atendimento do Cliente no Balcão
local function openCustomerCounterMenu(shop)
    if not shop.is_open then
        notify('Esta loja encontra-se fechada no momento.', 'error')
        return
    end

    lib.registerContext({
        id = 'pawnshop_customer_main',
        title = shop.name,
        options = {
            {
                title = '⭐ Ofertas Especiais',
                description = 'Confira os itens raros e promoções em destaque no balcão',
                onSelect = function()
                    local items = lib.callback.await('mri_Qpawnshop:server:getShelfItems', false, shop.id, 'special_offers') or {}
                    local opts = {}
                    for _, it in ipairs(items) do
                        opts[#opts + 1] = {
                            title = it.label or it.item_name:upper(),
                            description = ('Preço: $%s • %s em estoque'):format(it.price, it.qty),
                            disabled = it.qty <= 0,
                            onSelect = function()
                                TriggerServerEvent('mri_Qpawnshop:server:buyFromShelf', shop.id, it.id)
                            end
                        }
                    end
                    if #opts == 0 then opts[#opts + 1] = { title = 'Nenhuma oferta especial disponível no momento', disabled = true } end
                    lib.registerContext({ id = 'pawnshop_special_offers', title = shop.name .. ' - Ofertas Especiais', menu = 'pawnshop_customer_main', options = opts })
                    lib.showContext('pawnshop_special_offers')
                end
            },
            {
                title = '🏷️ Tabela de Compras da Loja',
                description = 'Veja quais categorias de itens nós compramos e os valores base',
                onSelect = function()
                    local catOpts = {}
                    for catKey, enabled in pairs(shop.categories or {}) do
                        if enabled and Config.Categories[catKey] and catKey ~= 'special_offers' then
                            local cat = Config.Categories[catKey]
                            catOpts[#catOpts + 1] = {
                                title = cat.label,
                                icon = cat.icon,
                                onSelect = function()
                                    local itemOpts = {}
                                    for _, info in pairs(cat.items) do
                                        itemOpts[#itemOpts + 1] = {
                                            title = info.label,
                                            description = ('Valor Base de Mercado: $%s'):format(info.baseValue)
                                        }
                                    end
                                    lib.registerContext({ id = 'pawnshop_what_buy_' .. catKey, title = cat.label, menu = 'pawnshop_what_buy', options = itemOpts })
                                    lib.showContext('pawnshop_what_buy_' .. catKey)
                                end
                            }
                        end
                    end
                    lib.registerContext({ id = 'pawnshop_what_buy', title = 'O Que Compramos', menu = 'pawnshop_customer_main', options = catOpts })
                    lib.showContext('pawnshop_what_buy')
                end
            },
            {
                title = '📦 Colocar Itens na Bancada',
                description = 'Deposite os itens que deseja vender ou penhorar para avaliação',
                onSelect = function()
                    TriggerServerEvent('mri_Qpawnshop:server:openOfferStash', shop.id)
                end
            },
            {
                title = '💲 Avaliar Itens / Fechar Negócio',
                description = 'Receba a proposta de Venda Imediata à vista ou Penhor (72h)',
                onSelect = function()
                    local eval = lib.callback.await('mri_Qpawnshop:server:evaluateOfferedItems', false, shop.id)
                    if not eval or eval.empty then
                        notify('Use "Colocar Itens na Bancada" primeiro para depositar os produtos.', 'error')
                        return
                    end

                    local listText = ''
                    for _, line in ipairs(eval.items) do
                        listText = listText .. ('- **%sx %s** — $%s\n'):format(line.count, line.label, line.lineValue)
                    end

                    local valModal = lib.alertDialog({
                        header = '📋 Laudo de Avaliação de Mercadorias',
                        content = ('%s\n**Total de Itens:** %s\n**Valor Estimado de Mercado:** $%s\n**Melhor Oferta à Vista:** $%s\n\nDeseja visualizar as propostas de pagamento?'):format(
                            listText, eval.totalItems, eval.marketValue, eval.sellOffer
                        ),
                        centered = true,
                        cancel = true,
                        labels = { cancel = 'AGORA NÃO', confirm = 'VER PROPOSTAS' }
                    })

                    if valModal == 'confirm' then
                        lib.registerContext({
                            id = 'pawnshop_offer_choices',
                            title = 'Propostas da Loja',
                            options = {
                                {
                                    title = ('💰 Opção 1: Vender à Vista (Receber $%s)'):format(eval.sellOffer),
                                    description = ('Taxa de %s%% • Pagamento imediato em mãos • Venda definitiva'):format(eval.sellPercent),
                                    onSelect = function()
                                        TriggerServerEvent('mri_Qpawnshop:server:finalizeCustomerOffer', shop.id, 'sell')
                                    end
                                },
                                {
                                    title = ('🏷️ Opção 2: Penhorar Itens (Receber $%s Agora)'):format(eval.pawnOffer),
                                    description = ('Empréstimo de %s%% • Valor de Resgate: $%s • Prazo: %s horas'):format(eval.pawnPercent, eval.buybackPrice, eval.durationHours),
                                    onSelect = function()
                                        TriggerServerEvent('mri_Qpawnshop:server:finalizeCustomerOffer', shop.id, 'pawn')
                                    end
                                }
                            }
                        })
                        lib.showContext('pawnshop_offer_choices')
                    end
                end
            },
            {
                title = '🕒 Meus Itens Penhorados',
                description = 'Pague o valor de recompra para resgatar seus itens antes que expirem',
                onSelect = function()
                    local pawns = lib.callback.await('mri_Qpawnshop:server:getMyPawnedItems', false, shop.id) or {}
                    local opts = {}
                    for _, p in ipairs(pawns) do
                        opts[#opts + 1] = {
                            title = ('%sx %s'):format(p.qty, p.item_label),
                            description = ('Valor de Resgate: $%s | Tempo Restante: %sh %sm'):format(p.buyback_price, p.hoursLeft, p.minsLeft),
                            onSelect = function()
                                local confirm = lib.alertDialog({
                                    header = 'Resgatar Item Penhorado',
                                    content = ('Item: **%sx %s**\nValor de Resgate: **$%s**\n\nDeseja quitar o penhor e recuperar seu item agora?'):format(p.qty, p.item_label, p.buyback_price),
                                    centered = true,
                                    cancel = true,
                                    labels = { cancel = 'CANCELAR', confirm = 'PAGAR E RESGATAR' }
                                })
                                if confirm == 'confirm' then
                                    TriggerServerEvent('mri_Qpawnshop:server:buybackPawnedItem', shop.id, p.id)
                                end
                            end
                        }
                    end
                    if #opts == 0 then opts[#opts + 1] = { title = 'Você não possui itens penhorados ativos nesta loja.', disabled = true } end
                    lib.registerContext({ id = 'pawnshop_my_pawns', title = 'Meus Itens Penhorados', menu = 'pawnshop_customer_main', options = opts })
                    lib.showContext('pawnshop_my_pawns')
                end
            },
            {
                title = '💳 Programa de Fidelidade',
                description = 'Assine um plano para ganhar bônus nas vendas e melhores taxas de penhor',
                onSelect = function()
                    lib.registerContext({
                        id = 'pawnshop_loyalty_menu',
                        title = 'Planos de Fidelidade',
                        menu = 'pawnshop_customer_main',
                        options = {
                            {
                                title = '🥉 Plano Básico (GRÁTIS)',
                                description = '+2% de Bônus na Venda • Acumule pontos a cada negócio',
                                onSelect = function() TriggerServerEvent('mri_Qpawnshop:server:joinLoyalty', shop.id, 'Basico') end
                            },
                            {
                                title = '🥈 Plano Premium ($500/semana)',
                                description = '+5% de Bônus na Venda • +5% no Penhor • Atendimento Prioritário',
                                onSelect = function() TriggerServerEvent('mri_Qpawnshop:server:joinLoyalty', shop.id, 'Premium') end
                            },
                            {
                                title = '🥇 Plano VIP ($2000/semana)',
                                description = '+15% de Bônus na Venda • +10% no Penhor • Ofertas Exclusivas',
                                onSelect = function() TriggerServerEvent('mri_Qpawnshop:server:joinLoyalty', shop.id, 'VIP') end
                            }
                        }
                    })
                    lib.showContext('pawnshop_loyalty_menu')
                end
            }
        }
    })

    lib.showContext('pawnshop_customer_main')
end

local function openManagementComputer(shopId)
    local data = lib.callback.await('mri_Qpawnshop:server:getComputerData', false, shopId)
    if not data or data.denied then
        notify('Acesso negado: Você não faz parte do quadro de funcionários desta loja.', 'error')
        return
    end
    CurrentComputerShop = shopId
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openComputer',
        data = data
    })
end

RegisterNetEvent('mri_Qpawnshop:client:refreshComputer', function(data)
    if not CurrentComputerShop or not data then return end
    if data.denied then CurrentComputerShop=nil;SetNuiFocus(false,false);SendNUIMessage({action='closeComputerUI'});return end
    if not data.shop or data.shop.id~=CurrentComputerShop then return end
    SendNUIMessage({
        action = 'refreshComputer',
        data = data
    })
end)

local function clearWorldEntities()
    for _, point in ipairs(SignPoints) do point:remove() end
    SignPoints = {}
    for _, entity in pairs(SpawnedSigns) do
        if DoesEntityExist(entity) then exports.mri_Qinteract:removeLocalEntity(entity) end
    end
    for _, entity in pairs(SpawnedPeds) do
        if DoesEntityExist(entity) then exports.mri_Qinteract:removeLocalEntity(entity) end
    end
    for _, ped in pairs(SpawnedPeds) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    for _, obj in pairs(SpawnedSigns) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
    for _, blip in pairs(SpawnedBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    for _, zone in ipairs(ActiveZones) do zone:remove() end
    SpawnedPeds, SpawnedSigns, SpawnedBlips, ActiveZones = {}, {}, {}, {}
end

local function rebuildWorld(serverShops)
    Shops = serverShops or {}
    clearWorldEntities()

    for shopId, shop in pairs(Shops) do
        local c = shop.coords or {}

        if c.ped and shop.blip and shop.blip.sprite then
            local blip = AddBlipForCoord(c.ped.x + 0.0, c.ped.y + 0.0, c.ped.z + 0.0)
            SetBlipSprite(blip, shop.blip.sprite or 431)
            SetBlipColour(blip, shop.blip.color or 5)
            SetBlipScale(blip, (shop.blip.scale or 0.8) + 0.0)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(shop.blip.label or shop.name)
            EndTextCommandSetBlipName(blip)
            SpawnedBlips[shopId] = blip
        end

        if c.ped then
            local model = joaat(shop.ped_model or 's_m_y_barman_01')
            if pcall(lib.requestModel, model, 5000) then
                local ped = CreatePed(4, model, c.ped.x + 0.0, c.ped.y + 0.0, c.ped.z - 1.0, (c.ped.w or 0.0) + 0.0, false, true)
                SetEntityInvincible(ped, true)
                FreezeEntityPosition(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                if shop.ped_scenario then
                    TaskStartScenarioInPlace(ped, shop.ped_scenario, 0, true)
                end
                exports.mri_Qinteract:addLocalEntity(ped, {
                    {
                        label = 'Balcão de Atendimento - ' .. shop.name,
                        icon = 'fa-solid fa-scale-balanced',
                        onSelect = function() openCustomerCounterMenu(shop) end
                    },
                    {
                        label = 'Computador de Gestão',
                        icon = 'fa-solid fa-desktop',
                        onSelect = function() openManagementComputer(shopId) end
                    }
                })
                SpawnedPeds[shopId] = ped
            end
        end

        local available = (shop.ownable == true or tonumber(shop.ownable) == 1) and (not shop.owner_cid or shop.owner_cid == '')
        if available and c.forSaleSign then
            local position = c.forSaleSign
            SignPoints[#SignPoints + 1] = lib.points.new({
                coords = vec3(position.x, position.y, position.z), distance = 100.0,
                onEnter = function()
                    if SpawnedSigns[shopId] and DoesEntityExist(SpawnedSigns[shopId]) then return end
                    local signModel = joaat(Config.ForSaleSignModel or 'prop_forsale_lrg_01')
                    if not IsModelInCdimage(signModel) or not IsModelValid(signModel) or not pcall(lib.requestModel, signModel, 5000) then
                        print(('[mri_Qpawnshop] Não foi possível carregar a placa da loja %s.'):format(shopId))
                        return
                    end
                    RequestCollisionAtCoord(position.x, position.y, position.z)
                    local found, ground = GetGroundZFor_3dCoord(position.x, position.y, position.z + 2.0, false)
                    local minimum = GetModelDimensions(signModel)
                    local base = found and math.abs(ground - position.z) < 4.0 and ground or position.z - 1.0
                    local entity = CreateObjectNoOffset(signModel, position.x, position.y, base - minimum.z, false, false, false)
                    SetModelAsNoLongerNeeded(signModel)
                    if entity == 0 then print(('[mri_Qpawnshop] Falha ao criar a placa da loja %s.'):format(shopId)); return end
                    SetEntityAsMissionEntity(entity, true, true)
                    SetEntityHeading(entity, tonumber(position.w) or 0.0)
                    SetEntityCollision(entity, true, true)
                    FreezeEntityPosition(entity, true)
                    SpawnedSigns[shopId] = entity
                    exports.mri_Qinteract:addLocalEntity(entity, {{
                        name = 'pawnshop_buy_' .. shopId, distance = 2.5,
                        label = 'Comprar loja - ' .. shop.name, icon = 'fa-solid fa-file-signature',
                        onSelect = function() openPurchaseAgreement(shop) end
                    }})
                end,
                onExit = function()
                    local entity = SpawnedSigns[shopId]
                    if entity and DoesEntityExist(entity) then exports.mri_Qinteract:removeLocalEntity(entity); DeleteEntity(entity) end
                    SpawnedSigns[shopId] = nil
                end
            })

        end

        if c.computer then
            ActiveZones[#ActiveZones + 1] = addInteractionZone(vec3(c.computer.x + 0.0, c.computer.y + 0.0, c.computer.z + 0.0), (c.computer.radius or 1.5) + 0.0, {
{label = "Computador de Gestão", icon = 'fa-solid fa-desktop', canInteract = function() return not CurrentComputerShop and not lib.getOpenContextMenu() end, onSelect = function()

                            openManagementComputer(shopId)
end}
})
        end

        if c.packaging then
            ActiveZones[#ActiveZones + 1] = addInteractionZone(vec3(c.packaging.x + 0.0, c.packaging.y + 0.0, c.packaging.z + 0.0), (c.packaging.radius or 1.5) + 0.0, {
{label = "Estação de Embalagem", icon = 'fa-solid fa-box', canInteract = function() return not CurrentComputerShop and not lib.getOpenContextMenu() end, onSelect = function()
lib.registerContext({
                            id = 'pawnshop_packaging_' .. shopId,
                            title = 'Estação de Embalagem',
                            options = {
                                {
                                    title = '📦 Abrir Container de Embalagem',
                                    description = 'Coloque os itens que deseja encaixotar para exportação',
                                    onSelect = function()
                                        exports.ox_inventory:openInventory('stash', ('pawnshop_%s_packaging'):format(shopId))
                                    end
                                },
                                {
                                    title = '🛠️ Embalar Mercadorias',
                                    description = 'Lacrar as caixas para transporte seguro',
                                    onSelect = function()
                                        if lib.progressBar({
                                            duration = 4000,
                                            label = 'Embalando mercadorias...',
                                            canCancel = true,
                                            disable = { move = true, car = true, combat = true },
                                            anim = { dict = 'mini@repair', clip = 'fixing_a_ped' }
                                        }) then
                                            TriggerServerEvent('mri_Qpawnshop:server:processPackaging', shopId)
                                        end
                                    end
                                }
                            }
                        })
                        lib.showContext('pawnshop_packaging_' .. shopId)
end}
})
        end

        for idx, shelf in ipairs(shop.shelves or {}) do
            local catInfo = Config.Categories[shelf.category]
            local catLabel = catInfo and catInfo.label or shelf.category
            ActiveZones[#ActiveZones + 1] = addInteractionZone(vec3(shelf.x + 0.0, shelf.y + 0.0, shelf.z + 0.0), (shelf.radius or 1.4) + 0.0, {
{label = 'Ver Prateleira: ' .. catLabel, icon = 'fa-solid fa-boxes-stacked', canInteract = function() return not CurrentComputerShop and not lib.getOpenContextMenu() end, onSelect = function()
local items = lib.callback.await('mri_Qpawnshop:server:getShelfItems', false, shopId, shelf.category) or {}
                        local opts = {}
                        for _, it in ipairs(items) do
                            opts[#opts + 1] = {
                                title = it.label or it.item_name:upper(),
                                description = ('Preço: $%s • %s disponível(is)'):format(it.price, it.qty),
                                disabled = it.qty <= 0,
                                onSelect = function()
                                    TriggerServerEvent('mri_Qpawnshop:server:buyFromShelf', shopId, it.id)
                                end
                            }
                        end
                        if #opts == 0 then opts[#opts + 1] = { title = 'Prateleira vazia', disabled = true } end
                        lib.registerContext({ id = ('shelf_%s_%s'):format(shopId, idx), title = catLabel .. ' - Vitrine', options = opts })
                        lib.showContext(('shelf_%s_%s'):format(shopId, idx))
end}
})
        end

        if c.garage then
            ActiveZones[#ActiveZones + 1] = addInteractionZone(vec3(c.garage.x + 0.0, c.garage.y + 0.0, c.garage.z + 0.0), 2.2, {
{label = "Garagem da Frota", icon = 'fa-solid fa-van-shuttle', canInteract = function() return not CurrentComputerShop and not lib.getOpenContextMenu() end, onSelect = function()
local fleet=lib.callback.await('mri_Qpawnshop:server:getFleet',false,shopId) or {}
                        if #fleet==0 then notify('Apenas funcionários podem retirar veículos da frota.', 'error'); return end
                        local vOpts = {}
                        for _, v in ipairs(fleet) do
                            local statusLabel = v.status == 'available' and 'Disponível' or 'Indisponível'
                            vOpts[#vOpts + 1] = {
                                title = v.label,
                                description = ('Placa: %s | Combustível: %s%% | Status: %s'):format(v.plate, v.fuel, statusLabel),
                                disabled = v.status ~= 'available',
                                onSelect = function()
                                    TriggerServerEvent('mri_Qpawnshop:server:spawnFleet',shopId,v.id)
                                end
                            }
                        end
                        lib.registerContext({ id = 'pawnshop_garage_' .. shopId, title = '🚐 Frota da Loja', options = vOpts })
                        lib.showContext('pawnshop_garage_' .. shopId)
end},
{label = "Guardar veículo da frota", icon = 'fa-solid fa-van-shuttle', canInteract = function() return not CurrentComputerShop and not lib.getOpenContextMenu() and FleetVehicleEntity ~= nil and DoesEntityExist(FleetVehicleEntity) end, onSelect = function()
TriggerServerEvent('mri_Qpawnshop:server:returnFleet',FleetShopId,FleetVehicleId,{
                            fuel=GetVehicleFuelLevel(FleetVehicleEntity),body=GetVehicleBodyHealth(FleetVehicleEntity)/10,engine=GetVehicleEngineHealth(FleetVehicleEntity)/10
                        })
end}
})
        end
    end
end
RegisterNetEvent('mri_Qpawnshop:client:syncShops',function(serverShops)
    PendingWorldSync=serverShops
    if WorldSyncRunning then return end
    WorldSyncRunning=true
    CreateThread(function()
        while PendingWorldSync do
            local current=PendingWorldSync
            PendingWorldSync=nil
            local ok,err=xpcall(function() rebuildWorld(current) end,debug.traceback)
            if not ok then print('[mri_Qpawnshop] Falha ao atualizar lojas: '..tostring(err)) end
        end
        WorldSyncRunning=false
    end)
end)

CreateThread(function()
    while true do
        Wait(1000)
        local count = exports.ox_inventory:GetItemCount('pawn_package') or 0
        local visualCount = IsPedInAnyVehicle(cache.ped,false) and 0 or math.min(4,count)

        if visualCount ~= #CarriedBoxProps then
            for _, obj in ipairs(CarriedBoxProps) do
                if DoesEntityExist(obj) then DeleteEntity(obj) end
            end
            CarriedBoxProps = {}

            if visualCount > 0 and not IsPedInAnyVehicle(cache.ped, false) then
                local boxModel = joaat('prop_cs_cardbox_01')
                if pcall(lib.requestModel, boxModel, 3000) then
                    lib.requestAnimDict('anim@heists@box_carry@')
                    TaskPlayAnim(cache.ped, 'anim@heists@box_carry@', 'idle', 8.0, -8.0, -1, 49, 0, false, false, false)
                    for i = 1, visualCount do
                        local prop = CreateObject(boxModel, 0.0, 0.0, 0.0, true, true, false)
                        AttachEntityToEntity(prop, cache.ped, GetPedBoneIndex(cache.ped, 28422),
                            0.0, 0.0, -0.05 + ((i - 1) * 0.24), 0.0, 0.0, 0.0, true, true, false, true, 1, true)
                        CarriedBoxProps[#CarriedBoxProps + 1] = prop
                    end
                end
            else
                ClearPedSecondaryTask(cache.ped)
            end
        end

        if visualCount >= 2 and IsPedRunning(cache.ped) and math.random(1, 100) <= 18 then
            SetPedToRagdoll(cache.ped, 2000, 2000, 0, false, false, false)
            notify(('Você tropeçou carregando %s caixas! Caminhe com cuidado.'):format(count), 'warning')
        end
    end
end)

RegisterNetEvent('mri_Qpawnshop:client:startExportMission', function(shopId, order, dropCoords)
    if MissionPed and DoesEntityExist(MissionPed) then exports.mri_Qinteract:removeLocalEntity(MissionPed);DeleteEntity(MissionPed) end
    SetNewWaypoint(dropCoords.x,dropCoords.y)
    notify('Ponto de entrega de exportação marcado no GPS!', 'inform')

    local npcModel = joaat('s_m_m_dockwork_01')
    if not pcall(lib.requestModel,npcModel,5000) then notify('Não foi possível carregar o contato. Inicie a entrega novamente.','error');return end
    local npc = CreatePed(4, npcModel, dropCoords.x, dropCoords.y, dropCoords.z - 1.0, dropCoords.w or 0.0, false, true)
    MissionPed=npc
    SetModelAsNoLongerNeeded(npcModel)
    FreezeEntityPosition(npc,true)
    SetEntityInvincible(npc, true)

    exports.mri_Qinteract:addLocalEntity(npc, {
        {
            label = 'Entregar Exportação (' .. order.item_label .. ')',
            icon = 'fa-solid fa-truck-ramp-box',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = '📦 Confirmar Entrega de Exportação',
                    content = ('**MERCADORIA SOLICITADA:** %sx %s\n**PAGAMENTO ESTIMADO:** $%s (+%s XP)\n\nDeseja entregar a carga agora?'):format(
                        order.qty, order.item_label, order.payout, order.xp_reward
                    ),
                    centered = true,
                    cancel = true,
                    labels = { cancel = 'VOLTAR', confirm = 'CONFIRMAR ENTREGA' }
                })
                if confirm == 'confirm' then
                    TriggerServerEvent('mri_Qpawnshop:server:completeExportOrder', shopId, order.id)

                end
            end
        }
    })
end)

RegisterNetEvent('mri_Qpawnshop:client:startSupplierCollection', function(shopId, queueItems, houseCoords)
    SetNewWaypoint(houseCoords.x, houseCoords.y)
    notify('Vá até o endereço do fornecedor marcado no GPS para coletar os pacotes!', 'inform')

    if MissionZone then MissionZone:remove() end
    local collectZone
    local collecting=false
    collectZone = addInteractionZone(vec3(houseCoords.x, houseCoords.y, houseCoords.z), 2.0, {
{label = "Coletar mercadorias do fornecedor", icon = 'fa-solid fa-truck', canInteract = function() return not CurrentComputerShop and not lib.getOpenContextMenu() and not collecting end, onSelect = function()

                if collecting then return end
                collecting=true

                lib.requestAnimDict('timetable@jimmy@doorknock@')
                TaskPlayAnim(cache.ped, 'timetable@jimmy@doorknock@', 'knockdoor_idle', 8.0, -8.0, 3000, 0, 0, false, false, false)
                notify('Batendo na porta... Aguarde o fornecedor.', 'inform')
                Wait(3200)

                local sModel = joaat('a_m_y_hipster_01')
                if pcall(lib.requestModel, sModel, 5000) then
                    local sPed = CreatePed(4, sModel, houseCoords.x, houseCoords.y, houseCoords.z - 1.0, houseCoords.w or 0.0, false, true)
                    Wait(1200)
                    DeleteEntity(sPed)
                end

                TriggerServerEvent('mri_Qpawnshop:server:completeSupplierCollection',shopId)
                Wait(1000)
                collecting=false
end}
})
    MissionZone=collectZone
end)

RegisterNUICallback('closeComputer', function(_, cb)
    CurrentComputerShop=nil
    SetNuiFocus(false,false)
    SendNUIMessage({action='closeComputerUI'})
    cb({ok=true})
end)

RegisterNUICallback('computerAction', function(body, cb)
    if not CurrentComputerShop or type(body) ~= 'table' then cb({ ok = false }); return end
    TriggerServerEvent('mri_Qpawnshop:server:computerAction', CurrentComputerShop, body.action, body.data or {})
    cb({ ok = true })
end)

RegisterNUICallback('openStashFromPC', function(body, cb)
    local shopId = CurrentComputerShop
    if not shopId or type(body)~='table' or type(body.stashId)~='string' or not body.stashId:match('^pawnshop_'..shopId..'_') then cb({ok=false});return end
    CurrentComputerShop=nil
    SetNuiFocus(false,false)
    SendNUIMessage({action='closeComputerUI'})
    exports.ox_inventory:openInventory('stash',body.stashId)
    cb({ ok = true })
end)

RegisterNUICallback('placeNewShelf', function(body, cb)
    local shopId = CurrentComputerShop
    if not shopId or type(body) ~= 'table' then cb({ ok = false }); return end
    CurrentComputerShop = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeComputerUI' })
    cb({ ok = true })

    CreateThread(function()
        local zone = runVisualZonePlacement('POSICIONAR PRATELEIRA: ' .. (body.category or 'general_goods'))
        if zone then
            zone.category = body.category or 'general_goods'
            TriggerServerEvent('mri_Qpawnshop:server:saveNewShelf', shopId, zone)
        end
    end)
end)

CreateThread(function()
    Wait(1500)
    local initialShops = lib.callback.await('mri_Qpawnshop:server:getShops', false)
    if initialShops then
        TriggerEvent('mri_Qpawnshop:client:syncShops', initialShops)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearWorldEntities()
    SetNuiFocus(false,false)
    lib.hideTextUI()
    ClearPedSecondaryTask(cache.ped)
    if MissionZone then MissionZone:remove() end
    if MissionPed and DoesEntityExist(MissionPed) then exports.mri_Qinteract:removeLocalEntity(MissionPed);DeleteEntity(MissionPed) end
    for _, obj in ipairs(CarriedBoxProps) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
end)

RegisterNetEvent('mri_Qpawnshop:client:missionComplete',function(kind)
    if kind=='export' and MissionPed then
        if DoesEntityExist(MissionPed) then exports.mri_Qinteract:removeLocalEntity(MissionPed);DeleteEntity(MissionPed) end
        MissionPed=nil
    elseif kind=='supplier' and MissionZone then MissionZone:remove();MissionZone=nil;lib.hideTextUI() end
end)
RegisterNetEvent('mri_Qpawnshop:client:takeFleet',function(shopId,id,netId,row)
    local deadline=GetGameTimer()+10000
    while not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer()<deadline do Wait(50) end
    if not NetworkDoesEntityExistWithNetworkId(netId) then notify('Veículo não carregado. Confira a garagem.','error');return end
    local entity=NetToVeh(netId)
    FleetVehicleEntity,FleetVehicleId,FleetShopId=entity,id,shopId
    SetVehicleFuelLevel(entity,(row.fuel or 100)+0.0)
    SetVehicleBodyHealth(entity,(row.body or 100)*10.0)
    SetVehicleEngineHealth(entity,(row.engine or 100)*10.0)
    TaskWarpPedIntoVehicle(cache.ped,entity,-1)
    notify('Veículo retirado da frota.','success')
end)
RegisterNetEvent('mri_Qpawnshop:client:fleetReturned',function() FleetVehicleEntity,FleetVehicleId,FleetShopId=nil,nil,nil end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload',function()
    CurrentComputerShop=nil;SetNuiFocus(false,false);SendNUIMessage({action='closeComputerUI'})
end)
