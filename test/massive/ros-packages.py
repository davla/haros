#!/usr/bin/env python3

from argparse import ArgumentParser

from rosinstall_generator.generator import (ARG_ALL_PACKAGES,
                                            generate_rosinstall,
                                            sort_rosinstall)
import yaml


def get_names(packages):
    return (
        package['name']
        for package in packages
    )


def get_urls(packages):
    return (
        '{} {}'.format(package['uri'], package['version'])
        for package in packages
    )


def process_package(package):
    package = package['git']
    package['name'] = package['local-name']
    del package['local-name']
    return package


parser = ArgumentParser(description='An hilarious description')
parser.add_argument('rosdistro', action='store')
parser.add_argument('--names', action='append_const', const=get_names,
                    dest='actions')
parser.add_argument('--urls', action='append_const', const=get_urls,
                    dest='actions')

args = parser.parse_args()

packages = map(process_package, sort_rosinstall(generate_rosinstall(
    args.rosdistro, [ARG_ALL_PACKAGES])))

results = (action(packages) for action in args.actions)
for result in zip(*results):
    for item in result:
        print(item, end=' ')
    print('')
