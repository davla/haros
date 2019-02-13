#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
from argparse import ArgumentParser
from os import path

import yaml


def get_package_path(package):
    return next(iter(package.values()))['local-name']


parser = ArgumentParser(description='An hilarious description')
parser.add_argument('deps_file', action='store')

args = parser.parse_args()

with open(args.deps_file) as deps_file:
    deps = yaml.load(deps_file)

package = yaml.load(sys.stdin.read())[0]
package_path = get_package_path(package)

deps = [
    package
    for package in deps
    if path.dirname(get_package_path(package)) != package_path
]
deps.append(package)

with open(args.deps_file, 'w') as deps_file:
    deps_file.write(yaml.dump(deps, default_flow_style=False))
