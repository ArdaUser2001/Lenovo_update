'use strict';

// Session state stays in memory. Reloading the page resets the entire preview.
// DATA comes from data.js, which build.py generates from the Windows app.
const $ = id => document.getElementById(id);
let language = 'de', index = 0, scanned = false, running = false;
let renderedStep = -1;
const states = Array(8).fill('StateOpen');
const messages = Array(8).fill('NotEdited');
const logs = Array(8).fill('');

// Store translation keys rather than translated text so language changes are immediate.
const t = key => DATA.ui[language][key] || key;
const completed = i => ['StateAuto', 'StateUserConfirmed'].includes(states[i]);

// Geometry comes from the same Icons.xaml resources used by the Windows UI.
const actionIcons = {
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
  );
}

// Rebuild the view from session state; this function never runs update actions.
function render() {
  document.documentElement.lang = language;
  document.querySelectorAll('[data-text]').forEach(el => el.textContent = t(el.dataset.text));

  // Step heading, instructions and overall completion count.
  const step = DATA.steps[language][index];
  if (renderedStep !== index) {
    ['instructions', 'alternatives', 'technical'].forEach(id => $(id).open = false);
    renderedStep = index;
    document.querySelector('.body').scrollTop = 0;
  }
  $('intro').textContent = t(`StepIntro${index + 1}`);
  $('title').textContent = step.Title.replace(/^\d+ · /, '');
  $('mode').textContent = step.Mode;
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
    number.textContent = completed(i) ? '✓' : i + 1;
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
      render();
    };
    return button;
  }));

  // The install action becomes available only after the simulated program scan.
  $('actions').replaceChildren();
  $('additionalActions').replaceChildren();
  step.Actions.forEach((action, i) => {
    const button = document.createElement('button');
    button.textContent = action.Label;
    addButtonIcon(button, actionIcons[action.Id] || 'IconExternal');
    button.className = (index === 3 && scanned ? action.Id === 'Install' : i === 0)
      ? 'primary'
      : '';
    button.disabled = running || (action.Id === 'Install' && !scanned);
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
  $('log').textContent = logs[index] || 'macOS UI Preview — simulated actions only.';
  $('confirmation').hidden = !step.Manual;
  $('confirm').checked = states[index] === 'StateUserConfirmed';
  $('confirm').disabled = running;
  $('busy').hidden = states[index] !== 'StateRunning';
  $('back').disabled = running || index === 0;
  $('next').disabled = running;
  $('next').className = completed(index) || index === 7 ? 'primary' : '';
  $('next').textContent = t(
    index === 7 ? 'Summary' : completed(index) ? 'NextStep' : 'ContinueOpen'
  );
  [['back', 'IconArrowLeft'], ['next', 'IconArrowRight'], ['guide', 'IconDocument'],
    ['help', 'IconHelp'], ['report', 'IconDocument']].forEach(([id, key]) => addButtonIcon($(id), key));
}

// Mimic asynchronous work with a short timer. No Windows command is executed.
function simulate(action) {
  // Capture the originating step while the simulated worker is running.
  const target = index;
  running = true;
  states[target] = 'StateRunning';
  messages[target] = 'RunningMessage';
  logs[target] += `\n[Preview] ${action.Label}`;
  render();

  setTimeout(() => {
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

// Initial German view, with every step still open.
render();
