Config = {}
Config.ForSaleSignModel = 'prop_forsale_lrg_01'

Config.AdminGroup = 'group.admin'
Config.CreateCommand = 'createpawnshop'
Config.SellRateBase = 0.80           -- Cliente recebe 80% do valor de mercado na venda imediata
Config.PawnRateBase = 0.60           -- Cliente recebe 60% do valor de mercado ao penhorar
Config.PawnBuybackMultiplier = 1.10  -- Cliente paga 110% do valor de mercado para resgatar o item
Config.PawnDurationHours = 72        -- 72 horas para resgatar antes de ir para o estoque da loja
Config.MaxActivePawnsPerPlayer = 10
Config.PayrollPointRate = 50         -- $50 por ponto de atividade acumulado na folha de pagamento

Config.PedScenarios = {
    { label = 'Aguardando Impaciente', value = 'WORLD_HUMAN_STAND_IMPATIENT' },
    { label = 'Segurança Posturado',   value = 'WORLD_HUMAN_GUARD_STAND' },
    { label = 'Fumando',               value = 'WORLD_HUMAN_SMOKING' },
    { label = 'Anotando na Prancheta', value = 'WORLD_HUMAN_CLIPBOARD' },
    { label = 'Vassoura / Limpeza',    value = 'WORLD_HUMAN_JANITOR' },
    { label = 'Flexionando Músculos',  value = 'WORLD_HUMAN_MUSCLE_FLEX' }
}

Config.ShopLevels = {
    [1] = { name = 'Iniciante',    xpRequired = 0,    exportBonus = 1.00, supplierDiscount = 1.00, taxRelief = 0.05, unlockOS = false },
    [2] = { name = 'Estabelecida', xpRequired = 250,  exportBonus = 1.10, supplierDiscount = 0.95, taxRelief = 0.10, unlockOS = false },
    [3] = { name = 'Profissional', xpRequired = 600,  exportBonus = 1.20, supplierDiscount = 0.90, taxRelief = 0.15, unlockOS = true  },
    [4] = { name = 'Premium',      xpRequired = 1200, exportBonus = 1.35, supplierDiscount = 0.85, taxRelief = 0.25, unlockOS = true  },
    [5] = { name = 'Império',      xpRequired = 2500, exportBonus = 1.50, supplierDiscount = 0.75, taxRelief = 0.35, unlockOS = true  }
}

Config.Categories = {
    ['special_offers'] = {
        label = 'Ofertas Especiais',
        icon = 'fa-star',
        items = {}
    },
    ['household_items'] = {
        label = 'Utensílios & Eletrônicos',
        icon = 'fa-house',
        items = {
            ['lockpick']   = { label = 'Gazua (Lockpick)', baseValue = 200 },
            ['phone']      = { label = 'Celular',          baseValue = 50  },
            ['radio']      = { label = 'Rádio Comunicador',baseValue = 150 },
            ['laptop']     = { label = 'Notebook',         baseValue = 800 }
        }
    },
    ['general_goods'] = {
        label = 'Mercadorias Gerais',
        icon = 'fa-box-open',
        items = {
            ['steel']      = { label = 'Aço Compactado',   baseValue = 50  },
            ['copper']     = { label = 'Cobre',            baseValue = 45  },
            ['aluminum']   = { label = 'Alumínio',         baseValue = 50  },
            ['iron']       = { label = 'Ferro Fundido',    baseValue = 55  },
            ['plastic']    = { label = 'Plástico Refinado',baseValue = 40  }
        }
    },
    ['jewellery'] = {
        label = 'Joalheria & Relógios',
        icon = 'fa-ring',
        items = {
            ['rolex']        = { label = 'Relógio Rolex',     baseValue = 650 },
            ['goldchain']    = { label = 'Corrente de Ouro',  baseValue = 350 },
            ['diamond_ring'] = { label = 'Anel de Diamante',  baseValue = 950 }
        }
    },
    ['precious_metals'] = {
        label = 'Metais Preciosos',
        icon = 'fa-coins',
        items = {
            ['goldbar']    = { label = 'Barra de Ouro',    baseValue = 2500 },
            ['silverbar']  = { label = 'Barra de Prata',   baseValue = 1100 }
        }
    },
    ['gems'] = {
        label = 'Pedras Preciosas',
        icon = 'fa-gem',
        items = {
            ['diamond']    = { label = 'Diamante Puro',    baseValue = 1500 },
            ['emerald']    = { label = 'Esmeralda',        baseValue = 1200 },
            ['ruby']       = { label = 'Rubi',             baseValue = 1350 }
        }
    },
    ['coins'] = {
        label = 'Moedas Raras',
        icon = 'fa-circle-dollar-to-slot',
        items = {
            ['old_coin']   = { label = 'Moeda Antiga',     baseValue = 450 }
        }
    },
    ['rusty_items'] = {
        label = 'Sucata & Ferrugem',
        icon = 'fa-screwdriver-wrench',
        items = {
            ['scrapmetal'] = { label = 'Sucata de Metal',  baseValue = 35 }
        }
    },
    ['stolen_goods'] = {
        label = 'Mercadoria Ilegal',
        icon = 'fa-mask',
        items = {
            ['markedbills'] = { label = 'Dinheiro Marcado', baseValue = 1000 }
        }
    }
}

Config.FleetVehicles = {
    { model = 'rumpo',     label = 'Van Rumpo',         minLevel = 1, price = 0,     insurance = 500,  slots = 25, maxOwned = 2 },
    { model = 'speedo',    label = 'Van Speedo',        minLevel = 2, price = 15000, insurance = 1000, slots = 35, maxOwned = 3 },
    { model = 'burrito3',  label = 'Van Burrito',       minLevel = 3, price = 25000, insurance = 1250, slots = 45, maxOwned = 3 },
    { model = 'boxville4', label = 'Caminhão Boxville', minLevel = 4, price = 50000, insurance = 1500, slots = 60, maxOwned = 3 }
}

Config.LoyaltyTiers = {
    ['Basico']  = { price = 0,    sellBonus = 0.02, pawnBonus = 0.00, label = 'Plano Básico (GRÁTIS)' },
    ['Premium'] = { price = 500,  sellBonus = 0.05, pawnBonus = 0.05, label = 'Plano Premium ($500/semana)' },
    ['VIP']     = { price = 2000, sellBonus = 0.15, pawnBonus = 0.10, label = 'Plano VIP ($2000/semana)' }
}

Config.PermissionPresets = {
    ['Gerente'] = {
        admin = true, hire_workers = true, fire_workers = true, manage_permissions = true,
        manage_funds = true, set_prices = true, manage_shelves = true, manage_categories = true,
        manage_stashes = true, manage_packaging = true, manage_special_offers = true,
        accept_exports = true, start_exports = true, accept_suppliers = true,
        manage_vehicles = true, manage_loyalty = true, view_logs = true, view_emails = true,
        send_emails = true, view_confidential = true, view_payroll = true
    },
    ['Estoquista'] = {
        set_prices = true, manage_shelves = true, manage_categories = true,
        manage_stashes = true, manage_packaging = true, manage_special_offers = true
    },
    ['Motorista'] = {
        accept_exports = true, start_exports = true, accept_suppliers = true, manage_vehicles = true
    },
    ['Caixa'] = {
        manage_loyalty = true, view_emails = true
    }
}

Config.SupplierDropLocations = {
    vec4(-14.66, -1441.92, 31.10, 180.0),
    vec4(314.82, -205.11, 54.09, 158.0),
    vec4(-1151.18, -1519.86, 4.36, 125.0),
    vec4(1273.91, -1711.66, 54.77, 294.0)
}

Config.ExportDropLocations = {
    vec4(1201.20, -3254.80, 5.50, 90.0),
    vec4(849.45, -2999.12, 5.90, 270.0),
    vec4(-424.15, -2789.81, 6.00, 315.0)
}
