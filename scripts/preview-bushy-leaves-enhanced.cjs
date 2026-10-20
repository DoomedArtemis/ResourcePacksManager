// Local software-rendered geometry study, with an offline interactive viewer.
// Usage: node scripts/preview-bushy-leaves-enhanced.cjs path/to/textures.json output-directory
// textures.json: { oak: { width: 16, pixels: [r,g,b,a,...] }, ... }
// Textures are read only for the preview; they are never added to the pack.
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const { geometry } = require('./update-bushy-leaves-enhanced.cjs');

function mesh(model) {
  const quads = [];
  for (const e of model.elements) {
    const [x,y,z] = e.from, [X,Y,Z] = e.to;
    const vertices = {
      north: [[X,y,z],[x,y,z],[x,Y,z],[X,Y,z]], south: [[x,y,Z],[X,y,Z],[X,Y,Z],[x,Y,Z]],
      west: [[x,y,z],[x,y,Z],[x,Y,Z],[x,Y,z]], east: [[X,y,Z],[X,y,z],[X,Y,z],[X,Y,Z]],
      up: [[x,Y,Z],[X,Y,Z],[X,Y,z],[x,Y,z]], down: [[x,y,z],[X,y,z],[X,y,Z],[x,y,Z]],
    };
    for (const [direction, face] of Object.entries(e.faces)) {
      const p = vertices[direction].map(v => {
        v = [...v];
        if (e.rotation) {
          const { origin:o, axis, angle } = e.rotation;
          const [a,b] = { x:[1,2], y:[2,0], z:[0,1] }[axis];
          const c = Math.cos(angle*Math.PI/180), s = Math.sin(angle*Math.PI/180);
          const u = v[a]-o[a], w = v[b]-o[b];
          v[a] = o[a]+u*c-w*s; v[b] = o[b]+u*s+w*c;
        }
        return v;
      });
      quads.push({ p, uv: face.uv, cull: face.cullface,
        material: face.texture.slice(1),
        light: e.shade === false ? 0.91 : ({up:1,down:.62,north:.78,south:.78,east:.88,west:.88}[direction]),
        tinted: face.tintindex === 0 });
    }
  }
  return quads;
}

// This function is shared verbatim with the browser preview. Orthographic view,
// nearest-neighbour alpha cutout and a depth buffer, with no external libraries.
function render(width, height, quads, texture, tint, yaw, pitch, cluster = false, materials = {}) {
  const pixels = new Uint8ClampedArray(width*height*4), depth = new Float64Array(width*height).fill(-Infinity);
  for (let y=0;y<height;y++) for(let x=0;x<width;x++) {
    const k=(y*width+x)*4, t=y/height;
    pixels[k]=18+t*6; pixels[k+1]=29+t*11; pixels[k+2]=29+t*9; pixels[k+3]=255;
  }
  const ca=Math.cos(yaw),sa=Math.sin(yaw),cp=Math.cos(pitch),sp=Math.sin(pitch);
  const scale=Math.min(width,height)/(cluster?91:47);
  function project(v,offset) {
    const [x,y,z]=v.map((n,i)=>n-8+offset[i]);
    const a=x*ca-z*sa,b=x*sa+z*ca;
    return [width/2+a*scale,height*.53-(y*cp-b*sp)*scale,y*sp+b*cp];
  }
  const offsets=cluster?[[0,0,0],[-16,0,0],[16,0,0],[0,0,-16],[0,0,16],[0,16,0],[0,-16,0]]:[[0,0,0]];
  const neighbour={east:[16,0,0],west:[-16,0,0],up:[0,16,0],down:[0,-16,0],south:[0,0,16],north:[0,0,-16]};
  for(const offset of offsets) for(const q of quads) {
    const sprite=materials[q.material]||texture;
    if(cluster && offsets.some(o=>o.every((n,i)=>n===offset[i]+neighbour[q.cull][i]))) continue;
    const p=q.p.map(v=>project(v,offset)),[u,v,U,V]=q.uv;
    const uv=[[u,V],[U,V],[U,v],[u,v]];
    for(const indices of [[0,1,2],[0,2,3]]) {
      const [a,b,c]=indices.map(i=>p[i]),[ta,tb,tc]=indices.map(i=>uv[i]);
      const area=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
      if(Math.abs(area)<1e-7) continue;
      // Both sides of each spray are present in the mesh. Cull backfaces so
      // intersecting planes do not draw each surface twice.
      if(area>0) continue;
      const minX=Math.max(0,Math.floor(Math.min(a[0],b[0],c[0]))),maxX=Math.min(width-1,Math.ceil(Math.max(a[0],b[0],c[0])));
      const minY=Math.max(0,Math.floor(Math.min(a[1],b[1],c[1]))),maxY=Math.min(height-1,Math.ceil(Math.max(a[1],b[1],c[1])));
      for(let y=minY;y<=maxY;y++)for(let x=minX;x<=maxX;x++) {
        const s=((b[0]-x-.5)*(c[1]-y-.5)-(b[1]-y-.5)*(c[0]-x-.5))/area;
        const t=((c[0]-x-.5)*(a[1]-y-.5)-(c[1]-y-.5)*(a[0]-x-.5))/area, r=1-s-t;
        if(s<0||t<0||r<0)continue;
        const d=s*a[2]+t*b[2]+r*c[2],n=y*width+x;
        if(d<=depth[n])continue;
        const tx=Math.min(sprite.width-1,Math.max(0,Math.floor((s*ta[0]+t*tb[0]+r*tc[0])*sprite.width/16)));
        const ty=Math.min(sprite.width-1,Math.max(0,Math.floor((s*ta[1]+t*tb[1]+r*tc[1])*sprite.width/16)));
        const k=(ty*sprite.width+tx)*4;
        if(sprite.pixels[k+3]<128)continue;
        depth[n]=d;
        for(let channel=0;channel<3;channel++)pixels[n*4+channel]=sprite.pixels[k+channel]*q.light*(q.tinted?tint[channel]:1);
      }
    }
  }
  return pixels;
}

function png(width,height,pixels) {
  function crc(data) { let c=0xffffffff; for(const b of data){c^=b;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return(c^0xffffffff)>>>0; }
  function chunk(type,data) { const header=Buffer.alloc(8),tail=Buffer.alloc(4);header.writeUInt32BE(data.length);header.write(type,4);tail.writeUInt32BE(crc(Buffer.concat([Buffer.from(type),data])));return Buffer.concat([header,data,tail]); }
  const header=Buffer.alloc(13);header.writeUInt32BE(width);header.writeUInt32BE(height,4);header[8]=8;header[9]=6;
  const raw=Buffer.alloc(height*(width*4+1));for(let y=0;y<height;y++)Buffer.from(pixels.buffer,pixels.byteOffset+y*width*4,width*4).copy(raw,y*(width*4+1)+1);
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',zlib.deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);
}

if(require.main===module) {
  const [input,output]=process.argv.slice(2);
  if(!input||!output)throw Error('Supply textures.json and an output directory');
  const textures=JSON.parse(fs.readFileSync(input,'utf8').replace(/^\uFEFF/,''));
  const examples=[['oak','broad',[.47,.70,.24]],['birch','airy',[.5,.67,.32]],['spruce','conifer',[.38,.55,.38]],['jungle','lush',[.35,.67,.2]],['cherry','blossom',[1,1,1]],['flowering_azalea','blossom',[1,1,1]]];
  const studies=examples.map(([name,profile,tint])=>({name,profile,tint,mesh:[0,1,2].map(l=>mesh(geometry(profile,l,name!=='flowering_azalea'))),vanilla:mesh({elements:[geometry(profile,0,name!=='flowering_azalea').elements[0]]})}));
  fs.mkdirSync(output,{recursive:true});
  const tile=300,width=tile*6,height=tile*2,pixels=new Uint8ClampedArray(width*height*4);
  for(const [i,study] of studies.entries())for(let row=0;row<2;row++) {
    const image=render(tile,tile,row?study.mesh[0]:study.vanilla,textures[study.name],study.tint,.66,.48,false);
    for(let y=0;y<tile;y++)pixels.set(image.subarray(y*tile*4,(y+1)*tile*4),((row*tile+y)*width+i*tile)*4);
  }
  fs.writeFileSync(path.join(output,'comparison.png'),png(width,height,pixels));
  for(const [i,study] of studies.entries())for(let row=0;row<2;row++) {
    const image=render(tile,tile,row?study.mesh[1]:study.vanilla,textures[study.name],study.tint,.66,.48,true);
    for(let y=0;y<tile;y++)pixels.set(image.subarray(y*tile*4,(y+1)*tile*4),((row*tile+y)*width+i*tile)*4);
  }
  fs.writeFileSync(path.join(output,'canopy-comparison.png'),png(width,height,pixels));
  const html=`<!doctype html><html lang="en"><meta charset="utf-8"><title>Bushy Leaves Enhanced — model study</title>
<style>body{margin:0;padding:32px;background:#101c1b;color:#e4e9d9;font:16px system-ui}h1{font-weight:500;margin:0 0 8px}p{color:#a7b6a7;max-width:850px}main{display:grid;grid-template-columns:repeat(3,minmax(230px,1fr));gap:18px}article{background:#172725;border:1px solid #33473d;border-radius:12px;overflow:hidden}canvas{display:block;width:100%;aspect-ratio:1}h2{margin:12px 20px;font-size:17px;text-transform:capitalize}label{display:inline-flex;gap:8px;align-items:center;margin:12px 18px 24px 0}button{padding:8px 12px}input,select{accent-color:#b7d888}@media(max-width:800px){main{grid-template-columns:repeat(2,1fr)}}</style>
<h1>Bushy Leaves Enhanced</h1><p>Original flat foliage sprays. Compare silhouettes, rotate the view, and inspect a seven-block canopy. This software model study approximates alpha cutout and neighbour culling; Minecraft lighting, shaders and performance require in-game testing.</p>
<label>View <input id="angle" type="range" min="0" max="628" value="66"></label><label>Layout <select id="layout"><option value="0">Soft</option><option value="1">Wild</option><option value="2">Layered</option></select></label><label><input id="cluster" type="checkbox">Canopy</label><label><input id="vanilla" type="checkbox">Vanilla geometry</label><main></main>
<script>const studies=${JSON.stringify(studies)},textures=${JSON.stringify(textures)};${render.toString()}
const main=document.querySelector('main');for(const s of studies){const card=document.createElement('article');card.innerHTML='<h2>'+s.name.replaceAll('_',' ')+' · '+s.profile+'</h2><canvas width="420" height="420"></canvas>';main.append(card);s.canvas=card.querySelector('canvas');}
function draw(){for(const s of studies){const p=render(420,420,document.querySelector('#vanilla').checked?s.vanilla:s.mesh[+document.querySelector('#layout').value],textures[s.name],s.tint,+document.querySelector('#angle').value/100,.48,document.querySelector('#cluster').checked);s.canvas.getContext('2d').putImageData(new ImageData(p,420,420),0,0);}}document.querySelectorAll('input,select').forEach(e=>e.addEventListener('input',draw));draw();</script></html>`;
  fs.writeFileSync(path.join(output,'preview.html'),html);
  console.log(`Preview written to ${output}. PNG: vanilla above, bushy below; oak, birch, spruce, jungle, cherry, flowering azalea.`);
}
module.exports={mesh,render,png};
