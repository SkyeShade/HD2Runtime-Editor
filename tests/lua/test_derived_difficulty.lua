local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local app,cat=H.app,H.catalog
cat.indexed=true
local I=require('mods/skyeshade/hd2runtime_editor/editor/icons')
app.ctx.icons=I.load({resources={image=function(id)return{image=id}end,
    game_icon=H.hd2.resources.game_icon,game_icons=H.hd2.resources.game_icons}})
local C=require('mods/skyeshade/hd2runtime_editor/editor/catalog')
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
local o=assert(cat:object('pw|LAS-17 Double-Edge Sickle'));cat:open(o)
local fields={};for _,r in ipairs(o.rows)do fields[r.field]=r end
local function stage(id,value)assert(app:stage(assert(fields[id],id),value))end
stage('heat.firing_charge',100);stage('heat.charge_gain_per_second',200);stage('heat.charge_loss_per_second',75)
assert(fields['heat.reset_charge_after_shot'].label=='Wind-up again after each shot')
assert(fields['heat.reset_charge_after_shot'].note:find('does not reset heat',1,true))
local fire,decay=assert(fields['heat.warmup']),assert(fields['heat.charge_decay_time'])
assert(not fire.editable and not decay.editable and fire.calculate and decay.calculate)
assert(C.text(fire,app:row_view(fire))=='0.5 s')
assert(C.text(decay,app:row_view(decay))=='1.333 s')
stage('heat.firing_charge',120);assert(C.text(fire,app:row_view(fire))=='0.6 s')
stage('heat.firing_charge',100)
assert(fields['heat.cool_per_second'].note:find('zero wind-up charge',1,true))
local before=app.pending_n;assert(not app:stage(fire,1)and app.pending_n==before,'derived values must not stage writes')
assert(app:goto_object(o));app:reveal(decay)
local frame=H.frame({});assert(#frame.refused==0)
if args.heat_frame then local f=assert(io.open(args.heat_frame,'wb'));f:write(H.dump(frame));f:close()end
app:apply();settle();assert(C.text(decay,app:row_view(decay))=='1.333 s')
stage('heat.charge_loss_per_second',60);app:apply();settle()
assert(C.text(decay,app:row_view(decay))=='1.667 s')
assert(H.layer:reset(fields['heat.charge_loss_per_second']));settle()
assert(math.abs(app:row_view(decay)-100/fields['heat.charge_loss_per_second'].vanilla)<1e-6)
stage('heat.charge_loss_per_second',0);assert(C.text(decay,app:row_view(decay))=='Never')
stage('heat.firing_charge',0);assert(C.text(decay,app:row_view(decay))=='0 s')
local cooldown=assert(fields['heat.overheat_cooldown'])
assert(C.text(cooldown,app:row_view(cooldown))=='Heatsink change')
stage('heat.prevent_overheat_cooling',false)
stage('heat.capacity',100);stage('heat.overheat_release_threshold',10);stage('heat.cool_per_second_overheated',10)
assert(C.text(cooldown,app:row_view(cooldown))=='9 s')
stage('heat.cool_per_second_overheated',0);assert(C.text(cooldown,app:row_view(cooldown))=='Never')
app:discard()
local d=cat:objects('enemy_difficulty')[9];cat:open(d)
local counts,keys={},{ }
local mirror
for _,r in ipairs(d.rows)do if r.canonical then
    assert(r.field=='spawn.weight_9' and r.key==r.canonical.key and cat.rows[r.key]==r.canonical)
    assert(r.loc==r.canonical.loc and r.object==d and r.canonical.object.category=='enemy_rosters')
    assert(not keys[r.key],'duplicate alias');keys[r.key]=true
    counts[r.section]=(counts[r.section]or 0)+1
    if not mirror and r.editable then mirror=r end
end end
for _,f in ipairs({'Terminids','Automatons','Illuminate'})do assert(counts[f]and d.section_icons[f],f)end
assert(mirror,'missing editable mirror')
local original=mirror.canonical
assert(original.label=='Difficulty 9 weight')
local value=original.vanilla+0.25
assert(app:stage(mirror,value));assert(app.pending_n==1 and app.pending[original.key].row==original)
assert(app:row_view(original)==value and app:row_view(mirror)==value)
assert(app:stage(original,value+0.25));assert(app.pending_n==1 and app:row_view(mirror)==value+0.25)
local encoded=app:encode_values({[mirror.key]=value+0.25})
local n=0;for key,v in pairs(encoded)do local row,got=app:decode_value(key,v);assert(row==original and got==value+0.25);n=n+1 end
assert(n==1,'two preset entries for one field')
assert(app:goto_object(d));app:reveal(mirror);frame=H.frame({});assert(#frame.refused==0 and#frame.items<1024)
if args.difficulty_frame then local f=assert(io.open(args.difficulty_frame,'wb'));f:write(H.dump(frame));f:close()end
app:apply();settle();assert(app:row_view(original)==value+0.25 and app:row_view(mirror)==value+0.25)
assert(H.layer:reset(mirror));settle();assert(app:row_view(mirror)==original.vanilla)
local other=cat:objects('enemy_difficulty')[8];cat:open(other)
for _,r in ipairs(other.rows)do if r.canonical then assert(r.field=='spawn.weight_8'and r.key~=mirror.key)end end
return 'derived pending applied reset zero rates and difficulty canonical aliases sync presets render ok'
