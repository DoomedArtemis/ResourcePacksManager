// Review the PNG pixels actually sampled by every generated crystal face.
const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib');
const {minerals,textureMinerals,ores,root}=require('./generate-alternative-ores.cjs');
function decode(file) {
  const bytes=fs.readFileSync(file),width=bytes.readUInt32BE(16),height=bytes.readUInt32BE(20),chunks=[];
  for(let offset=8;offset<bytes.length;) {
    const size=bytes.readUInt32BE(offset);
    if(bytes.toString('ascii',offset+4,offset+8)==='IDAT') chunks.push(bytes.subarray(offset+8,offset+8+size));
    offset+=size+12;
  }
  const raw=zlib.inflateSync(Buffer.concat(chunks)),stride=width*4+1;
  for(let y=0;y<height;y++) if(raw[y*stride]!==0) throw new Error('Unexpected PNG filter');
  return {width,height,pixel:(x,y)=>raw.subarray(y*stride+1+x*4,y*stride+1+x*4+4)};
}
function audit() {
  const report=[];
  const images=new Map();
  for(const mineral of textureMinerals) for(let variant=0;variant<6;variant++) {
    const model=JSON.parse(fs.readFileSync(path.join(root,`assets/minecraft/models/block/alternative_ores/crystal_layout_${variant+1}.json`)));
    for(const el of model.elements.slice(1)) for(const [dir,face] of Object.entries(el.faces)) {
      const key=`${mineral}_${face.texture.slice(-1)}`;
      if(!images.has(key)) images.set(key,decode(path.join(root,`assets/minecraft/textures/block/alternative_ores/${mineral}_${face.texture.slice(1)}.png`)));
      const image=images.get(key);
      const rectangle=face.uv.map(n=>Math.round(n*image.width/16));
      const [x0,y0,x1,y1]=[Math.min(rectangle[0],rectangle[2]),Math.min(rectangle[1],rectangle[3]),Math.max(rectangle[0],rectangle[2]),Math.max(rectangle[1],rectangle[3])];
      const colors=new Map();let isolated=0,warm=0,incomplete=0;
      for(let y=y0;y<y1;y++) for(let x=x0;x<x1;x++) {
        const pixel=image.pixel(x,y),key=pixel.subarray(0,3).toString('hex');
        colors.set(key,(colors.get(key)||0)+1);
        if(pixel[3]!==255) incomplete++;
        if(pixel[0]>pixel[2] || pixel[1]>pixel[2]) warm++;
        // Smooth tonal steps are intentional; only isolated high-contrast dots
        // count as speckle noise, rather than every unique gradient color.
        if(x>x0&&x<x1-1&&y>y0&&y<y1-1&&[[x-1,y],[x+1,y],[x,y-1],[x,y+1]].every(([u,v])=>Math.hypot(...Array.from(image.pixel(u,v).subarray(0,3),(value,i)=>value-pixel[i]))>28)) isolated++;
      }
      const area=(x1-x0)*(y1-y0);
      report.push({mineral,variant:variant+1,piece:el.name,dir,colors:colors.size,isolated,area,warm,incomplete});
    }
  }
  return report;
}
function auditRotations() {
  const read=file=>JSON.parse(fs.readFileSync(path.join(root,`assets/minecraft/${file}.json`)));
  const images=new Map(),report=[];
  for(const ore of ores) for(const state of read(`blockstates/${ore.name}`).multipart[1].apply) {
    const wrapper=read(`models/${state.model.split(':')[1]}`);
    const model=read(`models/${wrapper.parent.split(':')[1]}`);
    for(const el of model.elements) for(const dir of ['up','down']) {
      const face=el.faces[dir];
      const texture=wrapper.textures[face.texture.slice(1)].split(':')[1];
      if(!images.has(texture)) images.set(texture,decode(path.join(root,`assets/minecraft/textures/${texture}.png`)));
      const image=images.get(texture);
      let bounds=[face.uv.slice(0,2),face.uv.slice(2)];
      if(state.uvlock) for(let step=0;step<(state.y||0)/90;step++)
        bounds=bounds.map(([u,v])=>dir==='up'?[v,16-u]:[16-v,u]);
      const x0=Math.round(Math.min(bounds[0][0],bounds[1][0])*image.width/16),x1=Math.round(Math.max(bounds[0][0],bounds[1][0])*image.width/16);
      const y0=Math.round(Math.min(bounds[0][1],bounds[1][1])*image.height/16),y1=Math.round(Math.max(bounds[0][1],bounds[1][1])*image.height/16);
      const colors=new Set();
      for(let y=y0;y<y1;y++) for(let x=x0;x<x1;x++) colors.add(image.pixel(x,y).subarray(0,3).toString('hex'));
      report.push({ore:ore.name,rotation:state.y||0,piece:el.name,dir,colors:colors.size,uvlock:state.uvlock===true});
    }
  }
  return report;
}
if(require.main===module) {
  if(process.argv.includes('--rotations')) {
    const report=auditRotations();
    console.log(`${report.length} crystal top/bottom faces across block rotations; ${report.filter(face=>face.colors<2).length} sample a solid-color region.`);
    console.log(JSON.stringify(report.filter(face=>face.colors<2).slice(0,3)));
    return;
  }
  const report=audit();
  for(const mineral of textureMinerals) {
    const patches=report.filter(p=>p.mineral===mineral);
    console.log(`${mineral}: ${patches.length} patches; ${patches.filter(p=>p.colors<2).length} flat; ${patches.reduce((n,p)=>n+p.isolated,0)} isolated pixels`);
  }
  const target=path.join(__dirname,'../cache/work/alternative-ores/texture-audit.json');
  fs.writeFileSync(target,JSON.stringify(report,null,2)+'\n');
  if(process.argv.includes('--check')) {
    const failed=report.filter(p=>p.colors<2||p.incomplete>0||p.isolated/p.area>.05||(p.mineral==='lapis'&&p.warm>0));
    if(failed.length) {console.error('Failed patches:',failed.slice(0,10));process.exitCode=1;}
    else console.log(`PASS: ${report.length} painted face patches; no solid-color faces, incomplete pixels, noisy speckles, or warm colors in lapis.`);
  }
}
module.exports={audit,auditRotations};
