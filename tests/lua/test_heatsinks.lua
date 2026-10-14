local args=...
local H=assert(loadfile(args.harness))({sim=args.sim})
local A=require('hd2runtime/domains/attachment_authoring')
local function open(name)
 local o=assert(H.catalog:object('pw|'..name));H.catalog:open(o);assert(not o.error,o.error);return o
end
local function settle()for _=1,240 do H.sim.tick(0.1);H.layer:tick(0.1)end end
local seen=0
-- Every resolved magazine/heatsink override must appear on its weapon page, with the same native target.
for name,slot in pairs(A.weapons)do
 local o=H.catalog:object('pw|'..name)
 if o then
  H.catalog:open(o);assert(not o.error,o.error)
  local expected={}
  if slot.default then expected[slot.default]=true end
  for _,v in ipairs(slot.options)do if v.attachment then expected[v.attachment]=true end end
  for id in pairs(expected)do
   local e=A.attachments[id]
   for field,f in pairs(e.fields)do
    local found
    for _,r in ipairs(o.rows)do if r.group and r.field==field and r.target and r.target().attachment==id then
     assert(r.editable and r.vanilla==f.currentDefault,field)
     assert(r.group==(e.kind=='heatsink'and'Heatsinks'or'Magazines'),name..' '..field..' group '..tostring(r.group))
     found=true;seen=seen+1;break
    end end
    assert(found,name..' missing '..e.name..' '..field)
   end
  end
 end
end
assert(seen>250,'magazine coverage '..seen)
local scythe=open('LAS-5 Scythe');local spares={}
for _,r in ipairs(scythe.rows)do if r.field=='heatsink.spare'and r.editable then spares[#spares+1]=r end end
assert(#spares==3)
for i,r in ipairs(spares)do assert(H.layer:set(r,i+8))end;settle()
for i,r in ipairs(spares)do assert(H.sim.value(r)==i+8)end
for _,r in ipairs(spares)do assert(H.layer:reset(r))end;settle()
for _,r in ipairs(spares)do assert(H.sim.value(r)==r.held_vanilla)end
for _,name in ipairs({'LAS-5 Scythe','LAS-7 Dagger','LAS-16 Sickle','LAS-17 Double-Edge Sickle'})do
 for _,r in ipairs(open(name).rows)do if r.field:match('^heatsink%.')then assert(r.group=='Heatsinks')end end
end
local sai=open('LAS-12 Sai');local inherited=false
for _,r in ipairs(sai.rows)do if r.label=='Uses weapon values'then inherited=true;assert(r.group=='Heatsinks'and not r.editable)end end
assert(inherited)
-- Attachment-derived timings use only the matching variant's pending values.
local shear=open('LAS-22 Shear');local gain,fire
for _,r in ipairs(shear.rows)do
 if r.group=='Heatsinks'and r.field=='heat.charge_gain_per_second'then gain=r end
 if r.group=='Heatsinks'and r.field=='heat.warmup'then fire=r end
end
assert(gain and fire and fire.calculate)
assert(H.app:stage(gain,200));assert(math.abs(H.app:row_view(fire)-0.5)<1e-6);H.app:discard()
H.app:reveal(spares[1]);local frame=H.frame({});assert(#frame.refused==0)
if args.frame then local f=assert(io.open(args.frame,'wb'));f:write(H.dump(frame));f:close()end
return 'magazines and heatsinks coverage independent apply reset derived render ok'
