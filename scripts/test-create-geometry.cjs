const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const root=path.resolve(__dirname,'../resource_packs/alternative_ores');
const read=p=>JSON.parse(fs.readFileSync(path.join(root,p),'utf8'));
const modelPath=id=>'assets/'+id.replace(':','/models/')+'.json';
for(const block of ['copper_ore','zinc_ore','deepslate_zinc_ore']) {
  const state=read(`assets/create/blockstates/${block}.json`);
  const copper=block==='copper_ore',base=block.startsWith('deepslate_')?'deepslate':'stone';
  assert.equal(state.multipart[0].apply.model,`minecraft:block/${base}`);
  assert.equal(state.multipart.length,copper?9:2);
  for(let stage=0;stage<(copper?8:1);stage++) {
    const entry=state.multipart[stage+1];
    if(copper) assert.deepEqual(entry.when,{oxidization:String(stage)});
    else assert.equal(entry.when,undefined);
    assert.equal(entry.apply.length,24);
    assert.equal(new Set(entry.apply.map(v=>v.model)).size,6);
    for(let layout=1;layout<=6;layout++) {
      const variants=entry.apply.slice((layout-1)*4,layout*4);
      assert.deepEqual(variants.map(v=>v.y),[0,90,180,270]);
      for(const variant of variants) {
        assert.equal(variant.uvlock,false);
        const model=read(modelPath(variant.model));
        assert.equal(model.parent,`${copper?'create':'minecraft'}:block/alternative_ores/${copper?'copper_':''}crystal_layout_${layout}_overlay`);
        assert.equal(model.elements,undefined,'Keep geometry in the unchanged existing layouts.');
        assert.equal(model.textures.base,`minecraft:block/${base}`);
        assert.equal(model.textures.top,`minecraft:block/${base==='deepslate'?'deepslate_top':'stone'}`);
        assert.equal(model.textures.particle,'#base');
      }
    }
  }
  const item=read(`assets/create/models/item/${block}.json`);
  assert.equal(item.parent,`create:block/alternative_ores/${block}/${copper?'oxidization_0/':''}layout_1`);
}
for(let layout=1;layout<=6;layout++) {
  for(const suffix of ['','_overlay']) {
    const relative=`models/block/alternative_ores/copper_crystal_layout_${layout}${suffix}.json`;
    assert.deepEqual(read(`assets/create/${relative}`),read(`assets/minecraft/${relative}`),'Copper geometry/UVs must be copied unchanged.');
  }
  const template=read(`assets/create/models/block/alternative_ores/copper_crystal_layout_${layout}_overlay.json`);
  const used=[...new Set(template.elements.flatMap(e=>Object.values(e.faces).map(f=>f.texture)))];
  const signatures=[];
  for(let stage=0;stage<8;stage++) {
    const model=read(`assets/create/models/block/alternative_ores/copper_ore/oxidization_${stage}/layout_${layout}_overlay.json`);
    signatures.push(JSON.stringify(used.map(reference=>model.textures[reference.slice(1)])));
  }
  assert.equal(new Set(signatures).size,8,`All eight oxidation stages must remain visibly distinct in layout ${layout}.`);
}
for(const stage of ['copper','exposed_copper','weathered_copper','oxidized_copper']) for(const variant of ['a','b']) for(const suffix of ['','_e']) {
  const relative=`textures/block/alternative_ores/${stage}_crystal_${variant}${suffix}.png`;
  assert.deepEqual(fs.readFileSync(path.join(root,'assets/create',relative)),fs.readFileSync(path.join(root,'assets/minecraft',relative)),'Existing copper pixels must not change.');
}
const baselineArgument=process.argv.indexOf('--baseline');
if(baselineArgument!==-1) {
  const baseline=JSON.parse(fs.readFileSync(process.argv[baselineArgument+1],'utf8'));
  for(const [relative,hash] of Object.entries(baseline)) assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root,relative))).digest('hex'),hash,relative);
  console.log(`All ${Object.keys(baseline).length} existing vanilla, Mekanism and AE2 assets are byte-identical.`);
}
console.log('Passed Create geometry, six layouts/four rotations, eight distinct copper oxidation stages, inventory models, rock debris and exact copper artwork reuse.');
