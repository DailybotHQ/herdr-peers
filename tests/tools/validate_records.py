#!/usr/bin/env python3
"""Validate NDJSON records against templates/delegation-record.json.

Standard library only; implements exactly the JSON Schema keywords that
schema uses: type (incl. lists), const, enum, pattern, required, properties,
additionalProperties: false. Unknown keywords in the schema are an error, so
the validator can never silently ignore a rule.

Usage: validate_records.py SCHEMA FILE.ndjson   -> exit 0, prints "valid N"
"""
import json
import re
import sys

KNOWN = {'$schema', '$id', 'title', 'description', 'type', 'required',
         'additionalProperties', 'properties', 'const', 'enum', 'pattern'}
TYPES = {'string': str, 'object': dict, 'integer': int, 'null': type(None)}


def check_keywords(node, where):
    unknown = set(node) - KNOWN
    if unknown:
        raise SystemExit('schema %s uses unsupported keywords %s' % (where, sorted(unknown)))
    for name, sub in node.get('properties', {}).items():
        check_keywords(sub, '%s.%s' % (where, name))


def errors(value, schema, where):
    out = []
    if 'const' in schema and value != schema['const']:
        out.append('%s: expected %r' % (where, schema['const']))
    if 'enum' in schema and value not in schema['enum']:
        out.append('%s: %r not in %s' % (where, value, schema['enum']))
    if 'type' in schema:
        names = schema['type'] if isinstance(schema['type'], list) else [schema['type']]
        if not any(isinstance(value, TYPES[n]) and not (n == 'integer' and isinstance(value, bool))
                   for n in names):
            out.append('%s: type %s, wanted %s' % (where, type(value).__name__, names))
    if 'pattern' in schema and isinstance(value, str) and not re.search(schema['pattern'], value):
        out.append('%s: %r does not match %s' % (where, value[:60], schema['pattern']))
    if isinstance(value, dict):
        for key in schema.get('required', []):
            if key not in value:
                out.append('%s: missing %s' % (where, key))
        props = schema.get('properties', {})
        if schema.get('additionalProperties') is False:
            for key in value:
                if key not in props:
                    out.append('%s: unexpected key %s' % (where, key))
        for key, sub in props.items():
            if key in value:
                out.extend(errors(value[key], sub, '%s.%s' % (where, key)))
    return out


def main():
    schema = json.load(open(sys.argv[1], encoding='utf-8'))
    check_keywords(schema, '$')
    count, problems = 0, []
    for n, line in enumerate(open(sys.argv[2], encoding='utf-8'), 1):
        if not line.strip():
            continue
        count += 1
        try:
            rec = json.loads(line)
        except ValueError:
            problems.append('line %d: not JSON' % n)
            continue
        problems.extend('line %d %s' % (n, e) for e in errors(rec, schema, '$'))
    if problems:
        print('\n'.join(problems))
        return 1
    print('valid %d' % count)
    return 0 if count else 1


if __name__ == '__main__':
    sys.exit(main())
