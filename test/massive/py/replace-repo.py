#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
from argparse import ArgumentParser

import yaml

parser = ArgumentParser(description='An hilarious description')
parser.add_argument('rosinstall_file', action='store')
parser.add_argument('--hash', action='store', dest='hash')
parser.add_argument('--package', action='store', dest='package')
parser.add_argument('--url', action='store', dest='url')

args = parser.parse_args()

with open(args.rosinstall_file) as rosinstall_file:
    rosinstall = yaml.load(rosinstall_file)

try:
    package = next(
        package
        for item in rosinstall
        for package in item.values()
        if package['local-name'] == args.package
    )
    package['uri'] = args.url
    package['version'] = args.hash
except StopIteration:
    print('{} package not found!'.format(args.package), file=sys.stderr)
    sys.exit(1)

with open(args.rosinstall_file, 'w') as rosinstall_file:
    rosinstall_file.write(yaml.dump(rosinstall, default_flow_style=False))
