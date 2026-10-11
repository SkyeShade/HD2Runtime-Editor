-- HD2R Editor (c) 2026 SkyeShade. All rights reserved except as granted in LICENSE
-- (https://github.com/SkyeShade/HD2Runtime-Editor). Do not redistribute or reuse without the credit it requires.
-- An object page's categories: the catalogue's sections (editor/catalog.lua: "Projectile · Flak", "Damage · Direct
-- hit · Status", "Explosion · Primary impact" ...) sorted into a few top-level categories, each with its parts as
-- subsections. Presentation only: rows, their sections, keys and preset keys stay as they are.
--
-- A section label is "<head> · <rest> [· Status]". The head names what it edits (the catalogue's domain labels), the
-- rest which round, feed or explosion phase. Categories:
--   Projectile       everything a round carries, round by round: its type swap first (Projectile · Swap, "Projectile
--                    type"), its flight (Projectile), its direct hit (damage, AP, demolition, stagger, push) and the
--                    direct hit's status slots, missiles, its impact and expiry explosions (payload slot first, then
--                    the explosion's stats and status); one set per feed when the weapon has several (Flak, HE ...)
--   Damage           damage no round carries: a beam's, an arc's, a spray's or a melee hit's, then its status slots
--   Handling / Fire  handling, the weapon's own stats, fire modes, targeting, turret
--   Ammunition       ammunition and magazines, backpack ammunition
--   Heat / Charge    heat, charge, wind-up, recharge
--   Beam / Arc       the beam swap first, then beam and arc stats
--   Armory           what the armory shows
--   Hellpod / Call-in  the stratagem: call-in, hellpod, rearm (last on a weapon's page, first on any other)
-- Rows HD2Runtime may add later land in their place by their section: a per-weapon projectile swap ("Projectile ·
-- Swap") is the first part of its round, and an impact or expiry payload slot (a terminal.explosion row in
-- "Explosion · Impact" / "Explosion · Expiry") opens its explosion's subsection.
-- A head no category takes (Health & Armor, Shield, Drone, Tuning ...) is a category of its own. A stratagem's attack
-- ("Attack · Delivery 1 projectile damage · Damage"), a sentry's mounted weapon and a minefield's mine end with the
-- domain, which decides their category: their damage is a direct hit when a round of that name is on the page
-- ("Attack · Delivery 1 projectile · Projectile"), their parts follow their round, and a status section of theirs goes
-- with the section of the same name. Groups (object parts: magazines, vehicle weapons, damage zones) keep their own
-- headers; their sections are ordered the same way.
--
-- No header for a single field: a subsection with one row shows that row in its category (fold), with its feed, and its
-- title when the row's label does not already say it, before the label ("Flak · Projectile"); a category with one row
-- is that row alone (plain). The window draws them so (ui/app.lua field_items); a part that grows (a payload slot's
-- explosion settings) gets its header back, open or closed as it was left.
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
-- the order of a round's parts (a status section right after its own part)
local RANK={swap=0,flight=1,direct=2,missile=3,impact=4,expiry=5,other=6}
M.RANK=RANK
-- the order of the categories on a weapon's page; any other category comes before Armory, in page order
local ORDER={'projectile','damage','fire','ammo','heat','beam'}
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
local function phase_rank(phase)
    return phase:lower()=='impact'and RANK.impact or RANK.expiry
end
-- an attack's or a mount's explosion: the phase its name ends with ("... projectile expiry shrapnel impact damage")
local function nested_phase(title)
    local t=title:lower()
    local impact,expiry=0,0
    for i in t:gmatch('()impact')do impact=i end
    for i in t:gmatch('()expiry')do expiry=i end
    return expiry>impact and RANK.expiry or RANK.impact
end
-- One section: category id, title of its subsection (without the feed), feed name ('' = the main round), rank of
-- the subsection within its round, whether it is a status subsection, and the explosion's name for a named one.
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
            local rank=1
            if last=='Projectile'then rank=RANK.flight
            elseif last=='Explosion'then rank=nested_phase(title)
            elseif last=='Damage'then rank=RANK.direct end
            return cat,title,'',rank,status
        end
        -- (a status section of one of its parts: the layout puts it with the section of the same name)
        if status then return nil,join(parts),'',1,status end
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
        return 'projectile',swap and SUB_TITLES.swap or SUB_TITLES.flight,feed,swap and RANK.swap or RANK.flight,status
    elseif head=='Explosion'then
        if#rest==0 then return 'projectile',SUB_TITLES.explosion,'',RANK.impact,status end
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
        if phase then return 'projectile',phase_title(phase),feed,phase_rank(phase),status end
        -- a feed's own burst ("Explosion · Flak": the layout knows the feeds) or a named explosion ("Overcharge
        -- explosion", "Bomblets")
        return 'projectile',last,'',RANK.other,status,join(rest)
    elseif head=='Damage'then
        -- (a round's direct hit is the round's: Projectile; damage of its own, a beam's or a spray's, is Damage)
        if#rest==0 then return 'damage',SUB_TITLES.damage,'',0,status end
        local text=join(rest)
        local a,b=text:lower():find('direct hit',1,true)
        if a then
            local feed=text:sub(1,a-1):gsub('%s+$','')
            if MAIN[feed:lower()]then feed=''end
            return 'projectile',SUB_TITLES.direct..text:sub(b+1),feed,RANK.direct,status
        end
        return 'damage',text,'',1,status
    elseif head=='Missile'or head=='Function Missile'then
        return 'projectile',join(parts),'',RANK.missile,status
    end
    if cat then
        local title=#rest>0 and join(parts)or head
        -- (a swap first: the beam swap before the beam's stats)
        return cat,title,'',rest[#rest]=='Swap'and RANK.swap or 1,status
    end
    return nil,#rest>0 and join(rest)or head,'',1,status
end

-- Every section classified for one page or group, with what only the whole page tells: an explosion named after a
-- feed is that feed's; an attack's or a mount's damage is its round's direct hit when the round is on the page, and
-- its parts go with that round (carrier); a plain "Damage" beside a round of the page and no direct hit of its own is
-- that round's direct hit (a vehicle weapon's); a status section of an attack goes with the section of its name.
local function classify_all(sections)
    local entries,feeds,rounds,round_list={},{},{},{}
    local main_round,main_direct=false,false
    for i,section in ipairs(sections)do
        local cat,title,feed,rank,status,named=M.classify(section.label)
        local head=split(section.label)[1]
        local e={section=section,cat=cat,title=title,feed=feed,rank=rank,status=status,named=named,head=head}
        entries[i]=e
        if cat=='projectile'and feed~=''and(title==SUB_TITLES.flight or title==SUB_TITLES.swap)then feeds[feed]=true end
        if cat=='projectile'and NESTED[head]and rank==RANK.flight and not rounds[title]then
            rounds[title]=true
            round_list[#round_list+1]=title
        end
        if cat=='projectile'and feed==''and title==SUB_TITLES.flight then main_round=true end
        if cat=='projectile'and feed==''and title==SUB_TITLES.direct then main_direct=true end
    end
    local by_title={}
    for _,e in ipairs(entries)do
        if e.named and feeds[e.named]then e.feed,e.title,e.rank=e.named,SUB_TITLES.explosion,RANK.impact end
        if e.cat=='damage'and NESTED[e.head]and e.title:sub(-7)==' damage'and rounds[e.title:sub(1,-8)]then
            e.cat,e.rank='projectile',RANK.direct
        elseif e.cat=='damage'and e.head=='Damage'and e.title==SUB_TITLES.damage and main_round and not main_direct then
            e.cat,e.title,e.rank='projectile',SUB_TITLES.direct,RANK.direct
        end
        -- (the round an attack's or a mount's part belongs to: the longest round name it starts with)
        if e.cat=='projectile'and NESTED[e.head]then
            for _,r in ipairs(round_list)do
                if(e.title==r or e.title:sub(1,#r+1)==r..' ')and#r>#(e.carrier or'')then e.carrier=r end
            end
        end
        if e.cat and not e.status and NESTED[e.head]then by_title[e.title]=e end
    end
    for _,e in ipairs(entries)do
        if not e.cat and e.status and NESTED[e.head]then
            local owner=by_title[e.title]
            if owner then e.cat,e.rank,e.carrier=owner.cat,owner.rank,owner.carrier
            elseif e.head=='Mounted Weapon'then e.cat='fire'end
        end
    end
    return entries,round_list
end

-- What goes before a row's label when the header above it is folded away ("Flak · Projectile type" with the single row
-- "Projectile" -> "Flak"): the feed, then the title unless the label already starts with the title's first word; nil
-- when nothing is needed.
function M.fold_prefix(title,label,feed)
    local parts={}
    if feed and feed~=''then parts[1]=feed end
    title=tostring(title or'')
    if feed and feed~=''and title:sub(1,#feed+#SEP)==feed..SEP then title=title:sub(#feed+#SEP+1)end
    local word=(title:match('^(%S+)')or''):lower()
    if word~=''and tostring(label or''):lower():sub(1,#word)~=word then parts[#parts+1]=title end
    return#parts>0 and join(parts)or nil
end

-- The page layout of an object's ungrouped sections: {{id, title, key, rows, subs = {{title, key, rows, fold, prefix}},
-- flat, plain, prefix}}, in page order. object_category: the catalogue category of the page (a weapon's page puts the
-- stratagem side last).
--   c.flat   the category shows its one part's rows directly (no subsection header)
--   c.plain  the category is a single row: no header at all, the row alone (c.prefix before its label)
--   s.fold   the subsection is a single row: shown in its category without a header (s.prefix before its label)
function M.layout(sections,object_category)
    local cats,by_id,feeds_seen={},{},{}
    local first_seen=0
    local entries,round_list=classify_all(sections)
    -- (an attack's or a mount's rounds, in page order, after the page's own feeds)
    for i,r in ipairs(round_list)do feeds_seen['projectile\0\1'..r]=1000+i end
    for _,e in ipairs(entries)do
        local section,cat,title,feed,rank,status=e.section,e.cat,e.title,e.feed,e.rank,e.status
        local head=e.head
        local id=cat or('h:'..tostring(head))
        local c=by_id[id]
        if not c then
            first_seen=first_seen+1
            c={id=id,title=cat and M.TITLES[cat]or head,key='c|'..id,subs={},by_sub={},rows={},seen=first_seen,
                classified=cat~=nil}
            by_id[id]=c
            cats[#cats+1]=c
        end
        if not cat then
            title=section.label
            if status then title=title:gsub(' · Status$','')end
        end
        -- a feed's subsections after the main round's, in the order the feeds appear; an attack's round's together
        local group=feed~=''and feed or(e.carrier and('\1'..e.carrier))or''
        local fkey=id..'\0'..group
        if not feeds_seen[fkey]then feeds_seen[fkey]=(group==''and 0 or(#c.subs+1))end
        local full=(feed~=''and(feed..SEP)or'')..title..(status and(SEP..'Status')or'')
        local sub=c.by_sub[full]
        if not sub then
            sub={title=full,key=c.key..'|'..full,rows={},feed_rank=feeds_seen[fkey],rank=rank+(status and 0.5 or 0),
                n=#c.subs+1,feed=feed}
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
            -- (an explosion's payload slot before its stats: where a player picks what goes off; the settings of the
            -- explosion it names, ui/app.lua payload_sections, right under it)
            local refs,rest={},{}
            for _,r in ipairs(s.rows)do
                if r.field=='terminal.explosion'or r.shown_by then refs[#refs+1]=r else rest[#rest+1]=r end
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
            for _,s in ipairs(c.subs)do if s.rank<RANK.impact then round=true end end
            if not round then c.title=SUB_TITLES.explosion end
        end
        -- no header for a single field (a category of one part shows that part's rows under the category itself)
        c.flat=#c.subs==1 and(c.subs[1].title==c.title or not c.classified)
        c.plain=#c.rows==1
        if c.plain then
            local s,row=c.subs[1],c.rows[1]
            local label=row and row.label
            if c.classified then
                local own=M.fold_prefix(s.title,label,s.feed)
                -- (the category's name, unless the part's own title says enough: "Ammunition · Magazine capacity")
                c.prefix=own and s.title~=c.title and own or M.fold_prefix(c.title,label)
                if s.feed~=''and c.prefix and c.prefix:sub(1,#s.feed)~=s.feed then c.prefix=s.feed..SEP..c.prefix end
            else
                c.prefix=M.fold_prefix(s.title,label)
            end
        end
        for _,s in ipairs(c.subs)do
            s.fold=#s.rows==1 and not c.flat and not c.plain
            if s.fold then s.prefix=M.fold_prefix(s.title,s.rows[1].label,s.feed)end
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
    for i,e in ipairs((classify_all(sections)))do
        keyed[i]={section=e.section,c=e.cat and rank[e.cat]or 40,f=e.feed~=''and 1 or 0,
            r=(e.rank or 1)+(e.status and 0.5 or 0),i=i}
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
