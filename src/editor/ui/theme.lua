-- HD2Runtime Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- The editor's look: the icon's yellow on near-black, the game's FS Sinclair, compact rows. Sizes are 1080p pixels
-- (the canvas scales them to the screen).
local T={}

T.colour={
    panel={11,14,18,240},panel_alt={15,19,24,244},header={7,9,12,250},footer={7,9,12,250},
    rail={255,199,44,255},line={255,255,255,14},line_strong={255,255,255,30},
    text={234,234,228,255},dim={160,164,170,255},faint={104,110,118,255},inverse={14,16,20,255},
    gold={255,199,44,255},gold_dim={150,113,10,255},gold_wash={255,199,44,22},gold_soft={255,199,44,44},
    select={255,199,44,30},hover={255,255,255,10},focus_line={255,199,44,255},
    mod={104,196,255,255},mod_soft={104,196,255,40},
    pending={255,152,56,255},pending_soft={255,152,56,44},
    error={255,96,84,255},error_soft={255,96,84,44},
    ok={128,214,148,255},ok_soft={128,214,148,40},
    box={5,7,9,255},box_edge={255,255,255,46},box_focus={255,199,44,255},
    shadow={0,0,0,110},scrim={0,0,0,150},
}
-- Stratagem category tones (the game's own: offensive red, defensive green, support blue).
T.tone={offensive={226,94,74,255},defensive={122,188,94,255},support={74,172,232,255}}
T.tone_soft={offensive={226,94,74,40},defensive={122,188,94,40},support={74,172,232,40}}
T.size={title=22,tab=15,heading=13,body=16,label=15,small=13,tiny=12}
T.font={title='title',body='body'}

-- The panel: left of centre, clear of the native squad bars at the bottom.
T.panel={x=34,y=64,w=1260,h=930}
T.header_h=58
T.footer_h=56
T.status_h=40
T.row_h=30
T.section_h=30
T.list_row_h=34
T.pad=14

-- Text whose cap height sits centred on y (FS Sinclair: ascent 49.25, cap 34.75 of a 56 em).
T.CAP_OFFSET=(49.25-34.75/2)/56

return T
