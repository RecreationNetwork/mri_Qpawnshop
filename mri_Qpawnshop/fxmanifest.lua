fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mri_Qpawnshop'
author 'Matheus'
description 'Sistema Completo de Pawnshop para Qbox'
version '3.0.2'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/access.lua',
    'server/main.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/index.css',
    'web/index.js'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_inventory',
    'mri_Qinteract',
    'oxmysql'
}
