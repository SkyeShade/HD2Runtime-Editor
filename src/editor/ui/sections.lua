-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- An object page's categories: the catalogue's sections (editor/catalog.lua: "Projectile · Flak", "Damage · Direct
-- hit · Status", "Explosion · Primary impact" ...) sorted into a few top-level categories, each with its parts as
-- subsections. Presentation only: rows, their sections, keys and preset keys stay as they are.
--
-- A section label is "<head> · <rest> [· Status]". The head names what it edits (the catalogue's domain labels), the
-- rest which round, feed or explosion phase. Categories:
--   Projectile       the round: its type swap first (Projectile · Swap), its flight (Projectile), its impact and
--                    expiry explosions with their payload slot and stats ("Impact explosion", "Expiry explosion"),
--                    missiles; one set per feed when the weapon has several (Flak, HE, Cluster Bomb ...)
--   Damage           direct hit damage, AP, demolition, stagger, push, then its status slots; per feed
--   Handling / Fire  handling, the weapon's own stats, fire modes, targeting, turret
--   Ammunition       ammunition and magazines, backpack ammunition
--   Heat / Charge    heat, charge, wind-up, recharge
--   Beam / Arc       beam and arc stats and the beam swap
--   Armory           what the armory shows
--   Hellpod / Call-in  the stratagem: call-in, hellpod, rearm (last on a weapon's page, first on any other)
-- Rows HD2Runtime may add later land in their place by their section: a per-weapon projectile swap ("Projectile ·
-- Swap") is the first subsection of Projectile ("Projectile type"), and an impact or expiry payload slot (a
-- terminal.explosion row in "Explosion · Impact" / "Explosion · Expiry") opens its explosion's subsection.
-- A head no category takes (Health & Armor, Shield, Drone, Tuning ...) is a category of its own. A stratagem's attack
-- ("Attack · Delivery 1 projectile damage · Damage"), a sentry's mounted weapon and a minefield's mine end with the
-- domain, which decides their category. Groups (object parts: magazines, vehicle weapons, damage zones) keep their own
-- headers; their sections are ordered the same way.
local M={}

local SEP=' · '
local function split(label)
    local parts={}
    for part in(tostring(label)..SEP):gmatch('(.-) · ')do parts[#parts+1]=part end
    return parts
end
local function join(parts,first,last)
    local out={}
    for i=first or 1,last or#parts do out[#out+1]=parts[i]end
    return table.concat(out,SEP)
end

-- the subsection titles the layout gives (shown through L(), part by part)
local SUB_TITLES={flight='Flight',swap='Projectile type',impact='Impact explosion',expiry='Expiry explosion',
    explosion='Explosion',direct='Direct hit',damage='Damage'}
M.SUB_TITLES=SUB_TITLES
M.TITLES={projectile='Projectile',damage='Damage',fire='Handling / Fire',ammo='Ammunition',heat='Heat / Charge',
    beam='Beam / Arc',armory='Armory',call_in='Hellpod / Call-in'}
-- The category of a section's head (or, for an attack, mount or mine, of its last part).
local HEAD={Projectile='projectile',Explosion='projectile',Missile='projectile',['Function Missile']='projectile',
    Shrapnel='projectile',Bomblets='projectile',['Bomblet explosion']='projectile',
    Damage='damage',['Status Damage']='damage',
    Handling='fire',Weapon='fire',['Fire Mode']='fire',Targeting='fire',Turret='fire',['Mounted Weapon']='fire',
    ['Ammo & Magazine']='ammo',Ammo='ammo',Backpack='ammo',Functions='ammo',['Drone Magazines']='ammo',Magazine='ammo',
    Heat='heat',Charge='heat',['Wind-up']='heat',Recharge='heat',
    Beam='beam',Arc='beam',
    Armory='armory',
    ['Call-in']='call_in',Hellpod='call_in',['Eagle Rearm']='call_in',['Granted Stratagem']='call_in'}
-- heads whose last part names the domain ("Attack · Beam damage · Damage", "Mine · Mine · Explosion")
local NESTED={Attack=true,['Mounted Weapon']=true,Mine=true}
-- the order of the categories on a weapon's page; any other category comes before Armory, in page order
local ORDER={'projectile','damage','fire','ammo','heat','beam'}
local TAIL={'armory','call_in'}
-- pages of a weapon: the stratagem side (call-in, hellpod) last; on every other page it comes first
local WEAPON_PAGES={primary=true,secondary=true,support_weapons=true,throwables=true}
-- explosion phases (a single word after "Explosion", alone or after a feed)
local PHASES={impact=true,expiry=true,detonation=true,ability=true,shrapnel=true}
-- the main round's own feed names
local MAIN={['']=true,primary=true}

local function phase_title(phase)
    local p=phase:lower()
    if p=='impact'or p=='expiry'then return SUB_TITLES[p]end
    return phase
end
-- One section: category id, title of its subsection (without the feed), feed name ('' = the main round), rank of
-- the subsection within its feed, and whether it is a status subsection.
function M.classify(label)
    local parts=split(label)
    local status=false
    if#parts>1 and parts[#parts]=='Status'then status=true;table.remove(parts)end
    local head=parts[1]or''
    -- an attack, a mount or a mine: its last part decides, the parts between name it
    if NESTED[head]and#parts>=2 then
        local last=parts[#parts]
        local cat=HEAD[last]
        if cat then
            local title=#parts>2 and join(parts,1,#parts-1)or(head..SEP..last)
            return cat,title,'',cat=='projectile'and(last=='Explosion'and 3 or 1)or 1,status
        end
        if head=='Mounted Weapon'then return 'fire',join(parts),'',1,status end
    end
    local cat=HEAD[head]
    local rest={}
    for i=2,#parts do rest[#rest+1]=parts[i]end
    if head=='Projectile'then
        local swap=rest[#rest]=='Swap'
        if swap then table.remove(rest)end
        local feed=join(rest)
        if MAIN[feed:lower()]then feed=''end
        return 'projectile',swap and SUB_TITLES.swap or SUB_TITLES.flight,feed,swap and 0 or 1,status
    elseif head=='Explosion'then
        if#rest==0 then return 'projectile',SUB_TITLES.explosion,'',2,status end
        local last=rest[#rest]
        local feed,phase
        if PHASES[last:lower()]then
            phase=last
            feed=join(rest,1,#rest-1)
        else
            -- "Primary impact", "Full charge impact": a feed and its phase in one part
            local f,p=last:match('^(.-)%s+(%a+)$')
            if f and PHASES[p:lower()]then
                phase=p
                rest[#rest]=f
                feed=join(rest)
            else
                feed=''
                phase=nil
            end
        end
        if MAIN[(feed or''):lower()]then feed=''end
        if phase then return 'projectile',phase_title(phase),feed,phase:lower()=='impact'and 2 or 3,status end
        -- a feed's own burst ("Explosion · Flak": the layout knows the feeds) or a named explosion ("Overcharge
        -- explosion", "Bomblets")
        return 'projectile',last,'',4,status,join(rest)
    elseif head=='Damage'then
        if#rest==0 then return 'damage',SUB_TITLES.damage,'',0,status end
        local text=join(rest)
        local a,b=text:lower():find('direct hit',1,true)
        if a then
            local feed=text:sub(1,a-1):gsub('%s+$','')
            if MAIN[feed:lower()]then feed=''end
            return 'damage',SUB_TITLES.direct..text:sub(b+1),feed,0,status
        end
        return 'damage',text,'',1,status
    elseif head=='Missile'or head=='Function Missile'then
        return 'projectile',join(parts),'',1.5,status
    end
    if cat then
        local title=#rest>0 and join(parts)or head
        return cat,title,'',1,status
    end
    return nil,#rest>0 and join(rest)or head,'',1,status
end

-- The page layout of an object's ungrouped sections: {{id, title, key, rows, subs = {{title, key, rows}}}}, in page
-- order. object_category: the catalogue category of the page (a weapon's page puts the stratagem side last).
function M.layout(sections,object_category)
    local cats,by_id,feeds_seen={},{},{}
    local first_seen=0
    -- the feeds the page's projectiles name ("Projectile · Flak"): an explosion named after one is that feed's
    local feeds={}
    for _,section in ipairs(sections)do
        local cat,title,feed=M.classify(section.label)
        if cat=='projectile'and feed~=''and(title==SUB_TITLES.flight or title==SUB_TITLES.swap)then feeds[feed]=true end
    end
    for _,section in ipairs(sections)do
        local cat,title,feed,rank,status,named=M.classify(section.label)
        if named and feeds[named]then feed,title,rank=named,SUB_TITLES.explosion,2 end
        local head=split(section.label)[1]
        local id=cat or('h:'..tostring(head))
        local c=by_id[id]
        if not c then
            first_seen=first_seen+1
            c={id=id,title=cat and M.TITLES[cat]or head,key='c|'..id,subs={},by_sub={},rows={},seen=first_seen,
                classified=cat~=nil}
            by_id[id]=c
            cats[#cats+1]=c
        end
        if not cat then title=section.label end
        -- a feed's subsections after the main round's, in the order the feeds appear
        local fkey=id..'\0'..feed
        if not feeds_seen[fkey]then feeds_seen[fkey]=(feed==''and 0 or(#c.subs+1))end
        local full=(feed~=''and(feed..SEP)or'')..title..(status and(SEP..'Status')or'')
        local sub=c.by_sub[full]
        if not sub then
            sub={title=full,key=c.key..'|'..full,rows={},feed_rank=feeds_seen[fkey],rank=rank+(status and 0.5 or 0),
                n=#c.subs+1}
            c.by_sub[full]=sub
            c.subs[#c.subs+1]=sub
        end
        for _,row in ipairs(section.rows)do sub.rows[#sub.rows+1]=row end
    end
    local weapon=WEAPON_PAGES[object_category]
    local rank={}
    for i,id in ipairs(ORDER)do rank[id]=i end
    for _,c in ipairs(cats)do
        if c.id=='call_in'then c.order=weapon and 3000 or 0
        elseif c.id=='armory'then c.order=2000
        else c.order=rank[c.id]or(100+c.seen)end
        table.sort(c.subs,function(a,b)
            if a.feed_rank~=b.feed_rank then return a.feed_rank<b.feed_rank end
            if a.rank~=b.rank then return a.rank<b.rank end
            return a.n<b.n
        end)
        for _,s in ipairs(c.subs)do
            -- (an explosion's payload slot before its stats: where a player picks what goes off)
            local refs,rest={},{}
            for _,r in ipairs(s.rows)do
                if r.field=='terminal.explosion'then refs[#refs+1]=r else rest[#rest+1]=r end
            end
            if#refs>0 then
                for _,r in ipairs(rest)do refs[#refs+1]=r end
                s.rows=refs
            end
            for _,r in ipairs(s.rows)do c.rows[#c.rows+1]=r end
        end
        -- (a grenade's or a stratagem's blast without a round of its own: "Explosion")
        if c.id=='projectile'then
            local round=false
            for _,s in ipairs(c.subs)do if s.rank<2 then round=true end end
            if not round then c.title=SUB_TITLES.explosion end
        end
        c.by_sub=nil
    end
    table.sort(cats,function(a,b)
        if a.order~=b.order then return a.order<b.order end
        return a.seen<b.seen
    end)
    return cats
end

-- A group's sections ordered by the category and subsection their labels fall in (stable otherwise).
function M.order_group(sections)
    local keyed={}
    local rank={}
    for i,id in ipairs(ORDER)do rank[id]=i end
    rank.armory,rank.call_in=50,60
    for i,section in ipairs(sections)do
        local cat,_,feed,r,status=M.classify(section.label)
        keyed[i]={section=section,c=cat and rank[cat]or 40,f=feed~=''and 1 or 0,r=(r or 1)+(status and 0.5 or 0),i=i}
    end
    table.sort(keyed,function(a,b)
        if a.c~=b.c then return a.c<b.c end
        if a.f~=b.f then return a.f<b.f end
        if a.r~=b.r then return a.r<b.r end
        return a.i<b.i
    end)
    local out={}
    for i,k in ipairs(keyed)do out[i]=k.section end
    return out
end
-- Every title the layout can show for a section label (the localisation template).
function M.titles(label)
    local cat,title,feed,_,status=M.classify(label)
    local out={}
    if cat then out[#out+1]=M.TITLES[cat]end
    out[#out+1]=(feed~=''and(feed..SEP)or'')..title..(status and(SEP..'Status')or'')
    return out
end
return M
