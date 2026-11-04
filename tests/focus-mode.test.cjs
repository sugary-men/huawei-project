// Run with Node and the TypeScript compiler bundled with DevEco Studio.
// node tests/focus-mode.test.cjs <path-to-typescript.js>
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services/FocusModeManager.ets'), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS,
  target: ts.ScriptTarget.ES2020 } }).outputText;
const protocolSource = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services/FocusProtocol.ets'), 'utf8');
const protocolCompiled = ts.transpileModule(protocolSource, { compilerOptions: { module: ts.ModuleKind.CommonJS,
  target: ts.ScriptTarget.ES2020 } }).outputText;
let now = 1700000000000;
class TestDate extends Date { static now() { return now; } }
const moduleExports = {};
vm.runInNewContext(compiled, {
  exports: moduleExports,
  Date: TestDate,
  require: name => {
    if (name === '../models/FocusModels') return {};
    throw Error(`Unexpected runtime dependency: ${name}`);
  }
});
const protocolExports = {};
vm.runInNewContext(protocolCompiled, { exports: protocolExports, Date: TestDate });
const protocol = protocolExports.FocusProtocol;
assert.equal(protocol.parse('{"pitch":2.5,"roll":-1.2}').pitch, 2.5);
assert.equal(protocol.parse('3.1,-4.2,0').roll, -4.2);
assert.equal(protocol.isStable(protocol.parse('4,5')), true);
assert.equal(protocol.isStable(protocol.parse('30,5')), false);
assert.equal(protocol.parse('not-a-sample'), undefined);
const manager = new moduleExports.FocusModeManager();
assert.equal(manager.snapshot().phase, 'idle');
manager.connect({ id: 'cube-1', name: 'CampusCube', rssi: -42, source: 'ble' });
assert.equal(manager.snapshot().phase, 'ready');
manager.ingestOrientation(3, 2);
const autoSnapshot = manager.snapshot();
assert.equal(autoSnapshot.phase, 'focusing', 'a steady cube must auto-start focus');
assert.equal(autoSnapshot.lastTrigger, 'ble-steady');
now += 1000;
manager.stop('用户结束专注');
manager.connect({ id: 'cube-1', name: 'CampusCube', rssi: -42, source: 'ble' });
manager.start(25, 'ble-steady');
let snapshot = manager.snapshot();
assert.equal(snapshot.phase, 'focusing');
assert.equal(snapshot.screenLockLinked, true);
assert.equal(snapshot.durationMinutes, 25);
manager.ingestOrientation(4, 3);
assert.equal(manager.snapshot().phase, 'focusing', 'small gyro noise must not interrupt focus');
manager.ingestOrientation(44, 12);
snapshot = manager.snapshot();
assert.equal(snapshot.phase, 'interrupted');
assert.match(snapshot.interruptionReason, /姿态变化/);
assert.equal(snapshot.screenLockLinked, false);
now += 60000;
manager.nfcTap('AA:BB:CC');
snapshot = manager.snapshot();
assert.equal(snapshot.phase, 'focusing');
assert.equal(snapshot.lastTrigger, 'nfc');
assert.equal(snapshot.deviceName, 'NFC 专注标签');
now += 25 * 60 * 1000;
assert.equal(manager.refresh().phase, 'completed', 'expired focus sessions must complete automatically');
assert.equal(manager.snapshot().screenLockLinked, false);
console.log('PASS: BLE sample parsing, steady auto-start, NFC trigger, gyro interruption, timing, completion and lock-link state.');

