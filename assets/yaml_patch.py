#!/usr/bin/env python
import sys
import yaml

try:
    yaml_path, file_path, base64 = sys.argv[1:]
except Exception:
    sys.stderr.write('Expects to be called with 3 args\n')

yaml_doc = {}
updated_files = []

with open(yaml_path, "r") as yaml_file:
    yaml_doc = yaml.safe_load(yaml_file).copy()

original_files = yaml_doc['spec']['config']['storage']['files']
while original_files:
    file = original_files.pop()
    if file['path'] == file_path:
        file['contents']['source'] = "data:text/plain;charset=utf-8;base64,%s" % base64
    updated_files.append(file)

yaml_doc['spec']['config']['storage']['files'] = updated_files

with open(yaml_path, "w") as yaml_file:
    yaml.dump(yaml_doc, yaml_file, default_flow_style=False)
