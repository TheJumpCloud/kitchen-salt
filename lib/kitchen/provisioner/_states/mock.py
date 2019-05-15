from __future__ import absolute_import
import ast
import glob
import yaml
import salt.utils.args

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
    return {'name': 'mine', 'changes': {}, 'result': True, 'comment': 'Replaced mine.get with mock'}


def _parse_args(arg):
    '''
    yamlify `arg` and ensure it's outermost datatype is a list
    '''
    yaml_args = salt.utils.args.yamlify_arg(arg)

    if yaml_args is None:
        return []
    elif not isinstance(yaml_args, list):
        return [yaml_args]
    else:
        return yaml_args


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
    return {tgt: d}


def remote_functions(name):
    global remote_functions_data
    # FIXME(ppg): drive via configuration
    for file in glob.glob('/tmp/kitchen/srv/remote_functions/*'):
        remote_functions_data.update(yaml.load(open(file)))
    __salt__['publish.publish'] = _mock_publish
    return {'name': 'remote_functions', 'changes': {}, 'result': True, 'comment': 'Replaced publish.publish with mock'}


def _mock_publish(tgt, fun, arg=None, tgt_type='glob', returner='', timeout=5, via_master=None, expr_form=None):
    global remote_functions_data
    log.info('MOCK: Publishing {0!r} for {1}'.format(fun, tgt))
    log.debug('MOCK: Publish args: {0!r}'.format(arg))
    kwargs = salt.utils.args.yamlify_arg(arg)
    log.debug('MOCK: args after yamlify: {0}'.format(kwargs))

    # Special case some functions for convinient usage
    # TODO(ppg): allow custom python files provided to override a function
    #   mock_remote_functions:
    #     'x509.sign_remote_certificate': mock_sign_remote_certificate.py
    if fun == 'x509.sign_remote_certificate':
        # if salt.utils.args.yamlify failed to make a dict, try ast
        if not isinstance(kwargs, dict):
            kwargs = ast.literal_eval(kwargs)
        kwargs['text'] = True
        log.debug('MOCK: sending certificate kwargs: {0}'.format(kwargs))
        return {tgt: mock_sign_remote_certificate(**kwargs)}

    if tgt not in remote_functions_data:
        raise SaltInvocationError(
            message='Cannot find target {} in remote functions.'.format(tgt))
    d = remote_functions_data[tgt]
    if fun not in d:
        raise SaltInvocationError(
            message='Cannot find target {} with function {} in remote functions.'.format(tgt, fun))
    d = d[fun]
    if 'ret' not in d:
        raise SaltInvocationError(
            message="target {} function {} is missing 'ret' field".format(tgt, fun))
    # TODO(ppg): allow lookup based on arg too
    d = d['ret']
    return {tgt: d}


def mock_sign_remote_certificate(**kwargs):
    return __salt__['x509.create_certificate'](**kwargs)
