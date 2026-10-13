'use strict';

// Deterministic simulation only. No OS calls, networking or installations.
class QuickPreview {
  static tasks = ['DefenderSecure', 'Install', 'Windows', 'Drivers'];
  constructor(scenario = 'success', optionalDrivers = false) {
    this.scenario = scenario;
    this.optionalDrivers = optionalDrivers;
    this.stage = 0;
    this.status = 'Running';
    this.restartUsed = false;
    this.results = {};
  }
  next() { return this.status === 'Running' ? QuickPreview.tasks[this.stage] : null; }
  complete(task) {
    if (task !== this.next()) throw new Error('Unexpected simulated task');
    let outcome = 'Done', message = 'DoneMessage';
    if (this.scenario === 'failure' && task === 'Install') {
      outcome = 'Attention'; message = 'FailedMessage';
    } else if (this.scenario === 'restart' && task === 'Windows' && !this.restartUsed) {
      outcome = 'RestartNeeded'; message = 'RestartMessage';
      this.restartUsed = true;
      this.status = 'AwaitingRestart';
    } else if (task === 'Drivers') {
      message = this.optionalDrivers ? 'OptionalDriverMessage' : 'RecommendedDriverMessage';
    }
    const result = { task, outcome, message };
    this.results[task] = result;
    if (outcome !== 'RestartNeeded') {
      this.stage++;
      if (this.stage === QuickPreview.tasks.length) this.status = 'Complete';
    }
    return result;
  }
  resume() {
    if (this.status !== 'AwaitingRestart') throw new Error('No simulated restart is pending');
    this.status = 'Running';
  }
  hasAttention() { return Object.values(this.results).some(r => r.outcome !== 'Done'); }
}
if (typeof module !== 'undefined') module.exports = QuickPreview;
