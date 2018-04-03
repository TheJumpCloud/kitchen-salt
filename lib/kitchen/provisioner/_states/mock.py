from __future__ import absolute_import
import ast
import glob
import yaml

import logging

# import salt libs
from salt.exceptions import SaltInvocationError

log = logging.getLogger(__name__)

mine_data = {}
remote_functions_data = {}

def mine(name):
    global mine_data
    # FIXME(ppg): drive via configuration
    for file in glob.glob('/tmp/kitchen/srv/mine/*'):
        mine_data.update(yaml.load(open(file)))
    __salt__['mine.get'] = _mock_get
    return { 'name': 'mine', 'changes': {}, 'result': True, 'comment': 'Replaced mine.get with mock' }

def _mock_get(tgt, fun, tgt_type='glob', exclude_minion=False, expr_form=None):
    global mine_data
    log.info('MOCK: Fetching {0!r} for {1}'.format(fun, tgt))
    if tgt not in mine_data:
        log.warn('Cannot find target {} in mine.'.format(tgt))
        return {}
    d = mine_data[tgt]
    if fun not in d:
        log.warn('Cannot find target {} with function {} in mine.'.format(tgt, fun))
        return {}
    # TODO(ppg): allow lookup based on arg too
    d = d[fun]
    return { tgt: d }

def remote_functions(name):
    global remote_functions_data
    # FIXME(ppg): drive via configuration
    for file in glob.glob('/tmp/kitchen/srv/remote_functions/*'):
        remote_functions_data.update(yaml.load(open(file)))
    __salt__['publish.publish'] = _mock_publish
    return { 'name': 'remote_functions', 'changes': {}, 'result': True, 'comment': 'Replaced publish.publish with mock' }

def _mock_publish(tgt, fun, arg=None, tgt_type='glob', returner='', timeout=5, via_master=None, expr_form=None):
    global remote_functions_data
    log.info('MOCK: Publishing {0!r} for {1}'.format(fun, tgt))
    if tgt not in remote_functions_data:
        raise SaltInvocationError(message='Cannot find target {} in remote functions.'.format(tgt))
    d = remote_functions_data[tgt]
    if fun not in d:
        raise SaltInvocationError(message='Cannot find target {} with function {} in remote functions.'.format(tgt, fun))
    # TODO(ppg): allow lookup based on arg too
    d = d[fun]
    return { tgt: d }
