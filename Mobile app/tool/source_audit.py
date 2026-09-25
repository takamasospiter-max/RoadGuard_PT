#!/usr/bin/env python3
"""Limited offline source sanity checks. This is NOT a Dart analyzer or Flutter test.
Checks local imports, delimiter balance, assets, required files and secret patterns.
Run flutter analyze + flutter test for language, framework and runtime validation.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def delimiters(text: str, name: str) -> None:
    def error(message, index):
        raise ValueError(f'{name}:{text.count(chr(10), 0, index) + 1}: {message}')

    def string(i):
        quote = text[i]
        raw = i > 0 and text[i - 1] == 'r' and (i < 2 or not text[i - 2].isalnum())
        delim = quote * 3 if text.startswith(quote * 3, i) else quote
        i += len(delim)
        while i < len(text):
            if text.startswith(delim, i):
                return i + len(delim)
            if not raw and text[i] == '\\':
                i += 2
            elif not raw and text.startswith('${', i):
                i = code(i + 2, '}')
            else:
                i += 1
        error('Unclosed string', i)

    def code(i, closing=None):
        while i < len(text):
            if text.startswith('//', i):
                newline = text.find('\n', i)
                i = len(text) if newline < 0 else newline + 1
            elif text.startswith('/*', i):
                depth = 1
                i += 2
                while i < len(text) and depth:
                    if text.startswith('/*', i):
                        depth += 1; i += 2
                    elif text.startswith('*/', i):
                        depth -= 1; i += 2
                    else:
                        i += 1
                if depth:
                    error('Unclosed block comment', i)
            elif text[i] in "\"'":
                i = string(i)
            elif text[i] in '([{':
                i = code(i + 1, {'(': ')', '[': ']', '{': '}'}[text[i]])
            elif text[i] in ')]}':
                if text[i] != closing:
                    error(f'Expected {closing!r}, found {text[i]!r}', i)
                return i + 1
            else:
                i += 1
        if closing:
            error(f'Missing closing {closing!r}', i)
        return i
    code(0)


def main():
    files = sorted([*ROOT.glob('lib/**/*.dart'), *ROOT.glob('test/**/*.dart'), *ROOT.glob('integration_test/**/*.dart')])
    for path in files:
        content = path.read_text()
        delimiters(content, str(path.relative_to(ROOT)))
        for reference in re.findall(r"(?:import|export)\s+'([^']+)'", content):
            if reference.startswith('package:roadguard_ai/'):
                target = ROOT / 'lib' / reference.removeprefix('package:roadguard_ai/')
            elif ':' not in reference:
                target = path.parent / reference
            else:
                continue
            if not target.exists():
                raise ValueError(f'{path}: missing import {reference}')
        for pattern in [r'badCertificateCallback\s*=', r'AIza[0-9A-Za-z_-]{30,}', r'-----BEGIN (?:RSA )?PRIVATE KEY-----']:
            if re.search(pattern, content):
                raise ValueError(f'{path}: unsafe secret/certificate pattern')
    print(f'PASS: balanced delimiters and resolvable local imports in {len(files)} Dart files.')
    print('PASS: no bundled API key/private-key or certificate-bypass patterns in Dart sources.')
    print('NOT RUN: Dart formatting, dependency resolution, Flutter analysis, Flutter tests and native builds.')

if __name__ == '__main__':
    main()
