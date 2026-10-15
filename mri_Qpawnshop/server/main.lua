local core = exports.qbx_core
local inventory = exports.ox_inventory

local Shops = {}
local SupplierQueues = {}
local ActiveOfferStashes = {}
local PendingCreators = {}
local dbReady = false
local ShopLocks, PlayerLocks, LastAction = {}, {}, {}
local ExportMissions, SupplierMissions, FleetEntities = {}, {}, {}
local hasPermission

local function decode(value, fallback)
    if type(value) == 'table' then return value end
    local ok, result = pcall(json.decode, value or '')
    return ok and type(result) == 'table' and result or (fallback or {})
end
local function number(value, minimum, maximum)
    local n = tonumber(value)
    if not n or n ~= n or n % 1 ~= 0 or n < (minimum or 0) or n > (maximum or 100000000) then return nil end
    return n
end
local function validPoint(p)
    if type(p) ~= 'table' then return false end
    for _, k in ipairs({'x', 'y', 'z'}) do
        if type(p[k]) ~= 'number' or p[k] ~= p[k] or math.abs(p[k]) > 20000 then return false end
    end
    return true
end
local function nearPoint(src, p, distance)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and validPoint(p) and #(GetEntityCoords(ped) - vec3(p.x, p.y, p.z)) <= (distance or 5.0)
end
local function nearShop(src, shop, key)
    if key then return nearPoint(src, shop.coords[key], key == 'garage' and 12.0 or 6.0) end
    for _, p in pairs(shop.coords or {}) do if nearPoint(src, p, 8.0) then return true end end
    for _, p in ipairs(shop.shelves or {}) do if nearPoint(src, p, 6.0) then return true end end
    return false
end
local function transaction(queries)
    local ok, result = pcall(MySQL.transaction.await, queries)
    if not ok or not result then print('[mri_Qpawnshop] Transação de banco revertida.'); return false end
    return true
end
local function query(sql, values) return {query = sql, values = values} end
local function safeAdd(inv, name, count, metadata)
    local ok, result = pcall(function() return inventory:AddItem(inv, name, count, metadata) end)
    return ok and result
end
local function restoreItems(inv, lines)
    for _, line in ipairs(lines) do
        if not safeAdd(inv, line.name, line.count, line.metadata) then
            print(('[mri_Qpawnshop] Falha ao devolver %s x%s ao inventário %s'):format(line.name, line.count, inv))
        end
    end
end
local function removeLines(inv, lines)
    local removed = {}
    for _, line in ipairs(lines) do
        if not inventory:RemoveItem(inv, line.name, line.count, line.metadata, line.slot) then restoreItems(inv, removed); return false end
        removed[#removed + 1] = line
    end
    return true
end
local function stockQueries(shopId, category, item, count, metadata, price)
    return {
        query('INSERT INTO pawnshop_inventory (shop_id, category, item_name, qty, price, rrp) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty)', {shopId, category, item, count, price, price}),
        query('INSERT INTO pawnshop_stock_lots (shop_id, category, item_name, qty, metadata) VALUES (?, ?, ?, ?, ?)', {shopId, category, item, count, json.encode(metadata or {})})
    }
end
local function appendQueries(target, incoming) for _, q in ipairs(incoming) do target[#target + 1] = q end end

local EventRules = {
    buyShop = {point = 'forSaleSign'}, openOfferStash = {point = 'ped'},
    finalizeCustomerOffer = {point = 'ped'}, buybackPawnedItem = {point = 'ped'}, joinLoyalty = {point = 'ped'},
    buyFromShelf = {}, computerAction = {point = 'computer'}, saveNewShelf = {permission = 'manage_shelves'},
    processPackaging = {point = 'packaging', permission = 'manage_packaging'},
    spawnFleet = {point='garage',permission='manage_vehicles'}, returnFleet = {point='garage',permission='manage_vehicles'},
    completeExportOrder = {remote = true, permission = 'start_exports'},
    completeSupplierCollection = {remote = true, permission = 'accept_suppliers'}
}
local function registerEvent(name, handler)
    RegisterNetEvent(name, function(shopId, ...)
        local src, args = source, table.pack(...)
        local suffix = name:match(':server:(.+)$')
        local rule = EventRules[suffix] or {}
        if not dbReady or PlayerLocks[src] or (LastAction[src] or 0) > GetGameTimer() then return end
        if suffix ~= 'createShop' then
            shopId = number(shopId, 1)
            local shop = shopId and Shops[shopId]
            if not shop or ShopLocks[shopId] or (not rule.remote and not nearShop(src, shop, rule.point)) then return end
            ShopLocks[shopId] = true
            PlayerLocks[src] = true
        else PlayerLocks[src] = true end
        local ok, err = xpcall(function()
            if rule.permission and not hasPermission(src, shopId, rule.permission) then return end
            handler(shopId, table.unpack(args, 1, args.n))
        end, debug.traceback)
        if type(shopId) == 'number' then ShopLocks[shopId] = nil end
        PlayerLocks[src], LastAction[src] = nil, GetGameTimer() + 250
        if not ok then
            print('[mri_Qpawnshop] Operação falhou: ' .. tostring(err))
            core:Notify(src, 'Não foi possível concluir. Tente novamente.', 'error')
        end
    end)
end

local function notify(src, msg, kind)
    core:Notify(src, msg, kind or 'inform')
end

-- Verifica permissão administrativa no Qbox ou ACE
local function isAdmin(src)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, 'command.' .. (Config.CreateCommand or 'createpawnshop')) then return true end
    if IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, Config.AdminGroup or 'group.admin') then return true end
    local ok, hasPerm = pcall(function() return core:HasPermission(src, 'admin') or core:HasPermission(src, 'god') end)
    return ok and hasPerm
end

local function getItemInfo(itemName)
    for catKey, cat in pairs(Config.Categories) do
        if cat.items and cat.items[itemName] then
            return cat.items[itemName], catKey
        end
    end
    return nil, nil
end

local function logActivity(shopId, logType, actor, description, amount)
    MySQL.insert.await(
        'INSERT INTO pawnshop_logs (shop_id, log_type, actor, description, amount) VALUES (?, ?, ?, ?, ?)',
        { shopId, logType, actor, description, amount or 0 }
    )
end

local function sendShopEmail(shopId, sender, subject, body, actionType, confidential)
    MySQL.insert.await(
        'INSERT INTO pawnshop_emails (shop_id, sender, subject, body, action_type, is_confidential) VALUES (?, ?, ?, ?, ?, ?)',
        { shopId, sender, subject, body, actionType, confidential and 1 or 0 }
    )
end

local function addShopXP(shopId, amount)
    local shop = Shops[shopId]
    if not shop or amount <= 0 then return end
    shop.xp = (shop.xp or 0) + amount

    local newLevel = shop.level
    for lvl = 1, 5 do
        if Config.ShopLevels[lvl] and shop.xp >= Config.ShopLevels[lvl].xpRequired then
            newLevel = lvl
        end
    end

    if newLevel > shop.level then
        shop.level = newLevel
        shop.rating = math.min(5.0, 2.5 + (newLevel * 0.5))
        if newLevel >= 3 and shop.os_theme == 'classic' then
            sendShopEmail(
                shopId,
                'iFruit Tecnologias',
                'OFERTA EXCLUSIVA: Atualização para iFruit OS Pro!',
                'PARABÉNS!\n\nSua loja alcançou o Nível 3 e foi selecionada para receber gratuitamente a atualização do sistema operacional corporativo para o novo iFruit OS Pro (Modo Escuro + Dock Rápido).\n\nClique no botão abaixo para instalar imediatamente!',
                'upgrade_ifruit',
                false
            )
        end
    end

    MySQL.update.await('UPDATE pawnshop_shops SET xp = ?, level = ?, rating = ? WHERE id = ?', {
        shop.xp, shop.level, shop.rating, shopId
    })
end

hasPermission = function(src, shopId, permKey)
    local player = core:GetPlayer(src)
    local shop = Shops[shopId]
    if not player or not shop then return false end
    local cid = player.PlayerData.citizenid
    if shop.owner_cid == cid or isAdmin(src) then
        return true
    end
    local worker = MySQL.single.await('SELECT permissions FROM pawnshop_workers WHERE shop_id = ? AND citizenid = ?', { shopId, cid })
    if not worker then return false end
    local perms = decode(worker.permissions)
    return permKey=='access_computer' or perms.admin==true or perms[permKey]==true
end

local function registerShopStashes(shop)
    local intakeId = ('pawnshop_%s_intake'):format(shop.id)
    inventory:RegisterStash(intakeId, ('%s - Depósito de Entrada'):format(shop.name), 60, 250000, false)

    local specialId = ('pawnshop_%s_special_offers'):format(shop.id)
    inventory:RegisterStash(specialId, ('%s - Ofertas Especiais'):format(shop.name), 30, 100000, false)

    local pkgId = ('pawnshop_%s_packaging'):format(shop.id)
    inventory:RegisterStash(pkgId, ('%s - Container de Embalagem'):format(shop.name), 20, 100000, false)

    for catKey, cat in pairs(Config.Categories) do
        local shelfStash = ('pawnshop_%s_shelf_%s'):format(shop.id, catKey)
        inventory:RegisterStash(shelfStash, ('%s - %s'):format(shop.name, cat.label), 50, 200000, false)
    end

    for idx, stash in ipairs(shop.stashes or {}) do
        local customId = ('pawnshop_%s_custom_%s'):format(shop.id, idx)
        inventory:RegisterStash(customId, ('%s - %s'):format(shop.name, stash.label or ('Depósito #' .. idx)), 50, 150000, false)
    end
end

local function generateInitialExports(shopId)
    local count = MySQL.scalar.await("SELECT COUNT(*) FROM pawnshop_exports WHERE shop_id = ? AND status = 'pending'", { shopId })
    if (count or 0) >= 3 then return end

    local pool = {
        { name = 'lockpick', label = 'Gazua (Lockpick)', qty = 10, payout = 3200, xp = 35 },
        { name = 'steel',    label = 'Aço Compactado',   qty = 25, payout = 2100, xp = 25 },
        { name = 'rolex',    label = 'Relógio Rolex',    qty = 3,  payout = 2900, xp = 45 },
        { name = 'phone',    label = 'Celular',          qty = 8,  payout = 950,  xp = 20 }
    }

    for _ = 1, 3 - (count or 0) do
        local pick = pool[math.random(#pool)]
        MySQL.insert.await(
            'INSERT INTO pawnshop_exports (shop_id, item_name, item_label, qty, payout, xp_reward, status, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { shopId, pick.name, pick.label, pick.qty, pick.payout, pick.xp, 'pending', os.time() + 86400 }
        )
    end
end

local function generateSupplierOffers(shopId)
    if SupplierQueues[shopId] and #SupplierQueues[shopId].offers > 0 then return end
    SupplierQueues[shopId] = {
        offers = {
            { id = 1, item = 'copper',   label = 'Cobre',            qty = 5, cost = 140, rare = false },
            { id = 2, item = 'lockpick', label = 'Gazua (Lockpick)', qty = 8, cost = 640, rare = false },
            { id = 3, item = 'rolex',    label = 'Relógio Rolex',    qty = 2, cost = 780, rare = true }
        },
        queue = {}
    }
end

local function ensureDatabaseTables()
    local queries = {
        [[CREATE TABLE IF NOT EXISTS pawnshop_supplier_missions (
            id INT AUTO_INCREMENT PRIMARY KEY, shop_id INT NOT NULL, citizenid VARCHAR(50) NOT NULL,
            cost INT NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'active', KEY active_missions (status,shop_id)
        )]],
        [[CREATE TABLE IF NOT EXISTS pawnshop_stock_lots (
            id INT AUTO_INCREMENT PRIMARY KEY, shop_id INT NOT NULL, category VARCHAR(50) NOT NULL,
            item_name VARCHAR(50) NOT NULL, qty INT NOT NULL, metadata LONGTEXT DEFAULT NULL,
            KEY stock_lookup (shop_id, category, item_name, qty)
        )]],
        [[CREATE TABLE IF NOT EXISTS `pawnshop_shops` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `name` VARCHAR(100) NOT NULL,
            `owner_cid` VARCHAR(50) DEFAULT NULL,
            `ownable` TINYINT(1) NOT NULL DEFAULT 1,
            `purchase_price` INT NOT NULL DEFAULT 75000,
            `starting_equity` INT NOT NULL DEFAULT 25000,
            `funds` INT NOT NULL DEFAULT 25000,
            `level` INT NOT NULL DEFAULT 1,
            `xp` INT NOT NULL DEFAULT 0,
            `rating` FLOAT NOT NULL DEFAULT 3.0,
            `os_theme` VARCHAR(20) NOT NULL DEFAULT 'classic',
            `is_open` TINYINT(1) NOT NULL DEFAULT 1,
            `buying_active` TINYINT(1) NOT NULL DEFAULT 1,
            `special_offers_active` TINYINT(1) NOT NULL DEFAULT 1,
            `collections_active` TINYINT(1) NOT NULL DEFAULT 1,
            `exports_active` TINYINT(1) NOT NULL DEFAULT 1,
            `ped_model` VARCHAR(60) NOT NULL DEFAULT 's_m_y_barman_01',
            `ped_scenario` VARCHAR(60) NOT NULL DEFAULT 'WORLD_HUMAN_STAND_IMPATIENT',
            `coords_data` LONGTEXT NOT NULL,
            `categories_data` LONGTEXT NOT NULL,
            `shelves_data` LONGTEXT DEFAULT NULL,
            `stashes_data` LONGTEXT DEFAULT NULL,
            `blip_data` LONGTEXT DEFAULT NULL,
            `stats_data` LONGTEXT DEFAULT NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )]],
        [[CREATE TABLE IF NOT EXISTS `pawnshop_inventory` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `shop_id` INT NOT NULL,
            `category` VARCHAR(50) NOT NULL,
            `item_name` VARCHAR(50) NOT NULL,
            `qty` INT NOT NULL DEFAULT 0,
            `price` INT NOT NULL DEFAULT 100,
            `rrp` INT NOT NULL DEFAULT 100,
            UNIQUE KEY `shop_item` (`shop_id`, `category`, `item_name`)
        )]],
        [[CREATE TABLE IF NOT EXISTS `pawnshop_pawns` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `shop_id` INT NOT NULL,
            `citizenid` VARCHAR(50) NOT NULL,
            `item_name` VARCHAR(50) NOT NULL,
            `item_label` VARCHAR(100) NOT NULL,
            `qty` INT NOT NULL DEFAULT 1,
            `metadata` LONGTEXT DEFAULT NULL,
            `loan_amount` INT NOT NULL,
            `buyback_price` INT NOT NULL,
            `expires_at` INT NOT NULL,
            `status` VARCHAR(20) NOT NULL DEFAULT 'active',
            KEY `lookup_pawn` (`shop_id`, `citizenid`, `status`)
        )]],
        [[CREATE TABLE IF NOT EXISTS `pawnshop_workers` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `shop_id` INT NOT NULL,
            `citizenid` VARCHAR(50) NOT NULL,
            `name` VARCHAR(100) NOT NULL,
            `role_preset` VARCHAR(50) NOT NULL DEFAULT 'Caixa',
            `permissions` LONGTEXT NOT NULL,
            `rep_level` INT NOT NULL DEFAULT 1,
            `rep_xp` INT NOT NULL DEFAULT 0,
            `unclaimed_points` FLOAT NOT NULL DEFAULT 0,
            `total_sales` INT NOT NULL DEFAULT 0,
            UNIQUE KEY `shop_worker` (`shop_id`, `citizenid`)
        )]],
        [[CREATE TABLE IF NOT EXISTS `pawnshop_vehicles` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `shop_id` INT NOT NULL,
            `model` VARCHAR(50) NOT NULL,
            `label` VARCHAR(100) NOT NULL,
            `plate` VARCHAR(15) NOT NULL,
            `fuel` INT NOT NULL DEFAULT 100,
            `body` INT NOT NULL DEFAULT 100,
            `engine` INT NOT NULL DEFAULT 100,
            `status` VARCHAR(20) NOT NULL DEFAULT 'available',
            `insurance_cost` INT NOT NULL DEFAULT 500
        )]],
        [[CREATE TABLE IF NOT EXISTS `pawnshop_loyalty` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `shop_id` INT NOT NULL,
            `citizenid` VARCHAR(50) NOT NULL,
            `customer_name` VARCHAR(100) NOT NULL,
            `tier` VARCHAR(20) NOT NULL DEFAULT 'Basico',
            `points` INT NOT NULL DEFAULT 0,
            `total_spent` INT NOT NULL DEFAULT 0,
            `expires_at` INT NOT NULL DEFAULT 0,
            UNIQUE KEY `shop_customer` (`shop_id`, `citizenid`)
        )]],
        [[CREATE TABLE IF NOT EXISTS `pawnshop_exports` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `shop_id` INT NOT NULL,
            `item_name` VARCHAR(50) NOT NULL,
            `item_label` VARCHAR(100) NOT NULL,
            `qty` INT NOT NULL,
            `payout` INT NOT NULL,
            `xp_reward` INT NOT NULL,
            `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
            `accepted_by` VARCHAR(100) DEFAULT NULL,
            `expires_at` INT NOT NULL
        )]],
        [[CREATE TABLE IF NOT EXISTS `pawnshop_emails` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `shop_id` INT NOT NULL,
            `sender` VARCHAR(100) NOT NULL,
            `subject` VARCHAR(150) NOT NULL,
            `body` LONGTEXT NOT NULL,
            `action_type` VARCHAR(50) DEFAULT NULL,
            `action_status` VARCHAR(20) NOT NULL DEFAULT 'none',
            `is_confidential` TINYINT(1) NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )]],
        [[CREATE TABLE IF NOT EXISTS `pawnshop_logs` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `shop_id` INT NOT NULL,
            `log_type` VARCHAR(30) NOT NULL,
            `actor` VARCHAR(100) NOT NULL,
            `description` VARCHAR(255) NOT NULL,
            `amount` INT NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )]]
    }

    for _, q in ipairs(queries) do
        MySQL.query.await(q)
    end
end

local function loadAllShops()
    Shops = {}
    local rows = MySQL.query.await('SELECT * FROM pawnshop_shops ORDER BY id ASC') or {}
    for _, row in ipairs(rows) do
        local shop = {
            id = tonumber(row.id),
            name = row.name,
            owner_cid = row.owner_cid,
            ownable = (row.ownable == 1 or row.ownable == true),
            purchase_price = row.purchase_price,
            starting_equity = row.starting_equity,
            funds = row.funds,
            level = row.level,
            xp = row.xp,
            rating = row.rating,
            os_theme = row.os_theme or 'classic',
            is_open = (row.is_open == 1 or row.is_open == true),
            buying_active = (row.buying_active == 1 or row.buying_active == true),
            special_offers_active = (row.special_offers_active == 1 or row.special_offers_active == true),
            collections_active = (row.collections_active == 1 or row.collections_active == true),
            exports_active = (row.exports_active == 1 or row.exports_active == true),
            ped_model = row.ped_model,
            ped_scenario = row.ped_scenario,
            coords = decode(row.coords_data),
            categories = decode(row.categories_data),
            shelves = decode(row.shelves_data),
            stashes = decode(row.stashes_data),
            blip = decode(row.blip_data),
            stats = decode(row.stats_data)
        }
        Shops[shop.id] = shop
        registerShopStashes(shop)
        generateInitialExports(shop.id)
        generateSupplierOffers(shop.id)

        for catKey, enabled in pairs(shop.categories) do
            if enabled and Config.Categories[catKey] then
                for itemName, info in pairs(Config.Categories[catKey].items) do
                    MySQL.insert.await(
                        'INSERT IGNORE INTO pawnshop_inventory (shop_id, category, item_name, qty, price, rrp) VALUES (?, ?, ?, 0, ?, ?)',
                        { shop.id, catKey, itemName, info.baseValue, info.baseValue }
                    )
                end
            end
        end
    end
    TriggerClientEvent('mri_Qpawnshop:client:syncShops', -1, Shops)
end

MySQL.ready(function()
    local ok, err = xpcall(function()
        ensureDatabaseTables()
        local unfinished=MySQL.query.await("SELECT shop_id,SUM(cost) AS refund FROM pawnshop_supplier_missions WHERE status = 'active' GROUP BY shop_id") or {}
        for _,mission in ipairs(unfinished) do
            assert(transaction({query('UPDATE pawnshop_shops SET funds = funds + ? WHERE id = ?',{mission.refund,mission.shop_id}),query("UPDATE pawnshop_supplier_missions SET status = 'refunded' WHERE shop_id = ? AND status = 'active'",{mission.shop_id})}),'Falha ao devolver coleta interrompida')
        end
        MySQL.query.await("UPDATE pawnshop_shops SET owner_cid = NULL WHERE owner_cid = ''")
        MySQL.update.await("UPDATE pawnshop_vehicles SET status = 'available' WHERE status = 'out'")
        loadAllShops()
    end, debug.traceback)

    if not ok then
        print('[mri_Qpawnshop] ERRO AO INICIALIZAR BANCO DE DADOS: ' .. tostring(err))
        return
    end

    dbReady = true
    print('[mri_Qpawnshop] Tabelas verificadas e lojas de penhor carregadas com sucesso.')
end)

-- Expiração automática sem concorrer com o resgate do cliente.
CreateThread(function()
    while not dbReady do Wait(1000) end
    while true do
        Wait(60000)
        local ok,err=xpcall(function()
            local expired=MySQL.query.await("SELECT * FROM pawnshop_pawns WHERE status = 'active' AND expires_at <= ?",{os.time()}) or {}
            for _,pawn in ipairs(expired) do
                if not ShopLocks[pawn.shop_id] then
                    ShopLocks[pawn.shop_id]=true
                    local converted,problem=xpcall(function()
                        local current=MySQL.single.await("SELECT * FROM pawnshop_pawns WHERE id = ? AND status = 'active' AND expires_at <= ?",{pawn.id,os.time()})
                        local info,category=getItemInfo(pawn.item_name)
                        if current and info then
                            local statements=stockQueries(pawn.shop_id,category,pawn.item_name,pawn.qty,decode(pawn.metadata),info.baseValue)
                            statements[#statements+1]=query("UPDATE pawnshop_pawns SET status = 'expired' WHERE id = ? AND status = 'active'",{pawn.id})
                            transaction(statements)
                        end
                    end,debug.traceback)
                    ShopLocks[pawn.shop_id]=nil
                    if not converted then print('[mri_Qpawnshop] Expiração falhou: '..tostring(problem)) end
                end
            end
            MySQL.update.await("UPDATE pawnshop_exports SET status = 'expired' WHERE status IN ('pending','active') AND expires_at <= ?",{os.time()})
            for shopId in pairs(Shops) do if not ShopLocks[shopId] then generateInitialExports(shopId) end end
        end,debug.traceback)
        if not ok then print('[mri_Qpawnshop] Manutenção falhou: '..tostring(err)) end
        for src,mission in pairs(ExportMissions) do if mission.expires<os.time() then ExportMissions[src]=nil;TriggerClientEvent('mri_Qpawnshop:client:missionComplete',src,'export') end end
        -- Supplier missions remain claimable until cancellation/refund; no paid cargo is silently discarded.
    end
end)

-- Comando Admin /createpawnshop
lib.addCommand(Config.CreateCommand, {
    help = 'Criar uma nova Loja de Penhor in-game',
    restricted = Config.AdminGroup
}, function(src)
    if src == 0 then return end
    PendingCreators[src] = GetGameTimer() + (10 * 60 * 1000)
    TriggerClientEvent('mri_Qpawnshop:client:openCreatorWizard', src)
end)

lib.callback.register('mri_Qpawnshop:server:getShops', function()
    local deadline = GetGameTimer() + 10000
    while not dbReady and GetGameTimer() < deadline do Wait(100) end
    return Shops
end)

-- Salva nova loja criada pelo Editor In-Game no Banco de Dados
registerEvent('mri_Qpawnshop:server:createShop', function(payload)
    local src = source
    if type(payload) ~= 'table' then
        notify(src, 'Dados inválidos recebidos na criação.', 'error')
        return
    end

    if not isAdmin(src) then
        notify(src, 'Sem permissão para criar loja. Use /' .. Config.CreateCommand, 'error')
        return
    end

    if not PendingCreators[src] or PendingCreators[src] < GetGameTimer() then return end
    if type(payload.name) ~= 'string' or #payload.name < 1 or #payload.name > 100 or type(payload.coords) ~= 'table' or type(payload.categories) ~= 'table' then return end
    if not number(payload.purchasePrice, 0) or not number(payload.startingEquity, 0) then return end
    for _, key in ipairs({'ped', 'computer', 'packaging', 'garage', 'forSaleSign'}) do
        local p = payload.coords[key]
        if not validPoint(p) or not nearPoint(src, p, 150.0) then return end
        p.w = tonumber(p.w) or 0.0
        p.radius = math.max(0.6, math.min(4.0, tonumber(p.radius) or 1.5))
    end
    if type(payload.pedModel) ~= 'string' or #payload.pedModel > 60 or not payload.pedModel:match('^[%w_]+$') then return end
    local scenarioOK = false
    for _, entry in ipairs(Config.PedScenarios) do if entry.value == payload.pedScenario then scenarioOK = true end end
    if not scenarioOK then return end
    local categories = {}
    for key in pairs(Config.Categories) do categories[key] = payload.categories[key] == true end
    payload.categories = categories
    local blip = type(payload.blip) == 'table' and payload.blip or {}
    payload.blip = {label = tostring(blip.label or payload.name):sub(1,100), sprite = number(blip.sprite,0,1000) or 431, color = number(blip.color,0,100) or 5, scale = math.max(0.1,math.min(2.0,tonumber(blip.scale) or 0.8))}
    PendingCreators[src] = nil

    local ok, insertedId = xpcall(function()
        ensureDatabaseTables()

        local shopName = tostring(payload.name or 'Loja de Penhor')
        local ownableInt = payload.ownable and 1 or 0
        local purchasePrice = math.max(0, math.floor(tonumber(payload.purchasePrice) or 75000))
        local startingEquity = math.max(0, math.floor(tonumber(payload.startingEquity) or 25000))
        local pedModel = tostring(payload.pedModel or 's_m_y_barman_01')
        local pedScenario = tostring(payload.pedScenario or 'WORLD_HUMAN_STAND_IMPATIENT')
        local coordsJson = json.encode(payload.coords or {})
        local categoriesJson = json.encode(payload.categories or {})
        local shelvesJson = json.encode({})
        local stashesJson = json.encode({})
        local blipJson = json.encode(payload.blip or {})
        local statsJson = json.encode({ itemsSold = 0, completedExports = 0, totalTransactions = 0, netProfit = 0 })

        return MySQL.insert.await([[
            INSERT INTO pawnshop_shops
            (name, ownable, purchase_price, starting_equity, funds, ped_model, ped_scenario, coords_data, categories_data, shelves_data, stashes_data, blip_data, stats_data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            shopName,
            ownableInt,
            purchasePrice,
            startingEquity,
            startingEquity,
            pedModel,
            pedScenario,
            coordsJson,
            categoriesJson,
            shelvesJson,
            stashesJson,
            blipJson,
            statsJson
        })
    end, debug.traceback)

    if not ok or not insertedId then
        print('[mri_Qpawnshop] ERRO AO SALVAR LOJA NO MYSQL: ' .. tostring(insertedId))
        notify(src, 'Erro ao salvar loja no banco de dados. Verifique o console do servidor.', 'error')
        return
    end

    sendShopEmail(insertedId, 'Associação Comercial de Penhores', 'Bem-vindo à ' .. (payload.name or 'Loja de Penhor'),
        'Parabéns pela inauguração da sua Loja de Penhor!\n\nUtilize os aplicativos "Gestão da Loja" e "Estoque & Preços" no computador para posicionar prateleiras, definir preços, contratar funcionários e iniciar missões de fornecedores.', nil, false)

    loadAllShops()
    notify(src, ('Loja de Penhor "%s" (ID #%s) criada e salva no banco!'):format(payload.name, insertedId), 'success')
end)

-- Compra da loja na placa "À Venda"
registerEvent('mri_Qpawnshop:server:buyShop', function(shopId)
    local src, shop = source, Shops[shopId]
    local player = core:GetPlayer(src)
    if not player or not shop.ownable or shop.owner_cid then return end
    local due = shop.purchase_price + shop.starting_equity
    if due > 0 and not player.Functions.RemoveMoney('bank', due, 'pawnshop-purchase') then notify(src, 'Saldo bancário insuficiente.', 'error'); return end
    local cid = player.PlayerData.citizenid
    local statements = {
        query('UPDATE pawnshop_shops SET owner_cid = ?, funds = ? WHERE id = ? AND owner_cid IS NULL', {cid, shop.starting_equity, shopId}),
        query('INSERT INTO pawnshop_vehicles (shop_id, model, label, plate, status, insurance_cost) VALUES (?, ?, ?, ?, ?, ?)', {shopId, 'rumpo', 'Van Rumpo', ('PWN%05d'):format(math.random(10000,99999)), 'available', 500})
    }
    if not transaction(statements) then if due > 0 then player.Functions.AddMoney('bank',due,'pawnshop-refund') end; return end
    shop.owner_cid, shop.funds = cid, shop.starting_equity
    logActivity(shopId, 'Financeiro', player.PlayerData.charinfo.firstname, 'Compra da loja e capital inicial', due)
    TriggerClientEvent('mri_Qpawnshop:client:syncShops', -1, Shops)
    notify(src, 'Loja adquirida com sucesso!', 'success')
end)

-- Abre a Bancada de Avaliação ("Ofertar Itens")
registerEvent('mri_Qpawnshop:server:openOfferStash', function(shopId)
    local src = source
    local player = core:GetPlayer(src)
    local shop = Shops[shopId]
    if not player or not shop or not shop.is_open or not shop.buying_active then
        notify(src, 'A loja não está comprando ou penhorando itens no momento.', 'error')
        return
    end
    local stashId = ('pawn_offer_%s_%s'):format(shopId, player.PlayerData.citizenid)
    inventory:RegisterStash(stashId, ('%s - Bancada de Avaliação'):format(shop.name), 15, 50000, false, nil, vec3(shop.coords.ped.x, shop.coords.ped.y, shop.coords.ped.z))
    ActiveOfferStashes[src] = { stashId = stashId, shopId = shopId }
    TriggerClientEvent('mri_Qpawnshop:client:openStash', src, stashId)
end)

-- Calcula a avaliação dos itens colocados na Bancada
local function evaluateOfferedItems(src, shopId)
    local player = core:GetPlayer(src)
    local shop = Shops[shopId]
    if not dbReady or not player or not shop or not shop.is_open or not shop.buying_active or not nearShop(src, shop, 'ped') then return nil end
    local active = ActiveOfferStashes[src]
    if not active or active.shopId ~= shopId then return nil end

    local cid = player.PlayerData.citizenid
    local stashId = ('pawn_offer_%s_%s'):format(shopId, cid)
    local slotItems = inventory:GetInventoryItems(stashId) or {}

    local loyalty = MySQL.single.await('SELECT * FROM pawnshop_loyalty WHERE shop_id = ? AND citizenid = ?', { shopId, cid })
    local tierCfg = loyalty and loyalty.expires_at > os.time() and Config.LoyaltyTiers[loyalty.tier] or {sellBonus = 0, pawnBonus = 0}

    local lines = {}
    local totalCount = 0
    local marketValue = 0

    for _, item in pairs(slotItems) do
        if item and item.name and item.count > 0 then
            local info, catKey = getItemInfo(item.name)
            if info and shop.categories[catKey] then
                local customRow = MySQL.single.await('SELECT price FROM pawnshop_inventory WHERE shop_id = ? AND item_name = ?', { shopId, item.name })
                local unitBase = info.baseValue -- Preço de recompra é definido na configuração, nunca pelo preço de revenda.
                local lineTotal = unitBase * item.count
                totalCount = totalCount + item.count
                marketValue = marketValue + lineTotal
                lines[#lines + 1] = {
                    slot = item.slot,
                    name = item.name,
                    label = item.label or info.label,
                    count = item.count,
                    metadata = item.metadata,
                    unitValue = unitBase,
                    lineValue = lineTotal
                }
            end
        end
    end

    if totalCount == 0 then return { empty = true } end

    local sellRate = Config.SellRateBase + (tierCfg.sellBonus or 0)
    local pawnRate = Config.PawnRateBase + (tierCfg.pawnBonus or 0)

    local sellOffer = math.floor(marketValue * sellRate)
    local pawnOffer = math.floor(marketValue * pawnRate)
    local buybackTotal = math.floor(marketValue * Config.PawnBuybackMultiplier)

    return {
        empty = false,
        items = lines,
        totalItems = totalCount,
        marketValue = marketValue,
        sellOffer = sellOffer,
        sellPercent = math.floor(sellRate * 100),
        pawnOffer = pawnOffer,
        pawnPercent = math.floor(pawnRate * 100),
        buybackPrice = buybackTotal,
        durationHours = Config.PawnDurationHours
    }
end
lib.callback.register('mri_Qpawnshop:server:evaluateOfferedItems', evaluateOfferedItems)

-- Finaliza a Venda à Vista ou Penhor dos itens avaliados
registerEvent('mri_Qpawnshop:server:finalizeCustomerOffer', function(shopId, mode)
    local src, shop = source, Shops[shopId]
    local player = core:GetPlayer(src)
    if not player or (mode ~= 'sell' and mode ~= 'pawn') then return end
    local evaluation = evaluateOfferedItems(src, shopId)
    if not evaluation or evaluation.empty then notify(src, 'Nenhum item elegível na bancada.', 'error'); return end
    local payout = mode == 'pawn' and evaluation.pawnOffer or evaluation.sellOffer
    if not number(payout,1) then return end
    if shop.ownable and shop.owner_cid and shop.funds < payout then notify(src,'Fundos insuficientes na loja.','error');return end
    local cid = player.PlayerData.citizenid
    if mode == 'pawn' then
        local count = MySQL.scalar.await("SELECT COUNT(*) FROM pawnshop_pawns WHERE shop_id = ? AND citizenid = ? AND status = 'active'", {shopId,cid}) or 0
        if count + #evaluation.items > Config.MaxActivePawnsPerPlayer then notify(src,'Limite de penhores ativos atingido.','error');return end
    end
    local stash = ('pawn_offer_%s_%s'):format(shopId,cid)
    if not removeLines(stash,evaluation.items) then notify(src,'Os itens da bancada foram alterados. Avalie novamente.','error');return end
    local statements = {}
    for _, line in ipairs(evaluation.items) do
        local _, category = getItemInfo(line.name)
        if mode == 'pawn' then
            statements[#statements+1] = query("INSERT INTO pawnshop_pawns (shop_id,citizenid,item_name,item_label,qty,metadata,loan_amount,buyback_price,expires_at,status) VALUES (?,?,?,?,?,?,?,?,?,'active')",
                {shopId,cid,line.name,line.label,line.count,json.encode(line.metadata or {}),math.floor(line.lineValue*evaluation.pawnPercent/100),math.floor(line.lineValue*Config.PawnBuybackMultiplier),os.time()+Config.PawnDurationHours*3600})
        else appendQueries(statements,stockQueries(shopId,category,line.name,line.count,line.metadata,line.unitValue)) end
    end
    local funds = shop.funds
    if shop.ownable and shop.owner_cid then
        funds = funds-payout
        statements[#statements+1] = query('UPDATE pawnshop_shops SET funds = ? WHERE id = ?', {funds,shopId})
    end
    if not transaction(statements) then restoreItems(stash,evaluation.items);notify(src,'Operação cancelada. Itens devolvidos à bancada.','error');return end
    shop.funds = funds
    player.Functions.AddMoney('cash',payout,'pawnshop-'..mode)
    local points=math.max(1,math.floor(payout/25))
    MySQL.update.await('UPDATE pawnshop_loyalty SET points = points + ?, total_spent = total_spent + ? WHERE shop_id = ? AND citizenid = ?', {points,payout,shopId,cid})
    addShopXP(shopId,math.max(5,math.floor(payout/100)))
    logActivity(shopId,mode=='pawn' and 'Penhor' or 'Vendas',player.PlayerData.charinfo.firstname,('Recebeu %s itens'):format(evaluation.totalItems),-payout)
    notify(src,('Operação concluída! Você recebeu $%s.'):format(payout),'success')
end)

lib.callback.register('mri_Qpawnshop:server:getMyPawnedItems', function(src, shopId)
    local player = core:GetPlayer(src)
    if not player or not Shops[shopId] or not nearShop(src,Shops[shopId],'ped') then return {} end
    local rows = MySQL.query.await(
        "SELECT * FROM pawnshop_pawns WHERE shop_id = ? AND citizenid = ? AND status = 'active' ORDER BY id DESC",
        { shopId, player.PlayerData.citizenid }
    ) or {}
    local now = os.time()
    for _, row in ipairs(rows) do
        local rem = math.max(0, row.expires_at - now)
        row.hoursLeft = math.floor(rem / 3600)
        row.minsLeft = math.floor((rem % 3600) / 60)
    end
    return rows
end)

registerEvent('mri_Qpawnshop:server:buybackPawnedItem', function(shopId,pawnId)
    local src,shop=source,Shops[shopId]
    local player=core:GetPlayer(src)
    if not player or not shop.is_open or not number(pawnId,1) then return end
    local row=MySQL.single.await("SELECT * FROM pawnshop_pawns WHERE id = ? AND shop_id = ? AND citizenid = ? AND status = 'active' AND expires_at > ?",{pawnId,shopId,player.PlayerData.citizenid,os.time()})
    if not row then notify(src,'Penhor expirado ou indisponível.','error');return end
    local metadata=decode(row.metadata)
    if not inventory:CanCarryItem(src,row.item_name,row.qty,metadata) then notify(src,'Inventário sem espaço.','error');return end
    if not player.Functions.RemoveMoney('cash',row.buyback_price,'pawnshop-buyback') then notify(src,'Dinheiro insuficiente.','error');return end
    local ok,result=pcall(MySQL.update.await,"UPDATE pawnshop_pawns SET status = 'redeemed' WHERE id = ? AND status = 'active' AND expires_at > ?",{pawnId,os.time()})
    if not ok or result~=1 then player.Functions.AddMoney('cash',row.buyback_price,'pawnshop-refund');return end
    if not safeAdd(src,row.item_name,row.qty,metadata) then
        player.Functions.AddMoney('cash',row.buyback_price,'pawnshop-refund')
        MySQL.update.await("UPDATE pawnshop_pawns SET status = 'active' WHERE id = ? AND status = 'redeemed'",{pawnId});return
    end
    shop.funds=shop.funds+row.buyback_price
    MySQL.update.await('UPDATE pawnshop_shops SET funds = ? WHERE id = ?',{shop.funds,shopId})
    addShopXP(shopId,15)
    notify(src,'Itens resgatados!','success')
end)

lib.callback.register('mri_Qpawnshop:server:getShelfItems', function(src,shopId,category)
    local shop=Shops[number(shopId,1)]
    if not dbReady or not shop or not shop.is_open or not Config.Categories[category] or not shop.categories[category] or not nearShop(src,shop) then return {} end
    if category=='special_offers' and not shop.special_offers_active then return {} end
    local rows = MySQL.query.await('SELECT * FROM pawnshop_inventory WHERE shop_id = ? AND category = ? ORDER BY item_name ASC', { shopId, category }) or {}
    for _, r in ipairs(rows) do
        local info = getItemInfo(r.item_name)
        r.label = info and info.label or r.item_name
    end
    return rows
end)

registerEvent('mri_Qpawnshop:server:buyFromShelf',function(shopId,itemId)
    local src,shop=source,Shops[shopId]
    local player=core:GetPlayer(src)
    if not player or not shop.is_open or not number(itemId,1) then return end
    local item=MySQL.single.await('SELECT * FROM pawnshop_inventory WHERE id = ? AND shop_id = ? AND qty > 0',{itemId,shopId})
    if not item or not number(item.price,1) or not shop.categories[item.category] then return end
    if item.category=='special_offers' and not shop.special_offers_active then return end
    local lot=MySQL.single.await('SELECT * FROM pawnshop_stock_lots WHERE shop_id = ? AND category = ? AND item_name = ? AND qty > 0 ORDER BY id LIMIT 1',{shopId,item.category,item.item_name})
    local metadata=lot and decode(lot.metadata) or {}
    if not inventory:CanCarryItem(src,item.item_name,1,metadata) then notify(src,'Inventário sem espaço.','error');return end
    if not player.Functions.RemoveMoney('cash',item.price,'pawnshop-shelf-buy') then notify(src,'Dinheiro insuficiente.','error');return end
    local saved,result=pcall(MySQL.update.await,'UPDATE pawnshop_inventory SET qty = qty - 1 WHERE id = ? AND qty > 0',{itemId})
    if not saved or result~=1 then player.Functions.AddMoney('cash',item.price,'pawnshop-refund');return end
    if not safeAdd(src,item.item_name,1,metadata) then
        player.Functions.AddMoney('cash',item.price,'pawnshop-refund')
        MySQL.update.await('UPDATE pawnshop_inventory SET qty = qty + 1 WHERE id = ?',{itemId});return
    end
    if lot then MySQL.update.await('UPDATE pawnshop_stock_lots SET qty = qty - 1 WHERE id = ? AND qty > 0',{lot.id}) end
    shop.funds=shop.funds+item.price
    shop.stats.itemsSold=(shop.stats.itemsSold or 0)+1
    shop.stats.totalTransactions=(shop.stats.totalTransactions or 0)+1
    shop.stats.netProfit=(shop.stats.netProfit or 0)+item.price
    MySQL.update.await('UPDATE pawnshop_shops SET funds = ?, stats_data = ? WHERE id = ?',{shop.funds,json.encode(shop.stats),shopId})
    addShopXP(shopId,10)
    notify(src,'Compra concluída!','success')
end)

registerEvent('mri_Qpawnshop:server:joinLoyalty', function(shopId, tierName)
    local src = source
    local player = core:GetPlayer(src)
    local tier = Config.LoyaltyTiers[tierName]
    local shop = Shops[shopId]
    if not player or not tier or not shop or not shop.is_open then return end
    local current=MySQL.single.await('SELECT * FROM pawnshop_loyalty WHERE shop_id = ? AND citizenid = ?',{shopId,player.PlayerData.citizenid})
    if current and current.tier==tierName and current.expires_at>os.time() then notify(src,'Este plano já está ativo.','inform');return end

    if tier.price > 0 and not player.Functions.RemoveMoney('cash', tier.price, 'pawnshop-loyalty') then
        notify(src, ('Dinheiro insuficiente para o plano %s ($%s).'):format(tierName, tier.price), 'error')
        return
    end

    local cid = player.PlayerData.citizenid
    local fullName = ('%s %s'):format(player.PlayerData.charinfo.firstname, player.PlayerData.charinfo.lastname)
    local saved,result=pcall(MySQL.insert.await,[[
        INSERT INTO pawnshop_loyalty (shop_id, citizenid, customer_name, tier, points, expires_at)
        VALUES (?, ?, ?, ?, 10, ?)
        ON DUPLICATE KEY UPDATE tier = VALUES(tier), expires_at = VALUES(expires_at)
    ]], { shopId, cid, fullName, tierName, os.time() + (7 * 86400) })
    if not saved or not result then if tier.price>0 then player.Functions.AddMoney('cash',tier.price,'pawnshop-loyalty-refund') end;return end

    if tier.price > 0 then
        shop.funds = shop.funds + tier.price
        MySQL.update.await('UPDATE pawnshop_shops SET funds = ? WHERE id = ?', { shop.funds, shopId })
    end

    logActivity(shopId, 'Fidelidade', fullName, ('Assinou o plano %s'):format(tierName), tier.price)
    notify(src, ('Bem-vindo ao Programa de Fidelidade (%s)!'):format(tierName), 'success')
end)

local function getComputerData(src, shopId, fromGarage)
    shopId = number(shopId, 1)
    local player = core:GetPlayer(src)
    local shop = Shops[shopId]
    if not dbReady or not player or not shop or not nearShop(src, shop, fromGarage and 'garage' or 'computer') then return nil end

    local cid = player.PlayerData.citizenid
    local isOwner = (shop.owner_cid == cid) or isAdmin(src)
    local worker = MySQL.single.await('SELECT * FROM pawnshop_workers WHERE shop_id = ? AND citizenid = ?', { shopId, cid })

    if not isOwner and not worker then
        return { denied = true }
    end

    local invRows = MySQL.query.await('SELECT * FROM pawnshop_inventory WHERE shop_id = ? ORDER BY category, item_name', { shopId }) or {}
    for _, r in ipairs(invRows) do
        local info = getItemInfo(r.item_name)
        r.label = info and info.label or r.item_name
    end

    local workers = MySQL.query.await('SELECT * FROM pawnshop_workers WHERE shop_id = ? ORDER BY rep_xp DESC', { shopId }) or {}
    for _, w in ipairs(workers) do
        w.permissions = decode(w.permissions)
    end

    local exportsList = MySQL.query.await('SELECT * FROM pawnshop_exports WHERE shop_id = ? ORDER BY id DESC', { shopId }) or {}
    local vehicles = MySQL.query.await('SELECT * FROM pawnshop_vehicles WHERE shop_id = ? ORDER BY id ASC', { shopId }) or {}
    local loyaltyMembers = MySQL.query.await('SELECT * FROM pawnshop_loyalty WHERE shop_id = ? ORDER BY points DESC', { shopId }) or {}
    local emails = MySQL.query.await('SELECT * FROM pawnshop_emails WHERE shop_id = ? ORDER BY id DESC LIMIT 30', { shopId }) or {}
    local logs = MySQL.query.await('SELECT * FROM pawnshop_logs WHERE shop_id = ? ORDER BY id DESC LIMIT 50', { shopId }) or {}
    if not isOwner then
        local perms=decode(worker.permissions)
        local function allowed(key) return perms.admin or perms[key] end
        if not allowed('view_confidential') then
            local filtered={}
            for _,mail in ipairs(emails) do if mail.is_confidential==0 or mail.is_confidential==false then filtered[#filtered+1]=mail end end
            emails=filtered
        end
        if not allowed('view_emails') then emails={} end
        if not allowed('view_logs') then logs={} end
        if not allowed('manage_loyalty') then loyaltyMembers={} end
        if not allowed('hire_workers') then workers={} end
    end
    local activePawnsCount = MySQL.scalar.await("SELECT COUNT(*) FROM pawnshop_pawns WHERE shop_id = ? AND status = 'active'", { shopId }) or 0

    generateSupplierOffers(shopId)

    local categoryLabels = {}
    for k, v in pairs(Config.Categories) do
        categoryLabels[k] = v.label
    end

    local nearbyPlayers = {}
    local myCoords = GetEntityCoords(GetPlayerPed(src))
    for _, pSrc in ipairs(GetPlayers()) do
        local targetPed = GetPlayerPed(tonumber(pSrc))
        if targetPed ~= 0 and #(GetEntityCoords(targetPed) - myCoords) <= 15.0 then
            local targetPlayer = core:GetPlayer(tonumber(pSrc))
            if targetPlayer then
                nearbyPlayers[#nearbyPlayers + 1] = {
                    source = tonumber(pSrc),
                    citizenid = targetPlayer.PlayerData.citizenid,
                    name = ('%s %s'):format(targetPlayer.PlayerData.charinfo.firstname, targetPlayer.PlayerData.charinfo.lastname)
                }
            end
        end
    end

    return {
        shop = shop,
        categoryLabels = categoryLabels,
        levelInfo = Config.ShopLevels[shop.level] or Config.ShopLevels[1],
        role = isOwner and 'Proprietário' or (worker and worker.role_preset or 'Funcionário'),
        myWorker = worker,
        activePawns = activePawnsCount,
        inventory = invRows,
        workers = workers,
        nearbyPlayers = nearbyPlayers,
        exports = exportsList,
        supplier = SupplierQueues[shopId],
        vehicles = vehicles,
        fleetCatalog = Config.FleetVehicles,
        loyalty = loyaltyMembers,
        emails = emails,
        logs = logs,
        presets = Config.PermissionPresets,
        permissions = isOwner and {admin = true} or decode(worker and worker.permissions),
        payrollPointRate = Config.PayrollPointRate
    }
end
lib.callback.register('mri_Qpawnshop:server:getComputerData', function(src, shopId) return getComputerData(src, shopId) end)
lib.callback.register('mri_Qpawnshop:server:getFleet', function(src, shopId)
    local shop = Shops[number(shopId, 1)]
    if not shop or not nearShop(src, shop, 'garage') or not hasPermission(src, shop.id, 'manage_vehicles') then return {} end
    return MySQL.query.await('SELECT * FROM pawnshop_vehicles WHERE shop_id = ? ORDER BY id', {shop.id}) or {}
end)

registerEvent('mri_Qpawnshop:server:computerAction', function(shopId, action, data)
    local src = source
    local player = core:GetPlayer(src)
    local shop = Shops[shopId]
    if not player or not shop or type(data)~='table' or type(action)~='string' then return end
    if not hasPermission(src,shopId,'access_computer') then return end
    local actorName = ('%s %s'):format(player.PlayerData.charinfo.firstname, player.PlayerData.charinfo.lastname)

    if action == 'toggleControl' then
        if not hasPermission(src, shopId, 'admin') then return end
        local field = data.field
        local allowed = { is_open = true, buying_active = true, special_offers_active = true, collections_active = true, exports_active = true }
        if not allowed[field] then return end
        shop[field] = not shop[field]
        MySQL.update.await(('UPDATE pawnshop_shops SET %s = ? WHERE id = ?'):format(field), { shop[field] and 1 or 0, shopId })
        TriggerClientEvent('mri_Qpawnshop:client:syncShops', -1, Shops)

    elseif action == 'fundsTransaction' then
        if not hasPermission(src, shopId, 'manage_funds') then return end
        local amount=number(data.amount,1,10000000)
        if not amount then return end
        if data.kind == 'deposit' then
            if player.Functions.RemoveMoney('bank', amount, 'pawnshop-deposit') then
                local ok,result=pcall(MySQL.update.await,'UPDATE pawnshop_shops SET funds = funds + ? WHERE id = ?',{amount,shopId})
                if not ok or result~=1 then player.Functions.AddMoney('bank',amount,'pawnshop-deposit-refund');return end
                shop.funds=shop.funds+amount
                logActivity(shopId, 'Financeiro', actorName, 'Depósito no caixa da empresa', amount)
                notify(src, ('Depositado $%s com sucesso!'):format(amount), 'success')
            else
                notify(src, 'Saldo bancário insuficiente.', 'error')
            end
        elseif data.kind == 'withdraw' then
            if shop.funds >= amount then
                if MySQL.update.await('UPDATE pawnshop_shops SET funds = funds - ? WHERE id = ? AND funds >= ?',{amount,shopId,amount})~=1 then return end
                if not player.Functions.AddMoney('bank',amount,'pawnshop-withdraw') then MySQL.update.await('UPDATE pawnshop_shops SET funds = funds + ? WHERE id = ?',{amount,shopId});return end
                shop.funds=shop.funds-amount
                logActivity(shopId, 'Financeiro', actorName, 'Saque do caixa da empresa', -amount)
                notify(src, ('Sacado $%s com sucesso!'):format(amount), 'success')
            else
                notify(src, 'Fundos insuficientes na empresa.', 'error')
            end
        end

    elseif action=='stockIntake' or action=='stockSpecialOffers' then
        local special=action=='stockSpecialOffers'
        if not hasPermission(src,shopId,special and 'manage_special_offers' or 'manage_stashes') then return end
        local stash=('pawnshop_%s_%s'):format(shopId,special and 'special_offers' or 'intake')
        local lines,statements={},{}
        for _,item in pairs(inventory:GetInventoryItems(stash) or {}) do
            local info,category=getItemInfo(item.name)
            if info and item.count>0 and (special or shop.categories[category]) then
                if special then category='special_offers' end
                lines[#lines+1]={name=item.name,count=item.count,metadata=item.metadata,slot=item.slot}
                appendQueries(statements,stockQueries(shopId,category,item.name,item.count,item.metadata,info.baseValue))
            end
        end
        if #lines==0 then notify(src,'Depósito sem mercadorias elegíveis.','error');return end
        if not removeLines(stash,lines) then return end
        if not transaction(statements) then restoreItems(stash,lines);return end
        notify(src,'Mercadorias transferidas para o estoque de vendas.','success')

    elseif action == 'updateItemPrice' then
        if not hasPermission(src, shopId, 'set_prices') then return end
        local itemId = tonumber(data.itemId)
        local newPrice=number(data.price,1,10000000)
        if not newPrice or not number(itemId,1) then return end
        MySQL.update.await('UPDATE pawnshop_inventory SET price = ? WHERE id = ? AND shop_id = ?', { newPrice, itemId, shopId })
        notify(src, ('Preço atualizado para $%s.'):format(newPrice), 'success')

    elseif action == 'hireWorker' then
        if not hasPermission(src, shopId, 'hire_workers') then return end
        local targetCid,targetName=data.citizenid,nil
        if type(targetCid)~='string' then return end
        for _,id in ipairs(GetPlayers()) do
            local target=core:GetPlayer(tonumber(id))
            if target and target.PlayerData.citizenid==targetCid and nearPoint(src,{x=GetEntityCoords(GetPlayerPed(tonumber(id))).x,y=GetEntityCoords(GetPlayerPed(tonumber(id))).y,z=GetEntityCoords(GetPlayerPed(tonumber(id))).z},15.0) then
                targetName=target.PlayerData.charinfo.firstname..' '..target.PlayerData.charinfo.lastname;break
            end
        end
        if not targetName or targetCid==shop.owner_cid then return end
        local staffCount=MySQL.scalar.await('SELECT COUNT(*) FROM pawnshop_workers WHERE shop_id = ?',{shopId}) or 0
        if staffCount>=10 then notify(src,'Limite de dez funcionários atingido.','error');return end
        local defaultPerms = Config.PermissionPresets['Caixa']
        MySQL.insert.await(
            'INSERT IGNORE INTO pawnshop_workers (shop_id, citizenid, name, role_preset, permissions) VALUES (?, ?, ?, ?, ?)',
            { shopId, targetCid, targetName, 'Caixa', json.encode(defaultPerms) }
        )
        logActivity(shopId, 'Equipe', actorName, ('Contratou %s'):format(targetName), 0)
        notify(src, ('%s foi contratado!'):format(targetName), 'success')

    elseif action == 'updateWorkerPermissions' then
        if not hasPermission(src, shopId, 'manage_permissions') then return end
        local preset=Config.PermissionPresets[data.preset]
        if not preset or not number(data.workerId,1) then return end
        MySQL.update.await(
            'UPDATE pawnshop_workers SET role_preset = ?, permissions = ? WHERE id = ? AND shop_id = ?',
            { data.preset or 'Personalizado', json.encode(preset), tonumber(data.workerId), shopId }
        )
        logActivity(shopId, 'Equipe', actorName, 'Atualizou cargo/permissões de funcionário', 0)
        notify(src, 'Cargo e permissões atualizados com sucesso!', 'success')

    elseif action == 'fireWorker' then
        if not hasPermission(src, shopId, 'fire_workers') then return end
        MySQL.query.await('DELETE FROM pawnshop_workers WHERE id = ? AND shop_id = ?', { tonumber(data.workerId), shopId })
        logActivity(shopId, 'Equipe', actorName, 'Demitiu funcionário', 0)
        notify(src, 'Funcionário desligado da empresa.', 'inform')

    elseif action == 'acceptExportOrder' then
        if not hasPermission(src, shopId, 'accept_exports') then return end
        MySQL.update.await(
            "UPDATE pawnshop_exports SET status = 'active', accepted_by = ? WHERE id = ? AND shop_id = ? AND status = 'pending'",
            { actorName, tonumber(data.orderId), shopId }
        )
        notify(src, 'Pedido de exportação aceito! Embale os itens na Estação de Embalagem.', 'success')

    elseif action == 'denyExportOrder' then
        if not hasPermission(src, shopId, 'accept_exports') then return end
        MySQL.update.await("UPDATE pawnshop_exports SET status = 'denied' WHERE id = ? AND shop_id = ?", { tonumber(data.orderId), shopId })

    elseif action == 'startExportDelivery' then
        if not hasPermission(src, shopId, 'start_exports') then return end
        local order = MySQL.single.await("SELECT * FROM pawnshop_exports WHERE id = ? AND shop_id = ? AND status = 'active'", { tonumber(data.orderId), shopId })
        if not order or not shop.exports_active or order.expires_at<=os.time() then return end
        if ExportMissions[src] then notify(src,'Você já possui uma entrega em andamento.','error');return end
        for _,mission in pairs(ExportMissions) do if mission.shopId==shopId and mission.orderId==order.id then return end end
        local dropCoords = Config.ExportDropLocations[math.random(#Config.ExportDropLocations)]
        ExportMissions[src]={shopId=shopId,orderId=order.id,point={x=dropCoords.x,y=dropCoords.y,z=dropCoords.z},expires=os.time()+1800}
        TriggerClientEvent('mri_Qpawnshop:client:startExportMission', src, shopId, order, dropCoords)

    elseif action == 'addSupplierToQueue' then
        if not hasPermission(src, shopId, 'accept_suppliers') then return end
        local sData = SupplierQueues[shopId]
        if not sData then return end
        for idx, offer in ipairs(sData.offers) do
            if offer.id == tonumber(data.offerId) then
                sData.queue[#sData.queue + 1] = offer
                table.remove(sData.offers, idx)
                break
            end
        end

    elseif action == 'startSupplierMission' then
        if not hasPermission(src, shopId, 'accept_suppliers') then return end
        local sData = SupplierQueues[shopId]
        if not sData or #sData.queue==0 or not shop.collections_active then return end
        if SupplierMissions[src] then notify(src,'Conclua sua coleta atual primeiro.','error');return end
        for _,batch in ipairs(sData.queue) do if not inventory:Items(batch.item) or not shop.categories[select(2,getItemInfo(batch.item))] then notify(src,'Mercadoria ou categoria indisponível.','error');return end end
        local totalCost = 0
        for _, q in ipairs(sData.queue) do totalCost = totalCost + q.cost end
        local discount = (Config.ShopLevels[shop.level] and Config.ShopLevels[shop.level].supplierDiscount) or 1.0
        totalCost = math.floor(totalCost * discount)

        if shop.funds < totalCost then
            notify(src, ('Fundos insuficientes ($%s necessários).'):format(totalCost), 'error')
            return
        end

        if not transaction({query('UPDATE pawnshop_shops SET funds = ? WHERE id = ?',{shop.funds-totalCost,shopId}),query("INSERT INTO pawnshop_supplier_missions (shop_id,citizenid,cost,status) VALUES (?,?,?,'active')",{shopId,player.PlayerData.citizenid,totalCost})}) then return end
        local missionId=MySQL.scalar.await("SELECT id FROM pawnshop_supplier_missions WHERE shop_id = ? AND citizenid = ? AND status = 'active' ORDER BY id DESC LIMIT 1",{shopId,player.PlayerData.citizenid})
        shop.funds=shop.funds-totalCost

        local missionQueue = sData.queue
        sData.queue = {}
        local houseCoords = Config.SupplierDropLocations[math.random(#Config.SupplierDropLocations)]
        SupplierMissions[src]={id=missionId,shopId=shopId,items=missionQueue,cost=totalCost,point={x=houseCoords.x,y=houseCoords.y,z=houseCoords.z},expires=os.time()+1800}
        logActivity(shopId, 'Fornecedor', actorName, ('Iniciou coleta de %s lotes'):format(#missionQueue), -totalCost)
        TriggerClientEvent('mri_Qpawnshop:client:startSupplierCollection', src, shopId, missionQueue, houseCoords)

    elseif action == 'buyFleetVehicle' then
        if not hasPermission(src, shopId, 'manage_vehicles') then return end
        local vehCfg = nil
        for _, v in ipairs(Config.FleetVehicles) do
            if v.model == data.model then vehCfg = v; break end
        end
        if not vehCfg or shop.level<vehCfg.minLevel then return end
        local owned=MySQL.scalar.await('SELECT COUNT(*) FROM pawnshop_vehicles WHERE shop_id = ? AND model = ?',{shopId,vehCfg.model}) or 0
        if owned>=vehCfg.maxOwned then notify(src,'Limite deste modelo na frota atingido.','error');return end
        if shop.funds < vehCfg.price then
            notify(src, 'Fundos insuficientes para comprar este veículo.', 'error')
            return
        end
        local plate=('PWN%05d'):format(math.random(10000,99999))
        if not transaction({
            query('UPDATE pawnshop_shops SET funds = ? WHERE id = ?',{shop.funds-vehCfg.price,shopId}),
            query('INSERT INTO pawnshop_vehicles (shop_id,model,label,plate,status,insurance_cost) VALUES (?,?,?,?,?,?)',{shopId,vehCfg.model,vehCfg.label,plate,'available',vehCfg.insurance})
        }) then return end
        shop.funds=shop.funds-vehCfg.price
        logActivity(shopId, 'Frota', actorName, ('Adquiriu %s (%s)'):format(vehCfg.label, plate), -vehCfg.price)
        notify(src, ('%s adicionado à frota da empresa!'):format(vehCfg.label), 'success')

    elseif action == 'claimInsurance' then
        if not hasPermission(src, shopId, 'manage_vehicles') then return end
        local veh = MySQL.single.await('SELECT * FROM pawnshop_vehicles WHERE id = ? AND shop_id = ?', { tonumber(data.vehicleId), shopId })
        if not veh or FleetEntities[veh.id] and DoesEntityExist(FleetEntities[veh.id].entity) or veh.status=='available' or shop.funds<veh.insurance_cost then
            notify(src, 'Fundos insuficientes para acionar o seguro.', 'error')
            return
        end
        if not transaction({query('UPDATE pawnshop_shops SET funds = ? WHERE id = ?',{shop.funds-veh.insurance_cost,shopId}),query("UPDATE pawnshop_vehicles SET status = 'available',fuel = 100,body = 100,engine = 100 WHERE id = ?",{veh.id})}) then return end
        shop.funds=shop.funds-veh.insurance_cost
        logActivity(shopId, 'Frota', actorName, ('Acionou seguro do veículo %s'):format(veh.plate), -veh.insurance_cost)
        notify(src, 'Veículo recuperado pela seguradora!', 'success')

    elseif action == 'claimPayslip' then
        local worker = MySQL.single.await('SELECT * FROM pawnshop_workers WHERE shop_id = ? AND citizenid = ?', { shopId, player.PlayerData.citizenid })
        if not worker or worker.unclaimed_points <= 0 then
            notify(src, 'Você não possui pontos acumulados para gerar holerite.', 'error')
            return
        end
        local gross = math.floor(worker.unclaimed_points * Config.PayrollPointRate)
        if shop.funds < gross then
            notify(src, 'A loja não possui saldo suficiente para pagar seu holerite.', 'error')
            return
        end
        if not number(gross,1) then return end
        if not transaction({query('UPDATE pawnshop_shops SET funds = ? WHERE id = ?',{shop.funds-gross,shopId}),query('UPDATE pawnshop_workers SET unclaimed_points = 0 WHERE id = ?',{worker.id})}) then return end
        shop.funds=shop.funds-gross
        if not player.Functions.AddMoney('bank',gross,'pawnshop-payslip') then
            if transaction({query('UPDATE pawnshop_shops SET funds = funds + ? WHERE id = ?',{gross,shopId}),query('UPDATE pawnshop_workers SET unclaimed_points = ? WHERE id = ?',{worker.unclaimed_points,worker.id})}) then shop.funds=shop.funds+gross end
            return
        end
        logActivity(shopId, 'Financeiro', actorName, 'Pagamento de Holerite (Folha Salarial)', -gross)
        notify(src, ('Holerite recebido: $%s depositados no banco!'):format(gross), 'success')

    elseif action=='acceptEmailAction' then
        if not hasPermission(src,shopId,'admin') then return end
        local mail = MySQL.single.await('SELECT * FROM pawnshop_emails WHERE id = ? AND shop_id = ?', { tonumber(data.emailId), shopId })
        if not mail or mail.action_status ~= 'none' then return end
        MySQL.update.await("UPDATE pawnshop_emails SET action_status = 'accepted' WHERE id = ?", { mail.id })
        if mail.action_type == 'upgrade_ifruit' then
            shop.os_theme = 'ifruit'
            MySQL.update.await("UPDATE pawnshop_shops SET os_theme = 'ifruit' WHERE id = ?", { shopId })
            sendShopEmail(shopId, 'iFruit Tecnologias', 'Seu Computador iFruit OS Pro Foi Instalado!',
                'ÓTIMAS NOTÍCIAS!\n\nNossa equipe técnica concluiu a atualização durante a madrugada. Seu novo sistema operacional iFruit OS Pro já está ativo e pronto para uso.', nil, false)
            TriggerClientEvent('mri_Qpawnshop:client:syncShops', -1, Shops)
            notify(src, 'Sistema iFruit OS Pro instalado com sucesso!', 'success')
        end
    end

    local updated = getComputerData(src, shopId)
    TriggerClientEvent('mri_Qpawnshop:client:refreshComputer', src, updated)
end)

registerEvent('mri_Qpawnshop:server:saveNewShelf', function(shopId, shelfData)
    local src = source
    local shop = Shops[shopId]
    if not shop or not hasPermission(src,shopId,'manage_shelves') then return end
    if not validPoint(shelfData) or not nearPoint(src,shelfData,25.0) or not Config.Categories[shelfData.category] or not shop.categories[shelfData.category] or #shop.shelves>=50 then return end
    shelfData={x=shelfData.x,y=shelfData.y,z=shelfData.z,radius=math.max(0.6,math.min(4.0,tonumber(shelfData.radius) or 1.4)),category=shelfData.category}
    shop.shelves[#shop.shelves+1]=shelfData
    MySQL.update.await('UPDATE pawnshop_shops SET shelves_data = ? WHERE id = ?', { json.encode(shop.shelves), shopId })
    TriggerClientEvent('mri_Qpawnshop:client:syncShops', -1, Shops)
    notify(src, 'Prateleira criada e salva no banco com sucesso!', 'success')
end)

registerEvent('mri_Qpawnshop:server:processPackaging',function(shopId)
    local src=source
    if not inventory:Items('pawn_package') then notify(src,'Item pawn_package não cadastrado.','error');return end
    local stash=('pawnshop_%s_packaging'):format(shopId)
    local packed=0
    for _,item in pairs(inventory:GetInventoryItems(stash) or {}) do
        if item and item.name and item.name~='pawn_package' and item.count>0 then
            local info=getItemInfo(item.name)
            if info then
                for _=1,item.count do
                    local metadata={shopId=shopId,packedItem=item.name,packedMetadata=item.metadata or {},description=('Conteúdo: 1x %s'):format(item.label or item.name)}
                    if not inventory:CanCarryItem(src,'pawn_package',1,metadata) then notify(src,'Inventário sem espaço para mais caixas.','error');break end
                    if not inventory:RemoveItem(stash,item.name,1,item.metadata,item.slot) then break end
                    if not safeAdd(src,'pawn_package',1,metadata) then safeAdd(stash,item.name,1,item.metadata);break end
                    packed=packed+1
                end
            end
        end
    end
    notify(src,packed>0 and ('%s caixas embaladas.'):format(packed) or 'Nenhum item elegível foi embalado.',packed>0 and 'success' or 'inform')
end)

registerEvent('mri_Qpawnshop:server:completeExportOrder',function(shopId,orderId)
    local src,shop=source,Shops[shopId]
    local player=core:GetPlayer(src)
    local mission=ExportMissions[src]
    if not player or not mission or mission.shopId~=shopId or mission.orderId~=orderId or mission.expires<os.time() or not nearPoint(src,mission.point,6.0) then return end
    local order=MySQL.single.await("SELECT * FROM pawnshop_exports WHERE id = ? AND shop_id = ? AND status = 'active' AND expires_at > ?",{orderId,shopId,os.time()})
    if not order then return end
    local lines,remaining={},order.qty
    for _,item in pairs(inventory:Search(src,'slots','pawn_package') or {}) do
        local metadata=item.metadata or {}
        if metadata.shopId==shopId and metadata.packedItem==order.item_name then
            local count=math.min(remaining,item.count)
            if count>0 then lines[#lines+1]={name='pawn_package',count=count,metadata=metadata,slot=item.slot};remaining=remaining-count end
        end
    end
    if remaining>0 then
        for _,item in pairs(inventory:Search(src,'slots',order.item_name) or {}) do
            local count=math.min(remaining,item.count)
            if count>0 then lines[#lines+1]={name=item.name,count=count,metadata=item.metadata,slot=item.slot};remaining=remaining-count end
        end
    end
    if remaining>0 then notify(src,('Faltam %s unidades da mercadoria solicitada.'):format(remaining),'error');return end
    if not removeLines(src,lines) then return end
    local payout=math.floor(order.payout*((Config.ShopLevels[shop.level] or {}).exportBonus or 1.0))
    local funds=shop.funds+payout
    local stats=decode(json.encode(shop.stats))
    stats.completedExports=(stats.completedExports or 0)+1
    stats.netProfit=(stats.netProfit or 0)+payout
    if not transaction({
        query("UPDATE pawnshop_exports SET status = 'completed' WHERE id = ? AND status = 'active'",{orderId}),
        query('UPDATE pawnshop_shops SET funds = ?, stats_data = ? WHERE id = ?',{funds,json.encode(stats),shopId}),
        query('UPDATE pawnshop_workers SET unclaimed_points = unclaimed_points + 2.5, rep_xp = rep_xp + 25 WHERE shop_id = ? AND citizenid = ?',{shopId,player.PlayerData.citizenid})
    }) then restoreItems(src,lines);return end
    shop.funds,shop.stats=funds,stats
    ExportMissions[src]=nil
    addShopXP(shopId,order.xp_reward)
    TriggerClientEvent('mri_Qpawnshop:client:missionComplete',src,'export')
    notify(src,('Exportação concluída! $%s no caixa da loja.'):format(payout),'success')
end)

registerEvent('mri_Qpawnshop:server:completeSupplierCollection',function(shopId)
    local src,shop=source,Shops[shopId]
    local player=core:GetPlayer(src)
    local mission=SupplierMissions[src]
    if not player or not mission or mission.shopId~=shopId or not nearPoint(src,mission.point,6.0) then return end
    local statements={}
    for _,batch in ipairs(mission.items) do
        local info,category=getItemInfo(batch.item)
        if not info or not inventory:Items(batch.item) then return end
        appendQueries(statements,stockQueries(shopId,category,batch.item,batch.qty,{},info.baseValue))
    end
    statements[#statements+1]=query('UPDATE pawnshop_workers SET unclaimed_points = unclaimed_points + 1.5, rep_xp = rep_xp + 15 WHERE shop_id = ? AND citizenid = ?',{shopId,player.PlayerData.citizenid})
    statements[#statements+1]=query("UPDATE pawnshop_supplier_missions SET status = 'completed' WHERE id = ? AND status = 'active'",{mission.id})
    if not transaction(statements) then return end
    SupplierMissions[src]=nil
    addShopXP(shopId,25)
    TriggerClientEvent('mri_Qpawnshop:client:missionComplete',src,'supplier')
    notify(src,'Mercadorias do fornecedor adicionadas ao estoque!','success')
end)

AddEventHandler('playerDropped', function()
    local src=source
    PendingCreators[src],ActiveOfferStashes[src],LastAction[src]=nil,nil,nil
    ExportMissions[src]=nil
    local mission=SupplierMissions[src]
    if mission then
        SupplierMissions[src]=nil
        CreateThread(function()
            while ShopLocks[mission.shopId] do Wait(100) end
            ShopLocks[mission.shopId]=true
            local shop=Shops[mission.shopId]
            local ok,err=pcall(function()
                if shop then
                    if not transaction({query('UPDATE pawnshop_shops SET funds = funds + ? WHERE id = ?',{mission.cost,shop.id}),query("UPDATE pawnshop_supplier_missions SET status = 'refunded' WHERE id = ? AND status = 'active'",{mission.id})}) then return end
                    shop.funds=shop.funds+mission.cost
                    local supplier=SupplierQueues[shop.id]
                    if supplier then for _,batch in ipairs(mission.items) do supplier.queue[#supplier.queue+1]=batch end end
                end
            end)
            ShopLocks[mission.shopId]=nil
            if not ok then print('[mri_Qpawnshop] Falha ao devolver coleta: '..tostring(err)) end
        end)
    end
end)

setupPawnshopAccess({shops=function() return Shops end,locked=function(id) return ShopLocks[id] end,near=nearShop,permission=hasPermission})

registerEvent('mri_Qpawnshop:server:spawnFleet',function(shopId,vehicleId)
    local src,shop=source,Shops[shopId]
    if not number(vehicleId,1) then return end
    local row=MySQL.single.await("SELECT * FROM pawnshop_vehicles WHERE id = ? AND shop_id = ? AND status = 'available'",{vehicleId,shopId})
    if not row then return end
    local point=shop.coords.garage
    for _,entity in ipairs(GetAllVehicles()) do
        if DoesEntityExist(entity) and #(GetEntityCoords(entity)-vec3(point.x,point.y,point.z))<3.0 then notify(src,'Saída da garagem ocupada.','error');return end
    end
    if MySQL.update.await("UPDATE pawnshop_vehicles SET status = 'out' WHERE id = ? AND status = 'available'",{vehicleId})~=1 then return end
    local entity=CreateVehicleServerSetter(joaat(row.model),'automobile',point.x,point.y,point.z,tonumber(point.w) or 0.0)
    if entity==0 then MySQL.update.await("UPDATE pawnshop_vehicles SET status = 'available' WHERE id = ?",{vehicleId});return end
    SetVehicleNumberPlateText(entity,row.plate)
    SetEntityRoutingBucket(entity,GetPlayerRoutingBucket(src))
    FleetEntities[vehicleId]={entity=entity,shopId=shopId,driver=src,plate=row.plate}
    local deadline=GetGameTimer()+5000
    while NetworkGetEntityOwner(entity)==-1 and GetGameTimer()<deadline do Wait(50) end
    if GetResourceState('mri_Qcarkeys')=='started' then exports.mri_Qcarkeys:GiveTempKeys(src,row.plate) end
    TriggerClientEvent('mri_Qpawnshop:client:takeFleet',src,shopId,vehicleId,NetworkGetNetworkIdFromEntity(entity),row)
end)

registerEvent('mri_Qpawnshop:server:returnFleet',function(shopId,vehicleId,condition)
    local src=source
    local fleet=FleetEntities[number(vehicleId,1)]
    if not fleet or fleet.shopId~=shopId or not DoesEntityExist(fleet.entity) then return end
    local entity=fleet.entity
    local ped=GetPlayerPed(src)
    if #(GetEntityCoords(ped)-GetEntityCoords(entity))>8.0 then return end
    local driver=GetPedInVehicleSeat(entity,-1)
    if driver~=0 and driver~=ped then return end
    condition=type(condition)=='table' and condition or {}
    local function percent(value,default)
        local n=tonumber(value)
        if not n or n~=n then return default end
        return math.floor(math.max(0,math.min(100,n)))
    end
    if MySQL.update.await("UPDATE pawnshop_vehicles SET status = 'available', fuel = ?, body = ?, engine = ? WHERE id = ? AND shop_id = ?",{percent(condition.fuel,100),percent(condition.body,100),percent(condition.engine,100),vehicleId,shopId})~=1 then return end
    DeleteEntity(entity)
    FleetEntities[vehicleId]=nil
    if GetResourceState('mri_Qcarkeys')=='started' then exports.mri_Qcarkeys:RemoveTempKeys(fleet.driver,fleet.plate) end
    TriggerClientEvent('mri_Qpawnshop:client:fleetReturned',src)
    notify(src,'Veículo guardado.','success')
end)

AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    for _,fleet in pairs(FleetEntities) do if DoesEntityExist(fleet.entity) then DeleteEntity(fleet.entity) end end
end)
