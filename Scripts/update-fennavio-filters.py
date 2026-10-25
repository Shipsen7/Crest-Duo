#!/usr/bin/env python3
"""Refresh the bundled WebKit filter data using a pinned external AdGuard converter."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urljoin, urlparse
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent.parent
ENABLED_CONDITIONS = {'env_safari', 'env_mobile', 'adguard_app_ios', 'adguard_ext_safari', 'cap_user_stylesheet'}


def condition(expression):
    """Evaluate only the boolean syntax used by upstream filter preprocessors."""
    tokens = re.findall(r'&&|\|\||!|\(|\)|[A-Za-z_][A-Za-z_0-9]*', expression)
    if ''.join(tokens) != re.sub(r'\s+', '', expression):
        raise ValueError('Unsupported filter condition: ' + expression)
    position = 0

    def atom():
        nonlocal position
        token = tokens[position]
        position += 1
        if token == '!':
            return not atom()
        if token == '(':
            value = disjunction()
            if tokens[position] != ')':
                raise ValueError('Unbalanced filter condition')
            position += 1
            return value
        return token in ENABLED_CONDITIONS

    def conjunction():
        nonlocal position
        value = atom()
        while position < len(tokens) and tokens[position] == '&&':
            position += 1
            right = atom()
            value = value and right
        return value

    def disjunction():
        nonlocal position
        value = conjunction()
        while position < len(tokens) and tokens[position] == '||':
            position += 1
            right = conjunction()
            value = value or right
        return value

    value = disjunction()
    if position != len(tokens):
        raise ValueError('Incomplete filter condition')
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--converter', required=True, type=Path)
    args = parser.parse_args()
    converter = args.converter.resolve()
    configuration = json.loads((ROOT / 'Config/FennavioFilters.json').read_text())
    repository = next(p for p in converter.parents if (p / '.git').exists())
    revision = subprocess.check_output(['git', '-C', str(repository), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != configuration['converterRevision']:
        raise ValueError('The converter checkout must match the reviewed revision in Config/FennavioFilters.json')
    snapshots = {}
    github_revisions = {}

    def pinned(url):
        parts = urlparse(url)
        if parts.hostname != 'raw.githubusercontent.com':
            return url
        segments = parts.path.strip('/').split('/')
        owner, repo, ref = segments[:3]
        if ref == 'master':
            key = owner + '/' + repo
            if key not in github_revisions:
                with urlopen('https://api.github.com/repos/' + key + '/commits/master', timeout=60) as response:
                    github_revisions[key] = json.load(response)['sha']
            segments[2] = github_revisions[key]
        return 'https://raw.githubusercontent.com/' + '/'.join(segments)

    def expand(url, ancestry=()):
        url = pinned(url)
        if url in ancestry:
            raise ValueError('Cyclic filter include')
        if url not in snapshots:
            with urlopen(url, timeout=60) as response:
                data = response.read(16_000_001)
            if len(data) > 16_000_000 or b'<html' in data[:200].lower():
                raise ValueError('Invalid filter response: ' + url)
            snapshots[url] = data
        active = True
        stack = []
        output = []
        for line in snapshots[url].decode('utf-8-sig').splitlines():
            if line.startswith('!#if '):
                branch = condition(line[5:])
                stack.append((active, branch))
                active = active and branch
            elif line == '!#else':
                parent, branch = stack[-1]
                active = parent and not branch
            elif line == '!#endif':
                active, _ = stack.pop()
            elif active and line.startswith('!#include '):
                child = urljoin(url, line[10:].strip())
                # Includes must stay inside their reviewed upstream directory.
                if not child.startswith(url.rsplit('/', 1)[0] + '/'):
                    raise ValueError('Filter include leaves its source directory')
                output.extend(expand(child, ancestry + (url,)))
            elif active and line and not line.startswith(('!', '[')):
                output.append(line)
        if stack:
            raise ValueError('Unclosed filter condition: ' + url)
        return output

    lines = list(dict.fromkeys(line for url in configuration['sources'] for line in expand(url)))
    # Repeat exception directives in every partition. WebKit cannot let an
    # exception in one compiled list cancel a block in a different list.
    exceptions = [line for line in lines if line.startswith('@@') or any(
        marker in line for marker in ('#@#', '#@?#', '#@$#', '#@%#', '$badfilter', ',badfilter'))]
    exception_set = set(exceptions)
    ordinary = [line for line in lines if line not in exception_set]
    lists = []
    conversion = []
    with tempfile.TemporaryDirectory(prefix='fennavio-filters-') as temporary:
        temporary = Path(temporary)
        for index, start in enumerate(range(0, len(ordinary), 60_000)):
            source = temporary / 'combined.txt'
            source.write_text('\n'.join(ordinary[start:start + 60_000] + exceptions) + '\n')
            result = json.loads(subprocess.check_output([
                str(converter), 'convert', '--input-path', str(source), '--safari-version', '26.1',
                '--advanced-blocking', 'false'], text=True))
            if result['discardedSafariRules']:
                raise ValueError('The converter discarded rules; reduce the partition size')
            rules = json.loads(result['safariRulesJSON'])
            source_json = json.dumps(rules, separators=(',', ':'), ensure_ascii=False)
            digest = hashlib.sha256(source_json.encode()).hexdigest()
            lists.append({'identifier': 'io.github.shipsen7.fennavio.protection.' + digest, 'source': source_json})
            conversion.append({key: value for key, value in result.items()
                               if key not in ('safariRulesJSON', 'advancedRulesText')})
    count = sum(item['safariRulesCount'] for item in conversion)
    if count < 20_000:
        raise ValueError('Unexpected WebKit rule count: ' + str(count))
    resource = ROOT / 'CrestShared/Resources/FennavioProtection.json'
    resource.write_text(json.dumps(lists, separators=(',', ':'), ensure_ascii=False) + '\n')
    sources = ROOT / 'ThirdParty/FennavioFilters/Sources'
    sources.mkdir(parents=True, exist_ok=True)
    def subscription_url(url):
        parts = urlparse(url)
        if parts.hostname != 'raw.githubusercontent.com':
            return url
        segments = parts.path.strip('/').split('/')
        segments[2] = 'master'
        return 'https://raw.githubusercontent.com/' + '/'.join(segments)

    # Runtime includes resolve relative to subscription URLs; the manifest below
    # retains the pinned URLs for reproducible source correspondence.
    (ROOT / 'CrestShared/Resources/FennavioFilterSources.json').write_text(
        json.dumps({subscription_url(url): data.decode('utf-8-sig') for url, data in snapshots.items()},
                   separators=(',', ':'), ensure_ascii=False) + '\n')
    inventory = []
    for url, data in sorted(snapshots.items()):
        name = hashlib.sha256(url.encode()).hexdigest()[:16] + '-' + urlparse(url).path.rsplit('/', 1)[1]
        (sources / name).write_bytes(data)
        inventory.append({'url': url, 'file': 'Sources/' + name, 'sha256': hashlib.sha256(data).hexdigest()})
    manifest = {'converterRevision': revision, 'inputRules': len(lines), 'webKitRules': count, 'partitions': conversion,
                'rulesSHA256': hashlib.sha256(resource.read_bytes()).hexdigest(), 'sources': inventory}
    (sources.parent / 'Manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    # Remove only superseded input snapshots owned by this generator.
    retained = {item['file'].split('/', 1)[1] for item in inventory}
    for path in sources.glob('*.txt'):
        if path.name not in retained:
            path.unlink()
    print(f'Generated {count} native WebKit rules in {len(lists)} lists from {len(lines)} deduplicated filters.')


if __name__ == '__main__':
    main()
