import os
import re
import sys

KEYWORDS = [b'LiveKit', b'Livekit', b'AudioSource', b'LocalAudioTrack']


def find_livekit_dlls(root_dir):
    candidates = []
    addons_dir = os.path.join(root_dir, 'addons')
    if os.path.isdir(addons_dir):
        for dirpath, _, filenames in os.walk(addons_dir):
            for filename in filenames:
                if filename.lower().endswith('.dll') and 'livekit' in filename.lower():
                    candidates.append(os.path.join(dirpath, filename))
    return candidates


def dump_strings_from_file(path):
    with open(path, 'rb') as f:
        data = f.read()
    strings = re.findall(rb'[\x20-\x7E]{6,}', data)
    print(f'== Strings from: {path}')
    for s in strings:
        if any(keyword in s for keyword in KEYWORDS):
            print(s.decode('ascii', errors='ignore'))


if __name__ == '__main__':
    project_root = os.path.dirname(os.path.abspath(__file__))
    file_arg = sys.argv[1] if len(sys.argv) > 1 else None

    paths = []
    if file_arg:
        paths.append(os.path.abspath(file_arg))
    else:
        paths = find_livekit_dlls(project_root)

    if not paths:
        raise FileNotFoundError(
            'No LiveKit DLL found. Pass a DLL path as argument or place the LiveKit plugin under addons/'
        )

    for path in paths:
        dump_strings_from_file(path)
