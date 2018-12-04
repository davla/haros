#!/usr/bin/env python3

from argparse import ArgumentParser
import yaml


def get_names(distro):
    return distro['repositories'].keys()


def get_urls(distro):
    for package in distro['repositories'].values():
        repo = (package.get('source', None)
                or package.get('release', None)
                or package.get('doc', None))
        if repo:
            yield repo['url']


parser = ArgumentParser(description='An hilarious description')
parser.add_argument('distro_file', metavar='F', type=str)
parser.add_argument('--names', action='append_const', const=get_names,
                    dest='actions')
parser.add_argument('--urls', action='append_const', const=get_urls,
                    dest='actions')

args = parser.parse_args()

with open(args.distro_file, 'r', encoding='UTF-8') as distro_file:
    distro = yaml.load(distro_file)
    results = (action(distro) for action in args.actions)
    for result in zip(*results):
        for item in result:
            print(item, end=' ')
        print('')

