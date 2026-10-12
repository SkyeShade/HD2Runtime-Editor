local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
for _,item in ipairs({
 {'pw|PLAS-39 Accelerator Rifle','charge.burst_shots',4},
 {'pw|PLAS-39 Accelerator Rifle','charge.burst_interval_seconds',0.2},
 {'pw|PLAS-39 Accelerator Rifle','charge.explode_at_overcharge',false},
 {'pw|PLAS-39 Accelerator Rifle','fire_mode.modes',{'single','unsafe'}},
 {'th|G/SH-39 Shield','shield.recharge_delay',2},
 {'th|G/SH-39 Shield','shield.broken_recharge_delay',3},
 {'th|G/SH-39 Shield','shield.recharge_rate',50},
})do
 local o=assert(H.catalog:object(item[1]));H.catalog:open(o);assert(not o.error,o.error)
 local row;for _,r in ipairs(o.rows)do if r.field==item[2]then row=r end end
 assert(row and row.editable,item[2]..' missing')
 assert(H.layer:set(row,item[3]));settle()
 local value=H.sim.value(row)
 if type(item[3])=='boolean'then assert(value==item[3]or value==(item[3]and 1 or 0)or value==string.char(item[3]and 1 or 0),item[2])
 elseif type(item[3])=='table'then
  local b=require('hd2runtime/core/bytes')
  assert(type(value)=='table'and value[2]=='unsafe'or type(value)=='string'and b.u32(value,0)==2 and b.u32(value,4)==6)
 elseif type(value)=='number'then assert(math.abs(value-item[3])<1e-5,item[2])else assert(value==item[3],item[2])end
 assert(H.layer:reset(row));settle()
 H.app:reveal(row);assert(#H.frame({}).refused==0)
end
local groups={}
for _,category in ipairs({'terminids','automatons','illuminate','structures','enemy_entities'})do
 local list=H.catalog:objects(category);local rank=0
 for _,o in ipairs(list)do
  assert(o.control_rank>=rank,'gameplay entries must sort first');rank=o.control_rank
  assert(o.filter_group);groups[o.filter_group]=true
 end
 local chips=assert(H.app:weapon_groups(category));assert(chips[1]=='All')
 H.app:goto_object(list[1]);H.app:set_weapon_group(category,'Size only')
 for _,o in ipairs(H.app:objects())do assert(o.filter_group=='Size only')end
 H.app:set_weapon_group(category,'All')
end
assert(groups['Gameplay controls']and groups['Size only'])
return 'dev4 controls and capability groups ok'
