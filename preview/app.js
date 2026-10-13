'use strict';

// Session state stays in memory. Reloading the page resets the entire preview.
// DATA comes from data.js, which build.py generates from the Windows app.
const $ = id => document.getElementById(id);
let language = 'de', index = 0, scanned = false, running = false;
let renderedStep = -1;
let quick = null, activeTask = null, workTimer = null, restartTimer = null;
let restartSeconds = 0;
const previewText = {
  de: {
    PreviewNotice: 'macOS-Entwurf 1.3 · Alle Updates und Neustarts werden nur simuliert.',
    ScenarioLabel: 'Ergebnis ausprobieren:', ScenarioSuccess: 'Alles erfolgreich',
    ScenarioRestart: 'Neustart erforderlich', ScenarioFailure: 'Ein Programmupdate schlägt fehl',
    ResetPreview: 'Entwurf zurücksetzen', PreviewStart: 'Simulation starten', Cancel: 'Abbrechen',
    DoneMessage: 'In diesem Entwurf erfolgreich simuliert.',
    FailedMessage: 'Beispiel: Ein Programm konnte nicht aktualisiert werden. Die übrigen Aufgaben werden fortgesetzt.',
    RestartMessage: 'Windows benötigt in diesem Beispiel einen Neustart. Der Entwurf startet Ihren Mac nicht neu.',
    RecommendedDriverMessage: 'Empfohlene Treiber simuliert. Optionale Treiber und Firmware bleiben separat.',
    OptionalDriverMessage: 'Empfohlene und eindeutig passende optionale Treiber simuliert. Firmware bleibt separat.',
    PreviewCountdown: 'Simulierter Neustart in {0} Sekunden. Im Windows-Assistenten beträgt der Countdown 120 Sekunden.',
    PreviewPostponed: 'Der simulierte Neustart ist verschoben. Mit «Neustart simulieren und fortsetzen» geht es hier weiter.',
    RestartPreview: 'Neustart simulieren und fortsetzen',
    PreviewResume: 'Simulierter Neustart abgeschlossen. Der gespeicherte Durchlauf geht weiter.',
    ConfirmationNote: 'Dies ist ein Mac-Entwurf: Es werden keine Programme installiert und keine Einstellungen verändert.',
    PreviewSummary: 'Ergebnisse der Simulation', PreviewNext: 'Lesen Sie die einzelnen Ergebnisse. Danach können Sie Store-Apps und Lenovo prüfen.',
  },
  en: {
    PreviewNotice: 'macOS draft 1.3 · All updates and restarts are simulated.',
    ScenarioLabel: 'Try a result:', ScenarioSuccess: 'Everything succeeds',
    ScenarioRestart: 'Restart required', ScenarioFailure: 'One application update fails',
    ResetPreview: 'Reset draft', PreviewStart: 'Start simulation', Cancel: 'Cancel',
    DoneMessage: 'Successfully simulated in this draft.',
    FailedMessage: 'Example: One application could not be updated. The other tasks continue.',
    RestartMessage: 'Windows needs a restart in this example. The draft does not restart your Mac.',
    RecommendedDriverMessage: 'Recommended drivers simulated. Optional drivers and firmware remain separate.',
    OptionalDriverMessage: 'Recommended and unambiguous optional drivers simulated. Firmware remains separate.',
    PreviewCountdown: 'Simulated restart in {0} seconds. The Windows assistant uses a 120-second countdown.',
    PreviewPostponed: 'The simulated restart is postponed. Use “Simulate restart and continue” to proceed here.',
    RestartPreview: 'Simulate restart and continue',
    PreviewResume: 'Simulated restart complete. Your saved run is continuing.',
    ConfirmationNote: 'This is a Mac draft: No applications are installed and no settings are changed.',
    PreviewSummary: 'Simulation results', PreviewNext: 'Review each result. Then you can check Store apps and Lenovo.',
  },
};
const states = Array(8).fill('StateOpen');
const messages = Array(8).fill('NotEdited');
const logs = Array(8).fill('');

// Store translation keys rather than translated text so language changes are immediate.
const t = key => previewText[language][key] || DATA.quick[language][key] || DATA.ui[language][key] || key;
const completed = i => ['StateAuto', 'StateUserConfirmed'].includes(states[i]);

// Geometry comes from the same Icons.xaml resources used by the Windows UI.
const actionIcons = {
  QuickRun: 'IconRefresh', DefenderSecure: 'IconShield', Drivers: 'IconDevice',
  Windows: 'IconRefresh', Scan: 'IconSearch', Install: 'IconDownload',
  Defender: 'IconShield', Security: 'IconShield', Store: 'IconApps', Apps: 'IconApps',
  LenovoVantage: 'IconDownload', LenovoSystemUpdate: 'IconDownload',
  Vantage: 'IconDevice', SystemUpdate: 'IconDevice',
};
function addButtonIcon(button, key) {
  const text = button.textContent;
  const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  icon.setAttribute('viewBox', '0 0 24 24');
  icon.setAttribute('class', 'button-icon');
  icon.setAttribute('aria-hidden', 'true');
  icon.setAttribute('focusable', 'false');
  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  path.setAttribute('d', DATA.icons[key]);
  icon.append(path);
  const label = document.createElement('span');
  label.textContent = text;
  button.replaceChildren(icon, label);
  button.setAttribute('aria-label', text);
}

// Shared dialog for usage help and the session summary.
function showDialog(title, body) {
  $('dialogTitle').textContent = title;
  $('dialogBody').textContent = body;
  $('dialog').showModal();
}

function summary() {
  showDialog(
    t('Summary') + ' · Preview',
    DATA.steps[language].map((s, i) => `${s.Title}: ${t(states[i])}`).join('\n')
      + (quick ? '\n\n' + t('Results') + '\n' + quickSummary() : '')
  );
}

// Rebuild the view from session state; this function never runs update actions.
function render() {
  document.documentElement.lang = language;
  document.title = t('WindowTitle') + ' · macOS Draft';
  renderQuickPreview();
  document.querySelectorAll('[data-text]').forEach(el => el.textContent = t(el.dataset.text));

  // Step heading, instructions and overall completion count.
  const step = DATA.steps[language][index];
  if (renderedStep !== index) {
    ['instructions', 'alternatives', 'technical'].forEach(id => $(id).open = false);
    setOverview(false);
    renderedStep = index;
    document.querySelector('.body').scrollTop = 0;
  }
  $('intro').textContent = t(`StepIntro${index + 1}`);
  $('title').textContent = step.Title.replace(/^\d+ · /, '');
  $('description').textContent = step.Text;
  $('counter').textContent = t('SectionCounter').replace('{0}', index + 1);
  $('progressText').textContent = t('DoneProgress').replace(
    '{0}', states.filter((_, i) => completed(i)).length
  );
  $('progress').value = states.filter((_, i) => completed(i)).length;

  // Navigation displays every step's status. Selecting a step does not complete it.
  $('navigation').replaceChildren(...DATA.steps[language].map((s, i) => {
    const button = document.createElement('button');
    const number = document.createElement('span');
    number.className = 'step-number';
    number.textContent = i + 1;
    const title = document.createElement('span');
    title.className = 'step-label';
    title.textContent = s.Title.replace(/^\d+ · /, '');
    button.append(number, title);
    button.dataset.complete = completed(i);
    button.disabled = running;
    const status = document.createElement('small');
    status.textContent = t(states[i]);
    title.append(status);
    if (i === index) button.setAttribute('aria-current', 'step');
    button.onclick = () => {
      index = i;
      setOverview(false);
      render();
      $('title').focus();
    };
    return button;
  }));

  // The install action becomes available only after the simulated program scan.
  $('actions').replaceChildren();
  $('additionalActions').replaceChildren();
  step.Actions.forEach((action, i) => {
    const button = document.createElement('button');
    button.textContent = action.Id === 'QuickRun' && quick?.status === 'AwaitingRestart' ? t('Continue') : action.Label;
    addButtonIcon(button, actionIcons[action.Id] || 'IconExternal');
    button.className = (index === 3 && scanned ? action.Id === 'Install' : i === 0)
      ? 'primary'
      : '';
    const unfinished = quick && quick.status !== 'Complete';
    const separateWorker = ['Windows', 'Scan', 'Install', 'Defender', 'LenovoVantage', 'LenovoSystemUpdate'].includes(action.Id);
    button.disabled = running || (action.Id === 'Install' && !scanned)
      || (unfinished && separateWorker) || (action.Id === 'QuickRun' && quick?.status === 'AwaitingRestart');
    button.onclick = () => simulate(action);
    const container = button.className === 'primary' || index === 3
      ? $('actions') : $('additionalActions');
    container.append(button);
  });
  $('alternatives').hidden = !$('additionalActions').children.length;

  // Status, next-action guidance and optional manual confirmation.
  $('status').textContent = t(messages[index]);
  $('statusPanel').dataset.state = states[index];
  $('hint').textContent = t(
    completed(index) ? 'HintCompleted'
      : states[index] === 'StateScanned' ? 'HintScanned'
        : step.Manual ? 'HintManual'
          : 'HintAutomatic'
  );
  if (index === 0 && quick) {
    $('hint').textContent = quick.status === 'Complete' ? t('PreviewNext')
      : quick.status === 'AwaitingRestart' ? (restartTimer ? t('PreviewCountdown').replace('{0}', restartSeconds) : t('PreviewPostponed'))
        : t(activeTask) + ': ' + t('Busy');
  }
  $('log').textContent = logs[index] || 'macOS UI Preview — simulated actions only.';
  $('confirmation').hidden = !step.Manual;
  $('confirm').checked = states[index] === 'StateUserConfirmed';
  $('confirm').disabled = running;
  $('busy').hidden = states[index] !== 'StateRunning';
  $('back').disabled = running || index === 0;
  $('next').disabled = running;
  $('overviewButton').disabled = running;
  if (running) setOverview(false);
  $('overviewButton').setAttribute('aria-label', `${$('counter').textContent}. ${$('progressText').textContent}. ${t('ProgressLabel')}`);
  $('next').className = completed(index) || index === 7 ? 'primary' : '';
  $('next').textContent = t(
    index === 7 ? 'Summary' : completed(index) ? 'NextStep' : 'ContinueOpen'
  );
  [['back', 'IconArrowLeft'], ['next', 'IconArrowRight'], ['guide', 'IconDocument'],
    ['help', 'IconHelp'], ['report', 'IconDocument']].forEach(([id, key]) => addButtonIcon($(id), key));
}

// Mimic asynchronous work with a short timer. No Windows command is executed.
function simulate(action) {
  if (running) return;
  if (action.Id === 'QuickRun') { confirmQuickStart(); return; }
  // Capture the originating step while the simulated worker is running.
  const target = index;
  running = true;
  states[target] = 'StateRunning';
  messages[target] = 'RunningMessage';
  logs[target] += `\n[Preview] ${action.Label}`;
  render();

  workTimer = setTimeout(() => {
    running = false;
    if (action.Id === 'Scan') {
      scanned = true;
      states[target] = 'StateScanned';
      messages[target] = 'HintScanned';
    } else if (['Windows', 'Install', 'Defender'].includes(action.Id)) {
      states[target] = 'StateAuto';
      messages[target] = 'HintCompleted';
    } else {
      states[target] = completed(target) ? states[target] : 'StateOpen';
      messages[target] = 'HintManual';
    }
    logs[target] += '\n[Preview] Simulation complete. No system changes made.';
    render();
  }, 900);
}

// The overview is navigation only; opening it never changes completion state.
function setOverview(open) {
  $('stepOverview').hidden = !open;
  $('overviewButton').setAttribute('aria-expanded', String(open));
}
$('overviewButton').onclick = () => {
  if (running) return;
  const open = $('stepOverview').hidden;
  setOverview(open);
  if (open) $('navigation').children[index].focus();
};
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && !$('stepOverview').hidden) {
    setOverview(false);
    $('overviewButton').focus();
  }
});
document.addEventListener('click', event => {
  if (!$('taskFooter').contains(event.target)) setOverview(false);
});

// Bind the static controls once; render() handles dynamically created step buttons.
$('language').onchange = event => {
  language = event.target.value;
  render();
};

$('confirm').onchange = event => {
  states[index] = event.target.checked ? 'StateUserConfirmed' : 'StateOpen';
  messages[index] = event.target.checked ? 'ManualConfirmed' : 'NotConfirmed';
  render();
};

$('back').onclick = () => {
  if (index > 0) index--;
  render();
};

$('next').onclick = () => {
  if (index === 7) summary();
  else {
    index++;
    render();
  }
};

$('help').onclick = () => showDialog(t('HelpTitle'), t('HelpDialog'));
$('report').onclick = summary;



function quickSummary() {
  return QuickPreview.tasks.map(task => {
    const r = quick.results[task];
    const state = activeTask === task ? 'Running' : r ? ({Done: 'Done', Attention: 'Attention', RestartNeeded: 'Restart'}[r.outcome]) : 'Waiting';
    return `${t(task)}: ${t(state)}${r ? '\n' + t(r.message) : ''}`;
  }).join('\n\n');
}
function renderQuickPreview() {
  for (const [id, key] of Object.entries({
    previewNotice: 'PreviewNotice', scenarioLabel: 'ScenarioLabel', scenarioSuccess: 'ScenarioSuccess',
    scenarioRestart: 'ScenarioRestart', scenarioFailure: 'ScenarioFailure', resetPreview: 'ResetPreview',
    optionalLabel: 'Optional', optionalHelp: 'OptionalHelp', resultsTitle: 'Results',
    postponeRestart: 'CancelRestart', restartPreview: 'RestartPreview',
  })) $(id).textContent = t(key);
  $('scenario').disabled = running || (quick && quick.status !== 'Complete');
  $('quickOptions').hidden = index !== 0;
  $('optionalDrivers').disabled = running || (quick && quick.status !== 'Complete');
  $('quickResults').hidden = index !== 0 || !quick;
  $('postponeRestart').hidden = index !== 0 || !restartTimer;
  $('restartPreview').hidden = index !== 0 || quick?.status !== 'AwaitingRestart' || !!restartTimer;
  if (!quick) return;
  $('resultRows').replaceChildren(...QuickPreview.tasks.map(task => {
    const r = quick.results[task];
    const state = activeTask === task ? 'Running' : r ? ({Done:'Done',Attention:'Attention',RestartNeeded:'Restart'}[r.outcome]) : 'Waiting';
    const row = document.createElement('div');
    row.className = 'result-row'; row.dataset.outcome = state; row.dataset.task = task;
    const heading = document.createElement('strong');
    heading.textContent = t(task);
    const badge = document.createElement('span');
    badge.className = 'result-state'; badge.textContent = t(state);
    const message = document.createElement('p');
    message.textContent = r ? t(r.message) : '';
    row.append(heading, badge, message);
    return row;
  }));
}
function confirmQuickStart() {
  if (running || quick?.status === 'AwaitingRestart') return;
  $('startTitle').textContent = t('Title');
  $('startBody').textContent = t('ConfirmationNote') + '\n\n' + t('Confirmation');
  $('confirmStart').textContent = t('PreviewStart');
  $('cancelStart').textContent = t('Cancel');
  $('confirmStart').onclick = () => {
    $('startDialog').close();
    quick = new QuickPreview($('scenario').value, $('optionalDrivers').checked);
    [0, 1, 3, 5].forEach(i => { states[i] = 'StateOpen'; messages[i] = 'NotEdited'; logs[i] = ''; });
    index = 0;
    runQuickTask();
  };
  $('cancelStart').onclick = () => $('startDialog').close();
  $('startDialog').showModal();
}
function runQuickTask() {
  const task = quick.next();
  if (!task) return;
  running = true; activeTask = task;
  states[0] = 'StateRunning'; messages[0] = 'RunningMessage';
  logs[0] += `\n[Preview] ${task}`;
  render();
  workTimer = setTimeout(() => {
    workTimer = null;
    const result = quick.complete(task);
    activeTask = null;
    const target = {DefenderSecure:5, Install:3, Windows:0, Drivers:1}[task];
    if (target !== 0) {
      states[target] = result.outcome === 'Done' ? 'StateAuto' : 'StateCheck';
      messages[target] = result.message;
      logs[target] = `[Preview] ${task}: ${result.outcome}`;
    }
    logs[0] += `\n[Preview] ${task}: ${result.outcome}`;
    if (quick.status === 'AwaitingRestart') {
      states[0] = 'StateRestart'; messages[0] = 'RestartMessage';
      restartSeconds = 6;
      restartTimer = setInterval(() => {
        restartSeconds--;
        if (restartSeconds <= 0) restartSimulation();
        else render();
      }, 1000);
      render();
    } else if (quick.status === 'Complete') {
      running = false;
      states[0] = quick.hasAttention() ? 'StateCheck' : 'StateAuto';
      messages[0] = quick.hasAttention() ? 'NeedsAttention' : 'Finished';
      render();
      $('quickResults').scrollIntoView({block: 'nearest'});
    } else runQuickTask();
  }, 900);
}
function restartSimulation() {
  if (quick?.status !== 'AwaitingRestart') return;
  clearInterval(restartTimer); restartTimer = null;
  quick.resume(); index = 0;
  messages[0] = 'PreviewResume';
  logs[0] += '\n[Preview] Restart simulated; earlier stages retained.';
  runQuickTask();
}
$('postponeRestart').onclick = () => {
  clearInterval(restartTimer); restartTimer = null;
  running = false; messages[0] = 'PreviewPostponed';
  render();
};
$('restartPreview').onclick = restartSimulation;
$('resetPreview').onclick = () => {
  clearTimeout(workTimer); clearInterval(restartTimer);
  workTimer = null; restartTimer = null; quick = null; activeTask = null;
  index = 0; running = false; scanned = false;
  states.fill('StateOpen'); messages.fill('NotEdited'); logs.fill('');
  $('optionalDrivers').checked = false;
  render();
};

// Initial draft view.
render();
