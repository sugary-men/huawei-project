const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const root = __dirname
const library = JSON.parse(fs.readFileSync(path.join(root, 'library.json'), 'utf8'))
const graph = JSON.parse(fs.readFileSync(path.join(root, 'knowledge-graph.json'), 'utf8'))
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'))

assert.equal(library.length, 12)
assert.equal(graph.nodes.filter(node => node.kind === 'chunk').length, 120)
assert.ok(graph.edges.length >= 120)
assert.equal(manifest.counts.knowledgeNodes, 120)
for (const file of manifest.files.filter(name => name.endsWith('.png'))) {
  const bytes = fs.readFileSync(path.join(root, file))
  assert.deepEqual(Array.from(bytes.subarray(0, 8)), [137, 80, 78, 71, 13, 10, 26, 10])
}
console.log('PASS: offline fixtures contain 12 documents, 120 graph nodes, edges and valid PNG images.')
