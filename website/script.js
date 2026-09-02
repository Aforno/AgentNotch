const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) entry.target.classList.add('is-visible');
  });
}, { threshold: 0.14 });

document.querySelectorAll('.reveal').forEach((el) => revealObserver.observe(el));

const notch = document.querySelector('[data-notch]');
const activity = document.querySelector('[data-activity]');
const modeTitle = document.querySelector('[data-mode-title]');

const notchStates = [
  { open: false, activity: 'Running tests', title: '3 agents working' },
  { open: true, activity: 'Running tests', title: '3 agents working' },
  { open: false, activity: 'Editing SessionStore', title: '3 agents working' },
  { open: true, activity: 'Waiting for approval', title: '1 agent needs you' },
];

let notchIndex = 0;
function applyNotchState() {
  const state = notchStates[notchIndex % notchStates.length];
  notch.classList.toggle('is-open', state.open);
  activity.textContent = state.activity;
  modeTitle.textContent = state.title;
  notchIndex += 1;
}

applyNotchState();
if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
  window.setInterval(applyNotchState, 3100);
}

document.querySelectorAll('[data-choice]').forEach((button) => {
  button.addEventListener('click', () => {
    const result = document.querySelector('[data-choice-result]');
    const allowed = button.dataset.choice === 'allow';
    result.textContent = allowed ? 'Sent to Claude Code — you can keep working.' : 'Dismissed — Claude Code will keep waiting in its own prompt.';
    result.style.color = allowed ? 'var(--green)' : 'var(--muted)';
    result.classList.add('visible');
  });
});

const sessions = {
  auth: {
    provider: 'Codex', title: 'Fix authentication bug', progress: 72,
    rows: [
      ['done', 'Trace login flow', 'Completed'], ['done', 'Patch token refresh', 'Completed'], ['current', 'Run authentication tests', 'In progress'], ['', 'Review edge cases', 'Pending']
    ],
    files: ['Sources/Auth/SessionStore.swift', 'Tests/AuthTests.swift']
  },
  sidebar: {
    provider: 'Claude Code', title: 'Refine activity sidebar', progress: 54,
    rows: [
      ['done', 'Audit current layout', 'Completed'], ['current', 'Refactor SidebarView', 'In progress'], ['', 'Check keyboard navigation', 'Pending'], ['', 'Run UI snapshot tests', 'Pending']
    ],
    files: ['Sources/AgentsNotch/SidebarView.swift', 'Sources/AgentsNotch/ActivityCenter.swift']
  },
  migration: {
    provider: 'Claude Code', title: 'Database migration', progress: 38,
    rows: [
      ['done', 'Inspect schema', 'Completed'], ['current', 'Request migration approval', 'Waiting for user'], ['', 'Run migration', 'Blocked'], ['', 'Validate records', 'Pending']
    ],
    files: ['api/db/schema.sql', 'api/db/migrate.ts']
  },
  tests: {
    provider: 'Gemini CLI', title: 'Stabilize integration tests', progress: 64,
    rows: [
      ['done', 'Collect failing runs', 'Completed'], ['done', 'Group flaky tests', 'Completed'], ['current', 'Inspect race conditions', 'In progress'], ['', 'Patch and rerun', 'Pending']
    ],
    files: ['client/tests/integration.spec.ts', 'client/src/session.ts']
  },
  release: {
    provider: 'OpenCode', title: 'Prepare 0.2.1 release', progress: 100,
    rows: [
      ['done', 'Run repository checks', 'Completed'], ['done', 'Package release build', 'Completed'], ['done', 'Verify checksums', 'Completed'], ['done', 'Write release notes', 'Completed']
    ],
    files: ['CHANGELOG.md', 'VERSION']
  }
};

const detail = document.querySelector('[data-session-detail]');
const escapeHtml = (value) => value.replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));

function renderSession(key) {
  const session = sessions[key];
  if (!session || !detail) return;
  detail.innerHTML = `
    <div class="detail-head"><div><span>${escapeHtml(session.provider)}</span><h3>${escapeHtml(session.title)}</h3></div><button type="button">Open session ↗</button></div>
    <div class="progress-track"><span style="width:${session.progress}%"></span></div>
    <div class="detail-plan">
      ${session.rows.map(([state, title, meta]) => `<div class="plan-row ${state}"><span>${state === 'done' ? '✓' : ''}</span><div><strong>${escapeHtml(title)}</strong><em>${escapeHtml(meta)}</em></div></div>`).join('')}
    </div>
    <div class="detail-files"><span>Recent files</span>${session.files.map((file) => `<code>${escapeHtml(file)}</code>`).join('')}</div>`;
}

document.querySelectorAll('[data-session]').forEach((button) => {
  button.addEventListener('click', () => {
    document.querySelectorAll('[data-session]').forEach((item) => item.classList.remove('selected'));
    button.classList.add('selected');
    renderSession(button.dataset.session);
  });
});

document.querySelectorAll('.sidebar-item').forEach((button) => {
  button.addEventListener('click', () => {
    document.querySelectorAll('.sidebar-item').forEach((item) => item.classList.remove('selected'));
    button.classList.add('selected');
  });
});

const copyButton = document.querySelector('[data-copy]');
if (copyButton) {
  copyButton.addEventListener('click', async () => {
    const command = 'brew tap Aforno/agentnotch https://github.com/Aforno/AgentNotch\nbrew install --cask aforno/agentnotch/agent-notch';
    try {
      await navigator.clipboard.writeText(command);
      copyButton.textContent = 'Copied';
      setTimeout(() => { copyButton.textContent = 'Copy'; }, 1600);
    } catch {
      copyButton.textContent = 'Select text';
    }
  });
}
