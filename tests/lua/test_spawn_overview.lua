local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local app,cat=H.app,H.catalog
cat.indexed=true
local overview=require('mods/skyeshade/hd2runtime_editor/editor/ui/spawn_overview')
local icons=require('mods/skyeshade/hd2runtime_editor/editor/icons')
local loaded=icons.load(H.hd2)
assert(#cat:objects('enemy_overview')==3)
local o=assert(cat:object('eo|terminids'));assert(app:goto_object(o))
local frame=H.frame({});assert(#frame.refused==0 and#frame.items<1024)
if args.frame then local f=assert(io.open(args.frame,'wb'));f:write(H.dump(frame));f:close()end
assert(overview.start(app,'terminids',2)and app.pending_n==0)
app:apply();assert(app.spawn_job,'Apply must wait for preparation')
assert(not overview.start(app,'illuminate',3),'concurrent preparations must not overlap')
local function finish()
    for _=1,1000 do
        local d=H.frame({});assert(#d.refused==0 and#d.items<1024)
        if not app.spawn_job then return end
    end
    error('spawn preparation did not complete')
end
finish();assert(app.pending_n>100,'faction composition counts missing')
local values={}
for key,p in pairs(app.pending)do
    assert(key:find('ed|composition/terminids/',1,true)==1,'another faction was modified')
    assert(p.row.field:match('_count$')and p.value==math.min(64,math.floor(p.row.vanilla*2+0.5)))
    values[key]=p.value
end
local encoded=app:encode_values(values)
for key,value in pairs(encoded)do local row,got=app:decode_value(key,value);assert(row and got==values[key])end
local n=app.pending_n
assert(overview.start(app,'terminids',2));finish();assert(app.pending_n==n,'2x compounded')
assert(overview.start(app,'terminids',1));finish();assert(app.pending_n==0,'1x did not restore defaults')
assert(overview.start(app,'automatons',3));overview.tick(app);overview.tick(app)
app:discard();assert(not app.spawn_job and app.pending_n==0,'Discard did not stop preparation')
-- Independent scopes survive save/load, and 1x resets just the selected scope.
for channel,family in pairs({patrol=1,map=3,reinforcement=4})do
    assert(overview.start(app,'terminids',2,channel));finish()
    local n=0
    for key,p in pairs(app.pending)do
        assert(key:find('family_'..family..'/',1,true),'wrong composition family');n=n+1
    end
    assert(n>0);app:discard()
end
assert(overview.start(app,'illuminate',0.5,'frequency'));finish()
assert(app.pending_n>0)
for key,p in pairs(app.pending)do
    assert(p.row.field:match('^hive%.patrol_clock_rate_players_'))
    assert(math.abs(p.value-p.row.vanilla*0.5)<0.00001,tostring(p.value).." / "..tostring(p.row.vanilla))
    local encoded=app:encode_values({[key]=p.value})
    local row,value=app:decode_value(key,encoded[key]);assert(row and value==p.value)
end
assert(overview.start(app,'illuminate',1,'frequency'));finish();assert(app.pending_n==0)
assert(overview.start(app,10,2,'spawner_frequency','difficulty'));finish()
assert(app.pending_n==1)
for key,p in pairs(app.pending)do
    assert(key:find('ed|difficulty/10',1,true)and p.row.field=='difficulty.shared_spawner_cooldown')
    assert(p.value==p.row.vanilla/2)
end
app:discard()
-- Horizontal drag ignores vertical motion and prepares only once on release.
local state={value=1};local releases=0
overview.begin_slider(app,state,100,490,100,function(value)assert(value==5);releases=releases+1 end)
local cv=app.canvas
app:handle_mouse({wheel=0,mouse={x=(cv.ox+590)*cv.s,y=(cv.oy+20)*cv.s,left=true}})
assert(state.value==5 and releases==0)
app:handle_mouse({wheel=0,mouse={x=(cv.ox+590)*cv.s,y=(cv.oy+900)*cv.s,left=false}})
assert(releases==1 and not app.drag)
local names={'Trivial','Easy','Medium','Challenging','Hard','Extreme','Suicide Mission','Impossible','Helldive','Super Helldive'}
for level,item in ipairs(cat:objects('enemy_difficulty'))do
    assert(item.name==names[level]..' - '..level,'difficulty ordering or title incorrect')
    assert(icons.entry(loaded,item)==loaded.difficulties[tostring(level)],'difficulty icon absent')
    assert(item.spawnDifficulty==level and app:goto_object(item))
    local d=H.frame({});assert(#d.refused==0 and#d.items<1024)
end
local walking=assert(cat:object('st|Orbital Walking Barrage'));cat:open(walking)
local fields={};for _,row in ipairs(walking.rows)do fields[row.field]=row end
assert(fields['orbital.walking_speed'].editable and fields['orbital.walking_speed'].vanilla==3)
assert(fields['orbital.aim_step_min'].editable and fields['orbital.aim_step_max'].editable)
assert(fields['stratagem.max_uses'].label=='Mission uses (next launch)')
assert(fields['stratagem.max_uses'].note:find('before launch',1,true))
for _,category in ipairs({'enemy_rosters','enemy_compositions'})do
    assert(app:goto_object(cat:objects(category)[1]))
    local groups=app:weapon_groups(category);assert(#groups>=4)
    app:set_weapon_group(category,'Illuminate')
    assert(#app:objects()>0)
    for _,item in ipairs(app:objects())do
        assert(item.filter_group=='Illuminate'and item.iconName=='illuminate')
    end
    assert(#H.frame({}).refused==0)
end
local enemy=assert(cat:object('en|warrior_big_tier2'));cat:open(enemy)
local seen={}
for _,r in ipairs(enemy.rows)do seen[r.field]=r end
for _,field in ipairs({'health_change_rate','health_change_rate_disabled','regeneration_cooldown',
    'regeneration_segments','regeneration_change_rate','zone_bleedout_change_rate'})do
    assert(seen['entity.'..field]and seen['entity.'..field].editable,'health control locked: '..field)
end
assert(not seen['entity.kill_score'].editable,'unproven kill-score control was unlocked')
return 'faction spawn staging cache cancellation presets icons names health controls ok'
