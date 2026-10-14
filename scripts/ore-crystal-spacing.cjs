// Exact oriented-box separation, including tilted crystals on different faces.
const dot=(a,b)=>a.reduce((n,v,i)=>n+v*b[i],0);
const subtract=(a,b)=>a.map((v,i)=>v-b[i]);
const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
function rotate(point,rotation,vector=false) {
  if(!rotation) return point;
  const origin=vector?[0,0,0]:rotation.origin;
  const p=subtract(point,origin),theta=rotation.angle*Math.PI/180;
  const [a,b]=rotation.axis==='x'?[1,2]:rotation.axis==='y'?[2,0]:[0,1];
  const u=p[a],v=p[b];
  p[a]=u*Math.cos(theta)-v*Math.sin(theta);
  p[b]=u*Math.sin(theta)+v*Math.cos(theta);
  return p.map((n,i)=>n+origin[i]);
}
function box(element) {
  return {
    center:rotate(element.from.map((v,i)=>(v+element.to[i])/2),element.rotation),
    half:element.from.map((v,i)=>(element.to[i]-v)/2),
    axes:[[1,0,0],[0,1,0],[0,0,1]].map(axis=>rotate(axis,element.rotation,true)),
    vertices:Array.from({length:8},(_,mask)=>rotate(element.from.map((v,i)=>mask&(1<<i)?element.to[i]:v),element.rotation))
  };
}
function separation(a,b) {
  const delta=subtract(b.center,a.center);
  const axes=[...a.axes,...b.axes,...a.axes.flatMap(x=>b.axes.map(y=>cross(x,y)))];
  let greatestGap=-Infinity;
  for(const axis of axes) {
    const length=Math.hypot(...axis);
    if(length<1e-8) continue;
    const normal=axis.map(n=>n/length);
    const radius=shape=>shape.axes.reduce((n,v,i)=>n+shape.half[i]*Math.abs(dot(v,normal)),0);
    greatestGap=Math.max(greatestGap,Math.abs(dot(delta,normal))-radius(a)-radius(b));
  }
  return greatestGap;
}
function auditSpacing(elements,clearance=.25) {
  const crystals=elements.filter(el=>el.name!=='plain_rock_core');
  const boxes=crystals.map(box),collisions=[],edgeCrossings=[];
  for(let i=0;i<crystals.length;i++) {
    const support=Object.values(crystals[i].faces)[0].cullface;
    const normalAxis=['up','down'].includes(support)?1:['north','south'].includes(support)?2:0;
    for(const axis of [0,1,2].filter(axis=>axis!==normalAxis)) {
      const low=Math.min(...boxes[i].vertices.map(v=>v[axis])),high=Math.max(...boxes[i].vertices.map(v=>v[axis]));
      if(low<clearance-1e-8||high>16-clearance+1e-8) edgeCrossings.push({crystal:crystals[i].name,axis,low,high});
    }
    for(let j=i+1;j<crystals.length;j++) {
      const gap=separation(boxes[i],boxes[j]);
      if(gap<clearance-1e-8) collisions.push({first:crystals[i].name,second:crystals[j].name,gap});
    }
  }
  return {pairs:crystals.length*(crystals.length-1)/2,collisions,edgeCrossings};
}
module.exports={box,separation,auditSpacing};
function auditNeighbors(models,clearance=.25) {
  const states=models.flatMap((model,layout)=>[0,90,180,270].map(angle=>{
    const transform={axis:'y',angle,origin:[8,8,8]};
    const ring=['north','west','south','east'];
    return model.elements.filter(el=>el.name!=='plain_rock_core').map(el=>{
      const original=box(el),vertices=original.vertices.map(p=>rotate(p,transform));
      const support=Object.values(el.faces)[0].cullface;
      const turn=ring.indexOf(support);
      return {...original,center:rotate(original.center,transform),axes:original.axes.map(axis=>rotate(axis,transform,true)),
        low:[0,1,2].map(i=>Math.min(...vertices.map(p=>p[i]))),high:[0,1,2].map(i=>Math.max(...vertices.map(p=>p[i]))),
        name:el.name,layout:layout+1,angle,support:turn<0?support:ring[(turn+angle/90)%4]};
    });
  }));
  const normals={north:[0,0,-1],south:[0,0,1],west:[-1,0,0],east:[1,0,0],up:[0,1,0],down:[0,-1,0]};
  const failures=[];let pairs=0;
  for(let x=-1;x<=1;x++) for(let y=-1;y<=1;y++) for(let z=-1;z<=1;z++) {
    if(x===0&&y===0&&z===0) continue;
    const offset=[x,y,z],shift=offset.map(n=>n*16);
    for(const first of states) for(const second of states) for(const a of first) for(const b of second) {
      // Crystals on the shared opaque block faces are culled in Minecraft.
      if(normals[a.support].every((n,i)=>n===offset[i])||normals[b.support].every((n,i)=>n===-offset[i])) continue;
      pairs++;
      if([0,1,2].some(i=>b.low[i]+shift[i]-a.high[i]>=clearance||a.low[i]-b.high[i]-shift[i]>=clearance)) continue;
      const gap=separation(a,{...b,center:b.center.map((n,i)=>n+shift[i])});
      if(gap<clearance-1e-8) failures.push({first:{layout:a.layout,angle:a.angle,name:a.name},second:{layout:b.layout,angle:b.angle,name:b.name},offset,gap});
    }
  }
  return {pairs,failures};
}
module.exports.auditNeighbors=auditNeighbors;
if(require.main===module) {
  const fs=require('node:fs'),path=require('node:path');
  const root=path.join(__dirname,'../resource_packs/alternative_ores/assets/minecraft/models/block/alternative_ores');
  for(let variant=1;variant<=6;variant++) {
    const model=JSON.parse(fs.readFileSync(path.join(root,`crystal_layout_${variant}.json`)));
    const audit=auditSpacing(model.elements);
    console.log(`Layout ${variant}: ${audit.pairs} pairs, ${audit.collisions.length} spacing failures, ${audit.edgeCrossings.length} edge crossings.`);
    if(audit.collisions.length||audit.edgeCrossings.length) {console.log(JSON.stringify(audit));process.exitCode=1;}
  }
  if(process.argv.includes('--neighbors')) {
    const models=Array.from({length:6},(_,i)=>JSON.parse(fs.readFileSync(path.join(root,`crystal_layout_${i+1}.json`))));
    const result=auditNeighbors(models);
    console.log(`Adjacent blocks: ${result.pairs} visible crystal pairs, ${result.failures.length} spacing failures.`);
    if(result.failures.length) {console.log(JSON.stringify(result.failures.slice(0,8)));process.exitCode=1;}
  }
}
