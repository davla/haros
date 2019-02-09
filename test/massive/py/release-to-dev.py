#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import yaml

from argparse import ArgumentParser
from os import path

ros_distros = ('melodic', 'lunar', 'kinetic', 'jade', 'indigo', 'hydro',
               'groovy')
rosdistro_files = {}


def get_rosdistro(name):
    global rosdistro_files

    try:
        return rosdistro_files[name]
    except KeyError:
        rosdistro_filename = path.join(args.rosdistro_path, name,
                                       'distribution.yaml')
        with open(rosdistro_filename) as rosdistro_file:
            rosdistro_files[name] = yaml.load(rosdistro_file)

        return rosdistro_files[name]


def find_package_by_release(ros_distros, release_url):
    if not ros_distros:
        raise ValueError(release_url)

    try:
        rosdistro = get_rosdistro(ros_distros[0])

        return next(
            package
            for package in rosdistro['repositories'].values()
            if ('release' in package
                and 'source' in package
                and package['release']['url'] == release_url)
        )
    except StopIteration:
        return find_package_by_release(ros_distros[1:], release_url)


parser = ArgumentParser(description='An hilarious description')
parser.add_argument('rosdistro', action='store')
parser.add_argument('--rosdistro-path', action='store',
                    default=path.normpath(path.join(path.dirname(__file__),
                                                    '..', 'rosdistro')),
                    dest='rosdistro_path')
args = parser.parse_args()

searchable_ros_distros = ros_distros[ros_distros.index(args.rosdistro):]

for release_url in sys.stdin:
    release_url = release_url.strip()
    try:
        package = find_package_by_release(searchable_ros_distros, release_url)
        print(package['source']['url'], package['source']['version'])
    except ValueError:
        print('{} devel repository not found'.format(release_url),
              file=sys.stderr)
