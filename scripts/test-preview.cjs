// DOM scenario tests only; no browser or computer-use automation.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { JSDOM, VirtualConsole } = require('jsdom');
const template = fs.readFileSync(path.join(__dirname, '../assets/source/preview-template.html'), 'utf8');
const localeExpression = template.match(/let locale = (\(\(\) => \{[\s\S]*?\}\)\(\));/)[1];
for (const [languages, expected] of [
  [['zh-HK', 'en-US'], 'zh-Hans'],
  [['en-GB', 'zh-CN'], 'en'],
  [['fr-FR', 'zh-TW'], 'zh-Hans'],
  [['fr-FR', 'de-DE'], 'en'],
]) assert.equal(vm.runInNewContext(localeExpression, { navigator: { languages, language: languages[0] } }), expected);
assert.equal(vm.runInNewContext(localeExpression, { navigator: { language: 'zh-CN' } }), 'zh-Hans');
assert.equal(vm.runInNewContext(localeExpression, { navigator: { language: 'en-US' }, localStorage: {getItem:()=> 'zh-Hans'} }), 'zh-Hans');
process.stdout.write('PASS supported language priority and English fallback\n');
const errors = [];
const console = new VirtualConsole();
console.on('jsdomError', e => errors.push(e));
const dom = new JSDOM(fs.readFileSync(path.join(__dirname, '../assets/preview.html'), 'utf8'), {
  url: 'https://enchant.test/', runScripts: 'dangerously', virtualConsole: console,
  beforeParse(window) {
    window.confirm = () => true;
    Object.defineProperty(window.navigator, 'language', { value: 'zh-CN' });
    Object.defineProperty(window.navigator, 'languages', { value: ['zh-CN'] });
  }
});
const { document } = dom.window;
function click(action) {
  const button = document.querySelector(`[data-action="${action}"]`);
  assert.ok(button, `Missing action: ${action}`); button.click();
}
let passed = 0;
function test(name, run) { run(); passed++; process.stdout.write(`PASS ${name}\n`); }
test('all scenes render both devices without script errors', () => {
  for (const button of [...document.querySelectorAll('#scenarios button')]) {
    button.click(); assert.ok(document.querySelector('#phone').textContent.trim()); assert.ok(document.querySelector('#watch').textContent.trim());
    for (const id of ['phone', 'watch']) assert.ok(!document.querySelector('#'+id).textContent.includes('演示'), `Device-level preview copy remains in ${id}`);
  }
  assert.equal(document.querySelector('header .pill').textContent, '界面预览');
  assert.ok(document.querySelector('aside .aside-note').textContent.includes('预览使用样例记录，保存在当前浏览器。'));
  assert.ok(document.querySelector('aside .aside-note').textContent.includes('原生应用使用真实设备数据。'));
  assert.deepEqual(errors, []);
});
test('home contains one start and shared illustrated entry points', () => {
  click('scenario:normal');
  const watch = document.querySelector('#watch');
  assert.equal(watch.querySelectorAll('[data-action="start"]').length, 1);
  assert.ok(watch.querySelector('.book-icon'));
  assert.equal(watch.querySelector('[data-action="watchSettings"] svg').outerHTML, document.querySelector('#phoneNav [data-action="page:settings"] svg').outerHTML);
  assert.ok(!watch.textContent.includes('准备附魔'));
  const phone = document.querySelector('#phone');
  const start = phone.querySelector('.hero-card [data-action="start"]');
  assert.equal(start.nextElementSibling.className, 'metrics');
  assert.ok(start.nextElementSibling.textContent.includes('本月记录'));
  assert.ok(start.nextElementSibling.textContent.includes('本月活动时长'));
  assert.ok(!phone.querySelector('.hero-card + .metrics'));
  assert.ok(phone.querySelector('.book-card-content img'));
  assert.ok(phone.querySelector('.book-card-arrow'));
  assert.equal(dom.window.getComputedStyle(phone.querySelector('.sync')).textAlign, 'center');
  assert.equal(dom.window.getComputedStyle(phone.querySelector('.sync')).alignSelf, 'stretch');
  for (const text of ['手动补记', '自动监测', '备份与导入']) assert.ok(!document.querySelector('#scenarios').textContent.includes(text));
});
test('record pause resume finish and archive', () => {
  click('scenario:normal'); click('start'); click('pause'); assert.ok(document.querySelector('#watch').textContent.includes('已暂停'));
  click('pause'); click('finish'); assert.ok(document.querySelector('#watch').textContent.includes('附魔完成'));
  click('done'); click('watchJournal'); assert.ok(document.querySelector('#watch .watch-record'));
});
test('idle replaces state and leaves one control row', () => {
  click('scenario:idle'); assert.equal(document.querySelectorAll('#watch .state').length, 1);
  assert.equal(document.querySelectorAll('#watch .watch-controls').length, 1);
  assert.ok(document.querySelector('#watch .state').textContent.includes('10秒'));
  click('continueIdle'); assert.ok(document.querySelector('#watch .state').textContent.includes('正在附魔'));
});
test('watch details include average peak chart and editable note', () => {
  click('scenario:detail'); const watch = document.querySelector('#watch');
  assert.ok(watch.textContent.includes('平均 bpm')); assert.ok(watch.textContent.includes('峰值 bpm'));
  click('watchSlide:more'); assert.ok(document.querySelector('#watch .chart'));
  click('watchSlide:note'); click('watchNote'); document.querySelector('#watchNoteInput').value = 'Local note https://example.com/a';
  click('saveWatchNote'); click('watchSlide:note'); assert.equal(document.querySelector('#watch a').href, 'https://example.com/a');
});
test('phone note uses inline links without link form', () => {
  click('scenario:edit'); const form = document.querySelector('#editor');
  assert.ok(!form.querySelector('.link-fields')); form.elements.note.value = 'One note https://example.com/link';
  form.dispatchEvent(new dom.window.Event('submit', { bubbles: true, cancelable: true }));
  assert.equal(document.querySelector('#phone .note-body a').href, 'https://example.com/link');
});
test('automatic preference stays in settings and returns to single home', () => {
  click('scenario:normal'); click('watchSettings'); click('pref:automatic'); click('watchHome');
  assert.equal(document.querySelectorAll('#watch [data-action="start"]').length, 1);
  assert.ok(!document.querySelector('#watch [data-action="monitor"]'));
});
test('calendar year search and empty scenes', () => {
  click('scenario:calendar'); click('yearMode'); assert.equal(document.querySelectorAll('.year-grid button').length, 12);
  click('month:9'); const search = document.querySelector('#search'); search.value = 'no-such-note'; search.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
  assert.ok(document.querySelector('#searchResults').textContent.includes('没有匹配记录'));
  assert.ok(document.querySelector('#phone').classList.contains('searching'));
  click('cancelSearch'); assert.equal(document.querySelector('#search').value, '');
  assert.ok(!document.querySelector('#phone').classList.contains('searching'));
  click('scenario:empty'); assert.ok(document.querySelector('#phone').textContent.includes('这页还空着'));
});
test('scenario previews keep Watch counterparts visible', () => {
  for (const [scenario, action] of [['calendar','watchRecord:'], ['edit','saveWatchNote'], ['trash','watchSettings']]) {
    click('scenario:'+scenario); const watch = document.querySelector('#watch');
    if (scenario==='calendar') assert.ok(watch.querySelector('#watchSearch'));
    if (scenario==='edit') assert.ok(watch.querySelector('#watchNoteInput'));
    if (scenario==='trash') assert.ok(watch.textContent.includes('回收站'));
  }
  click('page:settings'); assert.equal(document.querySelectorAll('#watch .preference-tile').length, 6);
});
test('result omits routine storage copy and trash has its own icon', () => {
  click('scenario:result'); assert.ok(!document.querySelector('#phone').textContent.includes('已保存在本机'));
  assert.ok(document.querySelector('#watch [data-action="editResult"]'));
  for (const device of ['phone', 'watch']) assert.equal(document.querySelector('#'+device+' [data-action="editResult"]').textContent, '备注');
  click('scenario:trash'); assert.ok(document.querySelector('#watch .watch-empty .object-art svg'));
});
test('shared defaults use the same copy without URL prompts or calendar legend', () => {
  click('scenario:calendar');
  assert.equal(document.querySelector('#search').placeholder, '搜索日期或备注');
  assert.equal(document.querySelector('#watchSearch').placeholder, document.querySelector('#search').placeholder);
  assert.ok(!document.querySelector('#phone').textContent.includes('紫色代表'));
  click('scenario:edit');
  assert.equal(document.querySelector('#watchNoteInput').placeholder, '写下备注…');
  assert.equal(document.querySelector('#editor textarea').placeholder, document.querySelector('#watchNoteInput').placeholder);
  click('page:settings');
  assert.ok(document.querySelector('#watch').textContent.includes('记录心率'));
});
test('enchant tab uses the shared sword and settings use distinct object icons', () => {
  click('scenario:normal');
  assert.ok(document.querySelector('#phoneNav .tab-sword'));
  click('page:settings');
  for (const footer of document.querySelectorAll('#phone>.settings-note, #phone>.sync')) {
    assert.equal(dom.window.getComputedStyle(footer).textAlign, 'center');
    assert.equal(dom.window.getComputedStyle(footer).alignSelf, 'stretch');
  }
  for (const key of ['automatic', 'autoStop', 'health', 'sound', 'haptics']) {
    const phone = document.querySelector(`[data-pref="${key}"]`).closest('label');
    const watch = document.querySelector(`[data-action="pref:${key}"]`);
    assert.ok(phone.querySelector('svg'), `Missing phone object icon: ${key}`);
    assert.equal(phone.querySelector('svg').outerHTML, watch.querySelector('svg').outerHTML);
  }
  click('watchSize:small');
  const preferences=document.querySelector('#watch .watch-preferences');
  const tile=preferences.querySelector('.preference-tile');
  const tileStyle=dom.window.getComputedStyle(tile);
  assert.equal(tileStyle.height,'44px');assert.equal(tileStyle.minHeight,'44px');
  assert.equal(tileStyle.backgroundColor,'rgba(0, 0, 0, 0)');
  assert.equal(tileStyle.whiteSpace,'nowrap');
  assert.equal(dom.window.getComputedStyle(tile.querySelector('svg')).width,'12px');
  assert.equal(dom.window.getComputedStyle(preferences).rowGap,'2px');
  click('watchSize:large');
  assert.equal(dom.window.getComputedStyle(tile.querySelector('svg')).width,'16px');
  assert.ok(!document.querySelector('.coverage'));
});
test('removed controls remain absent from every scene', () => {
  for (const button of [...document.querySelectorAll('#scenarios button')]) {
    button.click();
    for (const action of ['backfill', 'export', 'addLink', 'lock']) assert.ok(!document.querySelector(`#phone [data-action="${action}"]`));
    assert.ok(!document.querySelector('#importFile'));
  }
  assert.deepEqual(errors, []);
});
test('preview language switch preserves scene, session, drafts and searches', () => {
  const chinese=()=>document.querySelector('[data-action="language:zh-Hans"]');
  const english=()=>document.querySelector('[data-action="language:en"]');
  assert.equal(chinese().getAttribute('aria-pressed'),'true');
  assert.equal(english().getAttribute('aria-pressed'),'false');
  assert.equal(dom.window.getComputedStyle(english()).whiteSpace,'nowrap');
  click('scenario:active');click('pause');
  const timer=document.querySelector('#watchTimer').textContent;
  click('language:en');
  assert.equal(document.documentElement.lang,'en');
  assert.equal(english().getAttribute('aria-pressed'),'true');
  assert.equal(chinese().getAttribute('aria-pressed'),'false');
  assert.equal(english().getAttribute('aria-label'),'Switch to English');
  assert.equal(document.querySelector('#watch .state').textContent,'Paused');
  assert.equal(document.querySelector('#watchTimer').textContent,timer);
  assert.equal(document.querySelector('.scenario.chosen').dataset.action,'scenario:active');
  click('language:zh-Hans');
  assert.equal(document.querySelector('#watch .state').textContent,'已暂停');
  assert.equal(document.querySelector('#watchTimer').textContent,timer);

  click('scenario:edit');
  const original='未提交的私人备注 https://example.com/中文?note=原文';
  let phoneNote=document.querySelector('#editor textarea');
  phoneNote.value=original;phoneNote.focus();phoneNote.setSelectionRange(2,7);
  document.querySelector('#watchNoteInput').value='手表中的独立草稿 https://example.com/watch';
  const stored=dom.window.localStorage.getItem('enchant.design.v1');
  english().dispatchEvent(new dom.window.MouseEvent('pointerdown',{bubbles:true}));
  english().focus();click('language:en');
  phoneNote=document.querySelector('#editor textarea');
  assert.equal(document.querySelector('.scenario.chosen').dataset.action,'scenario:edit');
  assert.equal(phoneNote.value,original);
  assert.equal(document.querySelector('#watchNoteInput').value,'手表中的独立草稿 https://example.com/watch');
  assert.equal(document.activeElement,phoneNote);
  assert.equal(phoneNote.selectionStart,2);assert.equal(phoneNote.selectionEnd,7);
  assert.equal(dom.window.localStorage.getItem('enchant.design.v1'),stored);
  click('language:zh-Hans');
  assert.equal(document.querySelector('#editor textarea').value,original);
  assert.equal(document.querySelector('#watchNoteInput').value,'手表中的独立草稿 https://example.com/watch');

  click('scenario:calendar');
  let search=document.querySelector('#search');
  search.value='2026-10-08';search.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  search.focus();search.setSelectionRange(0,4);
  const resultCount=document.querySelectorAll('#searchResults .record-row').length;
  const watchSearch=document.querySelector('#watchSearch');
  watchSearch.value='2026-10-08';watchSearch.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  search=document.querySelector('#search');search.focus();
  click('language:en');
  assert.equal(document.querySelector('#search').value,'2026-10-08');
  assert.equal(document.querySelector('#watchSearch').value,'2026-10-08');
  assert.equal(document.querySelectorAll('#searchResults .record-row').length,resultCount);
  assert.ok(document.querySelector('#phone').classList.contains('searching'));
  click('language:zh-Hans');
  assert.equal(document.querySelector('#search').value,'2026-10-08');
  assert.equal(document.querySelector('#watchSearch').value,'2026-10-08');
  assert.equal(document.querySelectorAll('#searchResults .record-row').length,resultCount);
  assert.deepEqual(errors, []);
});
dom.window.close();
process.stdout.write(`${passed} preview tests passed\n`);

const englishErrors = [];
const englishConsole = new VirtualConsole();
englishConsole.on('jsdomError', error => englishErrors.push(error));
const englishDOM = new JSDOM(fs.readFileSync(path.join(__dirname, '../assets/preview.html'), 'utf8'), {
  url: 'https://enchant.test/', runScripts: 'dangerously', virtualConsole: englishConsole,
  beforeParse(window) {
    window.confirm = () => true;
    Object.defineProperty(window.navigator, 'language', { value: 'en-US' });
    Object.defineProperty(window.navigator, 'languages', { value: ['en-US', 'zh-CN'] });
  }
});
const englishDocument = englishDOM.window.document;
function englishClick(action) {
  const button = englishDocument.querySelector(`[data-action="${action}"]`);
  assert.ok(button, `Missing English action: ${action}`); button.click();
}
const containsChinese = /[\u3400-\u9fff]/;
function assertEnglishUI(context) {
  for (const selector of ['#phone', '#watch', '#phoneNav', '#scenarios', 'header', 'aside', 'footer']) {
    const surface = englishDocument.querySelector(selector);
    const content=surface.cloneNode(true);
    content.querySelector('.language-switch')?.remove();
    assert.ok(!containsChinese.test(content.textContent), `Chinese UI text remains in English ${selector} / ${context}`);
    assert.ok(!/%@|%ld/.test(surface.textContent), `Unformatted UI text in English ${selector} / ${context}`);
    for (const element of surface.querySelectorAll('[placeholder], [aria-label], [alt]')) {
      for (const attribute of ['placeholder', 'aria-label', 'alt']) assert.ok(!containsChinese.test(element.getAttribute(attribute) || ''), `Chinese ${attribute} remains in English ${selector}`);
    }
  }
}
for (const scene of [...englishDocument.querySelectorAll('#scenarios button')]) {
  scene.click();
  assertEnglishUI(scene.dataset.action);
}
assert.equal(englishDocument.documentElement.lang, 'en');
assert.ok(englishDocument.title.includes('Spellbook'));
assert.equal(englishDocument.querySelector('header .pill').textContent, 'App preview');
assert.ok(englishDocument.querySelector('aside .aside-note').textContent.includes('Sample records stay in this browser.'));
englishClick('scenario:result');
assert.equal(englishDocument.querySelector('#watch [data-action="editResult"]').textContent, 'Note');
assert.equal(englishDocument.querySelector('#watch [data-action="done"]').textContent, 'Done');
englishClick('scenario:calendar');
assert.ok(englishDocument.querySelector('.calendar strong').textContent.includes('October'));
englishClick('yearMode');
assert.ok(englishDocument.querySelector('.year-grid button strong').textContent.includes('Jan'));
assert.ok(!containsChinese.test(englishDocument.querySelector('.calendar-grid')?.textContent || ''));
englishClick('page:settings');
assertEnglishUI('settings');
assert.equal(englishDocument.querySelector('#watch [data-action="pref:autoStop"]').textContent.trim(), 'Idle alert');
englishClick('pref:automatic');
assertEnglishUI('settings preference changed');
englishClick('watchTrash');
assertEnglishUI('Watch trash');
englishClick('scenario:detail');
englishClick('watchSlide:more');
assertEnglishUI('Watch heart chart');
englishClick('detailPage:note');
assertEnglishUI('note details');
englishClick('scenario:failure');
englishClick('retry');
assert.ok(!containsChinese.test(englishDocument.querySelector('#toast').textContent));
englishDocument.querySelector('#reset').click();
assert.ok(!containsChinese.test(englishDocument.querySelector('#toast').textContent));
assert.deepEqual(englishErrors, []);
process.stdout.write('PASS English scenes, accessibility and locale/date labels\n');

englishClick('scenario:edit');
const originalNote = '私人备注保持中文 https://example.com/中文?title=私人';
const englishForm = englishDocument.querySelector('#editor');
englishForm.elements.note.value = originalNote;
englishForm.dispatchEvent(new englishDOM.window.Event('submit', { bubbles: true, cancelable: true }));
assert.equal(englishDocument.querySelector('#phone .note-body p').textContent, originalNote);
assert.equal(englishDocument.querySelector('#watch .watch-note-text').textContent, originalNote);
assert.equal(englishDocument.querySelector('#phone .note-body a').textContent, 'https://example.com/中文?title=私人');
englishClick('edit');
assert.equal(englishDocument.querySelector('#editor textarea').value, originalNote);
assert.equal(englishDocument.querySelector('#watchNoteInput').value, originalNote);
assert.deepEqual(englishErrors, []);
englishDOM.window.close();
process.stdout.write('PASS English locale preserves user notes and URL text\n');
