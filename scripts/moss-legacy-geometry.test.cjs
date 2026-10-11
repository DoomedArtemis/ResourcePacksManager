const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { png, rectangles, cropped } = require('./moss-legacy-geometry.cjs');

test('transparent pixels produce holes rather than opaque rectangular faces', () => {
  const image = {width:16, opacity:(x,y) => x >= 4 && x < 7 && y >= 12 && y < 16 ? 255 : 0};
  assert.deepEqual(rectangles(image,[0,0,16,16],0),[[4,12,7,16]]);
  assert.deepEqual(rectangles(image,[16,16,0,0],0),[[4,12,7,16]]);
  assert.deepEqual(rectangles(image,[0,0,3,3],0),[]);
});

test('separate foliage islands remain separate', () => {
  const image = {width:16, opacity:(x,y) => y === 3 && (x === 2 || x === 4) ? 255 : 0};
  assert.deepEqual(rectangles(image,[0,0,16,16],0),[[2,3,3,4],[4,3,5,4]]);
});

test('cropping maps north-facing texture pixels onto the matching geometry', () => {
  const element = {from:[0,0,-0.026],to:[16,16,-0.026],faces:{north:{texture:'#flowers',cullface:'north'}}};
  const result = cropped(element,'north',element.faces.north,[4,12,7,16],[0,0,16,16]);
  assert.deepEqual(result.from,[9,0,-0.026]);
  assert.deepEqual(result.to,[12,4,-0.026]);
  assert.equal(result.faces.north.cullface,'north');
  assert.deepEqual(result.faces.north.uv,[4,12,7,16]);
  assert.deepEqual(element.from,[0,0,-0.026]);
});

test('flipped underside UVs and element rotations preserve hanging orientation', () => {
  const element = {from:[0,16,0],to:[16,16,16],rotation:{axis:'x',angle:22.5,origin:[8,16,8]},faces:{down:{texture:'#flowers'}}};
  const result = cropped(element,'down',element.faces.down,[4,12,7,16],[0,16,16,0]);
  assert.deepEqual(result.from,[4,16,12]);
  assert.deepEqual(result.to,[7,16,16]);
  assert.deepEqual(result.faces.down.uv,[4,16,7,12]);
  assert.deepEqual(result.rotation,element.rotation);
});

test('a cropped cube face stays on the cube surface', () => {
  const element = {from:[0,0,0],to:[16,16,16],faces:{south:{texture:'#flowers'}}};
  const result = cropped(element,'south',element.faces.south,[4,12,7,16],[0,0,16,16]);
  assert.deepEqual(result.from,[4,0,16]);
  assert.deepEqual(result.to,[7,4,16]);
});

const independentMasks = path.resolve(__dirname,'../cache/transparency/png-stats.json');
test('PNG masks agree with independent Windows decoding', {skip:!fs.existsSync(independentMasks)}, () => {
  for (const expected of JSON.parse(fs.readFileSync(independentMasks,'utf8'))) {
    const image = png(expected.file);
    assert.equal(image.width,expected.width);
    assert.equal(image.height,expected.height);
    let opaque=0, transparent=0;
    for (let y=0;y<image.height;y++) for (let x=0;x<image.width;x++) {
      if (image.opacity(x,y)>=128) opaque++; else transparent++;
    }
    assert.equal(opaque,expected.opaque,expected.file);
    assert.equal(transparent,expected.transparent,expected.file);
  }
});
