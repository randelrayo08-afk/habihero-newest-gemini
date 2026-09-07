import pathlib
import re
from collections import OrderedDict

path = pathlib.Path('addons/godot-livekit/bin/debug_livekit_api.txt')
raw = path.read_bytes()
encodings = ['utf-16-le', 'utf-16-be', 'utf-8', 'latin-1']

for encoding in encodings:
    try:
        text = raw.decode(encoding, errors='ignore')
    except Exception as e:
        print('encoding', encoding, 'failed', e)
        continue
    print('---', encoding, '---')
    print('text length', len(text))
    def print_matches(term):
        print(f'-- term {term} --')
        found = []
        for idx, line in enumerate(text.splitlines()):
            if term.lower() in line.lower():
                found.append((idx + 1, line))
        print('count', len(found))
        for line in found[:50]:
            print(line)
        print()

    for term in ['LiveKit', 'Room', 'Audio', 'Track', 'Participant', 'Remote', 'Subscribe', 'Subscribed', 'publish', 'publish_track', 'get_local_participant', 'get_connection_state', 'auto_subscribe', 'connected', 'track']:
        print_matches(term)
    print()
