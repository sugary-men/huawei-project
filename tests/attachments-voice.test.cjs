// Native kit boundaries are simulated; the actual ArkTS services run unchanged.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const nodeZlib = require('node:zlib');
const assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets/services');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'campuspilot-input-'));
const app = path.join(directory, 'app');
fs.mkdirSync(app);
const bufferOf = bytes => Uint8Array.from(bytes).buffer;
const crc32 = bytes => {
  let crc = 0xFFFFFFFF;
  for (const value of new Uint8Array(bytes)) {
    crc ^= value;
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xEDB88320 : 0);
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
};
const kits = {
  '@kit.AbilityKit': { abilityAccessCtrl: { createAtManager: () => ({ requestPermissionsFromUser: () => permission() }) } },
  '@kit.CoreFileKit': { fileIo: {
    accessSync: fs.existsSync, mkdirSync: fs.mkdirSync, unlinkSync: fs.unlinkSync,
    OpenMode: { READ_ONLY: 1, CREATE: 2, WRITE_ONLY: 4, TRUNC: 8 },
    open: async p => ({ fd: fs.openSync(p, 'r') }),
    openSync: (p, mode) => ({ fd: fs.openSync(p, mode === 1 ? 'r' : 'w') }),
    close: async file => fs.closeSync(file.fd), closeSync: file => fs.closeSync(file.fd),
    statSync: fs.fstatSync,
    copyFile: async (fd, destination) => fs.writeFileSync(destination, fs.readFileSync(fd)),
    readSync: (fd, buffer) => fs.readSync(fd, new Uint8Array(buffer)),
    writeSync: (fd, buffer) => fs.writeSync(fd, new Uint8Array(buffer))
  }, fileUri: { FileUri: class { constructor(p) { this.name = path.basename(p); } } }, picker: {} },
  '@kit.ArkTS': { util: { generateRandomUUID: crypto.randomUUID,
    TextDecoder: { create: encoding => ({ decodeToString: bytes => new TextDecoder(encoding).decode(bytes) }) },
    Base64Helper: class { encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); } }
  } },
  '@kit.BasicServicesKit': { zlib: {
    createZip: async () => ({ inflateInit2: async () => 0, inflateEnd: async () => 0,
      inflate: async stream => { const bytes = nodeZlib.inflateRawSync(Buffer.from(stream.nextIn));
        new Uint8Array(stream.nextOut).set(bytes); stream.totalOut = bytes.length; return 1; } }),
    createChecksum: async () => ({ crc32: async (_initial, bytes) => crc32(bytes) }),
    CompressFlushMode: { FINISH: 4 }, ReturnStatus: { STREAM_END: 1 }
  } },
  '@kit.MediaLibraryKit': { photoAccessHelper: {} },
  '@kit.ImageKit': { image: {} },
  '@kit.PDFKit': { pdfService: {} },
  '@kit.CoreSpeechKit': { speechRecognizer: {
    createEngine: async () => engine
  }, textToSpeech: {} }
};
const modules = new Map();
function load(name) {
  if (modules.has(name)) return modules.get(name);
  const exports = {};
  const source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2020 } }).outputText, { exports, ArrayBuffer, DataView, Uint8Array,
    setTimeout, clearTimeout, require: id => {
      if (kits[id]) return kits[id];
      if (id.startsWith('./')) return load(id.slice(2));
      throw Error(`Unexpected dependency ${id}`);
    } });
  modules.set(name, exports);
  return exports;
}
let permission = async () => ({ authResults: [0] });
let listener;
let voiceSession = '';
let starts = 0;
const engine = {
  setListener: value => { listener = value; },
  startListening: options => { starts++; voiceSession = options.sessionId;
    assert.equal(options.extraParams.recognitionMode, 0); queueMicrotask(() => listener.onStart(voiceSession, '')); },
  finish: id => queueMicrotask(() => { listener.onResult(id, { result: '识别结果', isLast: true, isFinal: true }); }),
  cancel: () => {}
};
function docxBytes(text) {
  const name = Buffer.from('word/document.xml');
  const xml = Buffer.from(`<w:document><w:body><w:p><w:r><w:t>${text}</w:t></w:r></w:p></w:body></w:document>`);
  const packed = nodeZlib.deflateRawSync(xml);
  const header = Buffer.alloc(30);
  header.writeUInt32LE(0x04034b50); header.writeUInt16LE(20, 4); header.writeUInt16LE(8, 8);
  header.writeUInt32LE(crc32(xml), 14); header.writeUInt32LE(packed.length, 18);
  header.writeUInt32LE(xml.length, 22); header.writeUInt16LE(name.length, 26);
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
  central.writeUInt16LE(8, 10); central.writeUInt32LE(crc32(xml), 16);
  central.writeUInt32LE(packed.length, 20); central.writeUInt32LE(xml.length, 24); central.writeUInt16LE(name.length, 28);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10);
  end.writeUInt32LE(central.length + name.length, 12); end.writeUInt32LE(header.length + name.length + packed.length, 16);
  return Buffer.concat([header, name, packed, central, name, end]);
}
(async () => {
  const { DocxTextService } = load('DocxTextService');
  assert.equal(await DocxTextService.extract(bufferOf(docxBytes('附件内容 &amp; 中文'))), '附件内容 & 中文');
  await assert.rejects(DocxTextService.extract(new ArrayBuffer(10)), /损坏/);
  const { AttachmentService } = load('AttachmentService');
  const original = path.join(directory, 'sample.txt');
  fs.writeFileSync(original, '文件测试 7Q42\n' + '字'.repeat(13000));
  const attachment = await AttachmentService.importUri({ filesDir: app }, original);
  assert.equal(attachment.text.length, 12000);
  assert.equal(attachment.truncated, true);
  assert.equal(fs.existsSync(attachment.path), true);
  assert.match(AttachmentService.content('请总结', [attachment]), /7Q42/);
  const docxPath = path.join(directory, 'sample.docx');
  fs.writeFileSync(docxPath, docxBytes('DOCX 正文'));
  const importedDocx = await AttachmentService.importUri({ filesDir: app }, docxPath);
  assert.equal(importedDocx.text, 'DOCX 正文');
  const imagePath = path.join(app, 'chat_attachments', 'image.jpg');
  fs.writeFileSync(imagePath, Buffer.from([1, 2, 3]));
  const image = { id: 'image', name: 'image.jpg', kind: 'image', mimeType: 'image/jpeg', path: imagePath, text: '', size: 3, truncated: false };
  const parts = AttachmentService.content('识图', [attachment, image]);
  assert.equal(parts[1].image_url.url, 'data:image/jpeg;base64,AQID');
  AttachmentService.removeDraft(attachment, app);
  assert.equal(fs.existsSync(attachment.path), false);
  assert.equal(fs.existsSync(original), true, 'removing a draft must never delete the selected source');
  const { HarmonyVoiceAdapter } = load('HarmonyVoiceAdapter');
  const voice = new HarmonyVoiceAdapter({});
  const results = [];
  await voice.start({ onPartial: value => results.push(value), onComplete: value => results.push('done:' + value), onError: value => results.push('error:' + value) });
  assert.equal(await voice.stop(), '识别结果');
  assert.deepEqual(results, ['识别结果', 'done:识别结果']);
  permission = async () => ({ authResults: [-1] });
  await assert.rejects(voice.start(), /权限/);
  let grant;
  permission = () => new Promise(resolve => { grant = resolve; });
  const pending = voice.start();
  await voice.cancel();
  grant({ authResults: [0] });
  await assert.rejects(pending, /取消/);
  assert.equal(starts, 1, 'cancel during permission request must not start the microphone afterwards');
  console.log('PASS: document import, DOCX inflate and CRC, truncation, multimodal payload, source preservation, ASR stop, denied permission, pending-start cancellation.');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  assert.equal(path.dirname(path.resolve(directory)), path.resolve(os.tmpdir()));
  assert.match(path.basename(directory), /^campuspilot-input-/);
  fs.rmSync(directory, { recursive: true, force: true });
});
