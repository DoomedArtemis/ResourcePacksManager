// Original pixel artwork, drawn separately at each crystal face's native size.
// One texel per model unit matches a vanilla 16x16 texture on a full block.
// The 32px canvas holds all six unfolded faces; it does not increase density.
const atlasSize = 32;
const texelsPerUnit = 1;
const palettes = {
  coal: ['#101217','#191d23','#272d34','#37404a','#505c66','#75828a'],
  iron: ['#393531','#625950','#8d8172','#b7a693','#d7c6ad','#f1e4ce'],
  copper: ['#48261f','#743b29','#a75835','#cf7f4c','#e9aa71','#ffe0ac'],
  exposed_copper: ['#493229','#715039','#9d7350','#bf956c','#d6b792','#e9d4b3'],
  weathered_copper: ['#1f4034','#345e4b','#4d8163','#74a17e','#a0c3a1','#d1dfc1'],
  oxidized_copper: ['#1c4542','#2b6860','#438e80','#68b39c','#9ed1b7','#d3e8d1'],
  gold: ['#66401b','#92601b','#c18b26','#dfb33e','#f1d474','#fff0bc'],
  redstone: ['#350c18','#641326','#982039','#c53447','#e45961','#ffac9e'],
  lapis: ['#101a42','#172d65','#244789','#3864ac','#5784c8','#9cbbeb'],
  diamond: ['#1c5664','#327e8b','#63adb5','#91cbd0','#c3e8e5','#effbf4'],
  emerald: ['#09342a','#115637','#24814f','#45ad70','#83d49e','#d3eed6'],
  quartz: ['#5e656a','#92999a','#bdc3c0','#d9ddd3','#eeeee2','#fffaf0'],
  debris: ['#29211f','#45332b','#665044','#8c6f59','#b19376','#d2b79a']
};
const rgb = hex => [1,3,5].map(i => parseInt(hex.slice(i,i+2),16));
function surfacePoint(dir,u,v) {
  return {south:[u,1-v,1],north:[1-u,1-v,0],west:[0,1-v,u],east:[1,1-v,1-u],up:[u,1,v],down:[u,0,1-v]}[dir];
}
function surfaceColor(mineral,kind,point) {
  const material=mineral.includes('copper')?'copper':mineral;
  const [x,y,z]=point,normal=[0,0,0],bevel=kind===0?.2:.16;
  for(let axis=0;axis<3;axis++) {
    if(point[axis]<bevel) normal[axis]-=1-point[axis]/bevel;
    if(point[axis]>1-bevel) normal[axis]+=1-(1-point[axis])/bevel;
  }
  const length=Math.hypot(...normal);
  const n=normal.map(v=>v/length),key=Math.max(0,-.52*n[0]+.76*n[1]+.39*n[2]);
  const bounce=Math.max(0,-.2*n[0]-.5*n[1]-.6*n[2]);
  // One light direction and one shared bevel field for the entire folded solid.
  let tone=.22+key*.43+bounce*.1+y*.035;
  const phase=kind===0?.03:-.04;
  const plane=x*.65+y*.2+z*.35;
  if(['diamond','emerald','redstone'].includes(mineral)) {
    tone+=plane<.65+phase?.08:-.055;
    if(mineral==='diamond'&&Math.abs(plane-.65-phase)<.075) tone+=.09;
    if(mineral==='emerald'&&x>.25&&x<.75&&z>.25&&z<.75) tone+=.045;
  } else if(mineral==='coal') {
    tone-=.05;
    if(Math.abs(x*.4+y*.3+z*.2-.42-phase)<.06) tone-=.14;
  } else if(mineral==='lapis') {
    tone-=.015;
    if(x*.3+y*.4+z*.2>.55+phase) tone-=.085;
  } else if(mineral==='debris') {
    const band=y+Math.abs(x-.5)*.18+z*.12;
    if(band>.35+phase&&band<.57+phase) tone+=.13;
    else if(band<.35+phase) tone-=.06;
  } else if(mineral==='quartz') {
    tone+=.14;
    if(Math.abs(x*.75+z*.2-.5-phase)<.075) tone-=.07;
  } else if(mineral==='iron') {
    if(x*.6+y*.25+z*.2<.3+phase) tone-=.1;
    if(Math.abs(x*.75+z*.45+y*.2-.72-phase)<.065) tone+=.07;
  } else if(mineral==='gold') {
    if(y>.3&&key>.25&&Math.abs(x*.6+z*.3-y*.25-.28-phase)<.09) tone+=.15;
  }
  // A restrained highlight wraps the upper front-left corner instead of being
  // stamped independently on all six faces. Opposite faces stay darker.
  const distance=Math.hypot(x,y-1,z-1);
  const polish={coal:.09,iron:.16,copper:.22,gold:.3,redstone:.2,lapis:.12,diamond:.28,emerald:.23,quartz:.14,debris:.08}[material];
  if(distance<.45) tone+=polish*(1-distance/.45);
  const palette=palettes[mineral].map(rgb);
  const level=Math.max(0,Math.min(1,Math.round(tone*24)/24))*(palette.length-1);
  const low=Math.floor(level),high=Math.min(palette.length-1,low+1),fraction=level-low;
  let color=palette[low].map((value,i)=>Math.round(value+(palette[high][i]-value)*fraction));
  if(mineral==='exposed_copper') {
    const weight=Math.max(0,Math.min(1,(x*.3+(1-y)*.7+z*.2-.78-phase)/.28));
    const patina=tone>.42?[97,140,105]:[43,81,61];
    color=color.map((value,i)=>Math.round(value+(patina[i]-value)*weight));
  } else if(mineral==='weathered_copper') {
    const residual=Math.max(0,Math.min(1,(.27+phase-x*.3-(1-y)*.7-z*.2)/.22));
    const brown=tone>.42?[174,139,91]:[105,76,48];
    color=color.map((value,i)=>Math.round(value+(brown[i]-value)*residual));
  }
  return color;
}
function paint(mineral,width,height,kind,dir) {
  const pixels=Buffer.alloc(width*height*4);
  for(let y=0;y<height;y++) for(let x=0;x<width;x++) {
    pixels.set([...surfaceColor(mineral,kind,surfacePoint(dir,x/(width-1),y/(height-1))),255],(y*width+x)*4);
  }
  // Remove accidental single-pixel islands at narrow facet intersections.
  for(let pass=0;pass<4;pass++) {
    const source=Buffer.from(pixels);let changed=0;
    for(let y=1;y<height-1;y++) for(let x=1;x<width-1;x++) {
      const at=(u,v)=>source.subarray((v*width+u)*4,(v*width+u)*4+3);
      const center=at(x,y),neighbors=[at(x-1,y),at(x+1,y),at(x,y-1),at(x,y+1)];
      const differences=neighbors.map(pixel=>Math.hypot(...Array.from(pixel,(value,i)=>value-center[i])));
      if(differences.every(distance=>distance>28)) {
        neighbors[differences.indexOf(Math.min(...differences))].copy(pixels,(y*width+x)*4);changed++;
      }
    }
    if(!changed) break;
  }
  return pixels;
}
function fitFaces(model) {
  const patches=[];
  for(const [piece,el] of model.elements.entries()) {
    if(el.name==='plain_rock_core') continue;
    const dimensions=el.from.map((n,i)=>el.to[i]-n);
    const [w,h,d]=dimensions.map(n=>Math.max(2,Math.round(n*texelsPerUnit)));
    const originX=Math.floor((atlasSize-2*w-2*d)/2),originY=Math.floor((atlasSize-h-2*d)/2);
    if(originX<0||originY<0) throw new Error('Crystal net does not fit the texture');
    // A connected cuboid net, viewed from outside: front is south. Every shared
    // edge joins the same 3D edge when folded, using Minecraft's standard UVs.
    const slots={
      up:[originX+d,originY,w,d],down:[originX+d,originY+d+h,w,d],
      west:[originX,originY+d,d,h],south:[originX+d,originY+d,w,h],
      east:[originX+d+w,originY+d,d,h],north:[originX+2*d+w,originY+d,w,h]
    };
    for(const [faceIndex,[dir,face]] of Object.entries(el.faces).entries()) {
      const [x,y,width,height]=slots[dir];
      const uv=[x,y,x+width,y+height].map(n=>n*16/atlasSize);
      face.uv=uv;
      patches.push({x,y,width,height,piece,faceIndex,dir});
    }
  }
  return patches;
}
function atlas(mineral,variant,patches) {
  // Transparent unused canvas makes the connected six-face net easy to see.
  const pixels=Buffer.alloc(atlasSize*atlasSize*4);
  for(const patch of patches) {
    const art=paint(mineral,patch.width,patch.height,variant,patch.dir);
    for(let y=0;y<patch.height;y++) art.copy(pixels,((patch.y+y)*atlasSize+patch.x)*4,y*patch.width*4,(y+1)*patch.width*4);
  }
  return {width:atlasSize,height:atlasSize,pixels};
}
module.exports={atlasSize,texelsPerUnit,fitFaces,atlas,surfacePoint};
