#!/usr/bin/env python3
"""Optional HTML-only checks: Python Playwright + Chromium. Not Flutter tests."""
from playwright.sync_api import sync_playwright
from pathlib import Path
import json
import os
import shutil
ROOT = Path(__file__).resolve().parents[1]
out=ROOT / 'build' / 'preview-checks'; out.mkdir(parents=True, exist_ok=True)
results=[]; errors=[]
def ok(s): results.append(s)
with sync_playwright() as p:
    browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_BIN') or shutil.which('chromium') or shutil.which('google-chrome'),headless=True,args=['--no-sandbox'])
    page=browser.new_page(viewport={'width':1512,'height':1040},device_scale_factor=2)
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.set_content((ROOT / 'preview/index.html').read_text())
    page.locator('#phone').screenshot(path=str(out/'onboarding.png'))
    page.locator('#app [data-go="permissions"]').click()
    page.locator('#app [data-action="guest"]').click()
    page.locator('#app h2').filter(has_text='A clearer road').wait_for()
    ok('Onboarding → optional permissions → guest Explore')
    page.locator('#phone').screenshot(path=str(out/'explore.png'))
    page.locator('#app [data-go="plan"]').first.click()
    page.locator('#app [data-route="1"]').click()
    assert page.evaluate('state.route')==1
    page.locator('#phone').screenshot(path=str(out/'planner.png'))
    page.locator('#app [data-action="start"]').click()
    page.locator('#app [data-action="pause"]').click()
    assert page.evaluate('state.paused') is True
    page.locator('#app [data-action="pause"]').click()
    assert page.evaluate('state.paused') is False
    page.locator('#phone').screenshot(path=str(out/'trip.png'))
    page.locator('#app [data-action="finish"]').click()
    assert page.evaluate('state.trips.length')==1
    ok('Route alternative selection → start → pause/resume → finish → preview trip history')
    page.evaluate("go('report')")
    page.locator('#app textarea').wait_for()
    assert page.locator('#app textarea').is_disabled()
    assert page.locator('#app [data-action="save"]').is_disabled()
    ok('Unknown GPS locks HTML report input and save action')
    page.locator('#app [data-action="demo"]').click()
    assert page.locator('#app textarea').is_enabled()
    page.locator('#app [data-action="photo"]').click()
    assert page.locator('#app [data-action="save"]').is_enabled()
    page.locator('#app [data-action="moving"]').click()
    assert page.locator('#app textarea').is_disabled()
    assert page.locator('#app [data-action="save"]').is_disabled()
    ok('Moving sample locks input and save even after adding a sample photo')
    page.locator('#app [data-action="stationary"]').click()
    page.locator('#app textarea').fill('Surface crack near the roadside.')
    page.locator('#app .scroll').evaluate('(e)=>e.scrollTop=0')
    page.locator('#phone').screenshot(path=str(out/'report.png'))
    page.locator('#app [data-action="save"]').click()
    page.locator('#app .report-entry').wait_for()
    assert 'DEMO · LOCAL ONLY' in page.locator('#app .report-entry').inner_text()
    assert page.evaluate('state.reports.length')==1
    ok('Stationary sample + photo + notes saves a permanently DEMO/local-only preview report')
    page.locator('#app [data-delete="0"]').click()
    assert page.evaluate('state.reports.length')==0
    ok('Delete preview report removes its memory record')
    page.evaluate("go('you')")
    page.locator('#app [data-action="theme"]').click()
    assert page.locator('#phone').evaluate('(e)=>e.classList.contains("app-dark")')
    page.locator('#phone').screenshot(path=str(out/'you_dark.png'))
    page.locator('#app [data-action="theme"]').click()
    page.locator('#app [data-action="mute"]').click()
    assert page.evaluate('state.voice') is False
    page.locator('#app [data-action="clear"]').click()
    assert page.evaluate('state.trips.length')==0
    ok('Theme, sample voice toggle and local preview clear actions update state')
    for width in [320,390,768,1512]:
        page.set_viewport_size({'width':width,'height':1040})
        page.evaluate("go('explore')")
        page.wait_for_timeout(50)
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth'), f'overflow at {width}'
    ok('HTML preview has no document horizontal overflow at 320, 390, 768 and 1512 px')
    assert not errors, errors
    ok('No browser JavaScript page errors during tested preview interactions')
    browser.close()
(out/'preview-validation.json').write_text(json.dumps({'checks':results,'page_errors':errors},indent=2))
print(json.dumps({'checks':results,'page_errors':errors},indent=2))
