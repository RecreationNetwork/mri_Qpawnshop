-- Loaded through setupPawnshopAccess after the main resource initializes its helpers.
function setupPawnshopAccess(api)
    local inventory = exports.ox_inventory
    local function permitted(src, identifier, moving)
        if type(identifier) ~= 'string' then return true end
        local offerShop, owner = identifier:match('^pawn_offer_(%d+)_(.+)$')
        if offerShop then
            local player = exports.qbx_core:GetPlayer(src)
            local shop = api.shops()[tonumber(offerShop)]
            if not player or not shop or owner ~= player.PlayerData.citizenid then return false end
            if moving and api.locked(shop.id) then return false end
            return api.near(src, shop, 'ped')
        end
        local id, kind = identifier:match('^pawnshop_(%d+)_(.+)$')
        if not id then return true end
        local shop = api.shops()[tonumber(id)]
        if not shop or moving and api.locked(shop.id) then return false end
        local permission = kind == 'packaging' and 'manage_packaging' or kind == 'special_offers' and 'manage_special_offers'
            or kind:match('^shelf_') and 'manage_shelves' or 'manage_stashes'
        return api.near(src, shop, kind == 'packaging' and 'packaging' or nil) and api.permission(src, shop.id, permission)
    end
    inventory:registerHook('openInventory', function(payload)
        return permitted(payload.source, payload.inventoryId, false)
    end, {inventoryFilter = {'^pawnshop_', '^pawn_offer_'}})
    inventory:registerHook('swapItems', function(payload)
        return permitted(payload.source, tostring(payload.fromInventory), true)
            and permitted(payload.source, tostring(payload.toInventory), true)
    end, {inventoryFilter = {'^pawnshop_', '^pawn_offer_'}})
end
