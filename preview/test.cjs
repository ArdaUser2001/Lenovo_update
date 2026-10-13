'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const QuickPreview = require('./flow.js');

for (const scenario of ['success', 'failure', 'restart']) {
  const run = new QuickPreview(scenario, true);
  const calls = [];
  while (run.status !== 'Complete') {
    if (run.status === 'AwaitingRestart') {
      assert.equal(run.next(), null, 'No task may run before the simulated reboot');
      assert.throws(() => run.complete('Windows'));
      run.resume();
    }
    const task = run.next(); calls.push(task); run.complete(task);
  }
  assert.equal(calls.filter(t => t === 'DefenderSecure').length, 1);
  assert.equal(calls.filter(t => t === 'Install').length, 1);
  assert.equal(calls.filter(t => t === 'Windows').length, scenario === 'restart' ? 2 : 1);
  assert.equal(calls.filter(t => t === 'Drivers').length, 1);
  assert.equal(run.hasAttention(), scenario === 'failure');
  assert.equal(run.results.Drivers.message, 'OptionalDriverMessage');
  assert.equal(run.next(), null);
  assert.throws(() => run.resume());
}
const recommended = new QuickPreview();
for (const task of QuickPreview.tasks) recommended.complete(task);
assert.equal(recommended.results.Drivers.message, 'RecommendedDriverMessage');

const context = {}; vm.createContext(context);
vm.runInContext(fs.readFileSync(__dirname + '/data.js', 'utf8') + '; globalThis.data = DATA;', context);
for (const lang of ['de', 'en']) {
  const data = context.data;
  assert.equal(data.steps[lang].length, 8);
  assert.equal(data.steps[lang][0].Actions[0].Id, 'QuickRun');
  assert.equal(data.steps[lang][0].Text, data.quick[lang].Instructions);
  assert.equal(data.ui[lang].StepIntro1, data.quick[lang].Intro);
  assert.ok(data.ui[lang].Footer.includes('1.3'));
  for (const key of ['Confirmation', 'Optional', 'Results', 'Finished', 'NeedsAttention']) assert.ok(data.quick[lang][key]);
}
console.log('PASS: successful and failed runs, restart continuation, optional drivers and bilingual version 1.3 data.');
