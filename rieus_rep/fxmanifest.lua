fx_version 'cerulean'
lua54 'yes'
game 'gta5'

name 'rieus_rep'
author 'Rieus'
description 'Gang Reputation NPC Dealer - Integrates with brutal_gangs'
version '2.0.0'

shared_scripts {
    'Config/config.lua'
}

client_scripts {
    'Client/client.lua',
    'Client/client_npc.lua'
}

ui_page 'UI/html/index.html'

files {
    'UI/html/index.html',
    'UI/style/main.css',
    'UI/scripts/ui.js'
}

server_scripts {
    'Server/server.lua'
}

exports {
    'getItemConfig',
    'getReputationItems'
}

escrow_ignore {
    'Config/config.lua',
    'Server/server.lua',
    'Client/client.lua',
    'Client/client_npc.lua',
    'UI/html/index.html',
    'UI/style/main.css',
    'UI/scripts/ui.js',
    'fxmanifest.lua'
}

dependencies {
    'brutal_gangs'
}


