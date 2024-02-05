#!/usr/bin/python3

import os
import sys
import pwd
import subprocess
import stat
import time
import json
import glob
import tempfile
import re

import logging
import logging.handlers

try:
    import htcondor
except ImportError:
    htcondor = None

try:
    import requests
except ImportError:
    requests = None

from cryptography.fernet import Fernet
from flaat import Flaat

sys.path.append('/usr/libexec/condor')
from credmon.CredentialMonitors.AbstractCredentialMonitor import AbstractCredentialMonitor
from credmon.utils import atomic_rename

class MytokenCredmon(AbstractCredentialMonitor):

    def __init__(self, *args, **kw):
        super(MytokenCredmon, self).__init__(*args, **kw)
        self.logger = None
        self.encryption_key = None
        self.encryption_key_file = None
        self.access_token_time = 0
        self.access_token_lifetime = 0

    def should_renew(self, user_name, access_token_name):

        access_token_path = os.path.join(self.cred_dir, user_name, access_token_name + '.use')
        self.logger.debug(' Access token credential file: %s \n', access_token_path)

        # renew access token if credential does not exist
        if not os.path.exists(access_token_path):
            return True

        # retrieve access token life time (return true for renewal - if credential information can not be retrieved)
        self.get_access_token_time(access_token_path)

        # retrieve period at which the credd is checking the access token remaining life time
        if (htcondor is not None) and ('CRED_CHECK_INTERVAL' in htcondor.param):
            credd_checking_period = int(htcondor.param['CRED_CHECK_INTERVAL'])
            self.logger.debug(' Period at which the credd is checking the access token remaining life time: %d seconds \n', credd_checking_period)
        else:
            raise RuntimeError(' The parameter CRED_CHECK_INTERVAL is not defined in the configuration \n')

        # determine threshold for renewal
        threshold_renewal = int(1.2*credd_checking_period)

        self.logger.debug(' Access token life time: %d seconds \n', self.access_token_lifetime)
        self.logger.debug(' Access token remaining life time: %d seconds \n', self.access_token_time)
        self.logger.debug(' Access token threshold for renewal: %d seconds \n', threshold_renewal)

        # renew access token if remaining life time is smaller than threshold for renewal
        return (self.access_token_time < threshold_renewal)

    def should_delete(self, user_name, token_name):

        flaat = Flaat()

        mytoken_path = os.path.join(self.cred_dir, user_name, token_name + '.top')

        try:
            with open(mytoken_path, "rb") as file:
                crypto = Fernet(self.encryption_key)
                mytoken_encrypted = file.read()
                mytoken_decrypted = crypto.decrypt(mytoken_encrypted)
                mytoken_info = flaat.get_info_thats_in_at(mytoken_decrypted.decode('utf-8'))

                if mytoken_info is None:
                    self.logger.error(' Mytoken credential information is absent \n')
                    raise SystemExit(' Mytoken credential information is absent \n')
                else:
                    self.logger.debug(' Information retrieved from Mytoken credential file: %s \n', mytoken_info)

        except BaseException as error:
            self.logger.error(' Could not retrieve Mytoken credential information: %s \n', error)
            raise SystemExit(' Could not retrieve Mytoken credential information: %s \n', error)       

        mytoken_time = int(mytoken_info['body']['exp'] - time.time())
        mytoken_lifetime =  int(mytoken_info['body']['exp'] - mytoken_info['body']['iat'])

        # determine threshold for credential deletion
        threshold_deletion = int(0.01*mytoken_lifetime)
        self.logger.debug(' Mytoken life time: %d seconds \n', mytoken_lifetime)
        self.logger.debug(' Mytoken remaining life time: %d seconds \n', mytoken_time)
        self.logger.debug(' Threshold for credential deletion: %d seconds \n', threshold_deletion)

        # delete user credential directory if remaining life time is smaller than threshold for credential deletion
        return (mytoken_time < threshold_deletion)

    def refresh_access_token(self, user_name, token_name):
        flaat = Flaat()

        # renew access token
        mytoken_path = os.path.join(self.cred_dir, user_name, token_name + '.top')

        try:
            with open(mytoken_path, "rb") as file:
                crypto = Fernet(self.encryption_key)
                mytoken_encrypted = file.read()
                mytoken_decrypted = crypto.decrypt(mytoken_encrypted)
                self.logger.debug(' Mytoken credential has been decrypted: %s\n', mytoken_decrypted.decode('utf-8'))

                access_token_cmd = 'mytoken AT --MT ' + mytoken_decrypted.decode('utf-8')
                new_access_token = subprocess.run(access_token_cmd.split(), stdout=subprocess.PIPE).stdout.decode('ascii').strip('\n')
        except BaseException as error:
            self.logger.error(' Could not renew access token credential: %s \n', error)
            raise SystemExit(' Could not renew access token credential: %s \n', error)

        # write new access token to tmp file
        try:
            (tmp_fd, tmp_access_token_path) = tempfile.mkstemp(dir = self.cred_dir)
            with os.fdopen(tmp_fd, 'w') as tmp_file:
                tmp_file.write(new_access_token)
                self.logger.debug(' New access token credential has been written to tmp file \n')
        except BaseException as error:
            self.logger.error(' Could not write new access token credential to tmp file: %s \n', error)

        # atomically move new access token to dedicated directory
        access_token_path = os.path.join(self.cred_dir, user_name, token_name + '.use')
        try:
            atomic_rename(tmp_access_token_path, access_token_path)
            self.logger.debug(' Access token credential file has been successfully renewed \n')
            self.logger.debug(' Old access token remaining life time: %s seconds \n', self.access_token_time)
            self.get_access_token_time(access_token_path)
            self.logger.debug(' New access token remaining life time: %s seconds \n', self.access_token_time)
        except OSError as error:
            self.logger.error(' Access token credential file could not be renewed: %s \n', error.strerror)

    def delete_mark_files(self):

        for file in os.listdir(self.cred_dir):
            if re.search(".mark",file):
                file_path = os.path.join(self.cred_dir,file)
                try:
                    os.unlink(file_path)
                    self.logger.debug(' Mark file %s has been successfully removed \n', file_path)
                except OSError as error:
                    self.logger.error(' Mark file %s could not be removed: %s \n', file_path, error.strerror)

    def delete_user_credentials(self, user_name, access_token_name):

        # delete mytoken and access token
        extensions = ['.top', '.use']
        base_path = os.path.join(self.cred_dir, user_name, access_token_name)

        for ext in extensions:            
            file_path = base_path + ext

            if os.path.exists(file_path):
                try:
                    os.unlink(file_path)
                    self.logger.debug(' Credential file %s has been successfully removed \n', file_path)
                except OSError as error:
                    self.logger.error(' Credential file %s could not be removed: %s \n', file_path, error.strerror)
            else:
                self.logger.error(' Credential file %s could not be found \n', file_path)

        # delete user credential directory
        user_cred_dir_path = os.path.join(self.cred_dir, user_name)
        if os.path.isdir(user_cred_dir_path):
            try:
                os.rmdir(user_cred_dir_path)
                self.logger.debug(' User credential directory %s has been successfully removed \n', user_cred_dir_path)
            except OSError as error:
                self.logger.error(' User credential directory %s could not be removed: %s \n', user_cred_dir_path, error.strerror)
        else:
            self.logger.error(' User credential directory %s could not be found \n', user_cred_dir_path)

    def check_access_token(self, access_token_path):

        # retrieve access token, user and provider
        basename, filename = os.path.split(access_token_path)
        user_name = os.path.split(basename)[1] # strip SEC_CREDENTIAL_DIRECTORY_OAUTH
        access_token_name = os.path.splitext(filename)[0] # strip .use

        self.logger.debug(' ### User name: %s ### \n', user_name)
        self.logger.debug(' Credential directory: %s \n', self.cred_dir)
        self.logger.debug(' Access token credential name: %s \n', access_token_name)

        # delete user credential directory if needed
        if self.should_delete(user_name, access_token_name):
            self.delete_user_credentials(user_name, access_token_name)

        # renew access token if needed
        elif self.should_renew(user_name, access_token_name):
            self.refresh_access_token(user_name, access_token_name)

        # delete mark file if present
        self.delete_mark_files()

    def scan_tokens(self):

        self.logger.debug(' Scanning the access token credential directory: %s \n', self.cred_dir)
        self.logger.debug(' Looking for access token credentials: %s \n', os.path.join(self.cred_dir, '*', '*.use'))

        # loop over all access tokens in the cred_dir
        access_token_files = glob.glob(os.path.join(self.cred_dir, '*', '*.use'))
        self.logger.debug(' The following access token credentials have been found: %s \n', access_token_files)

        for access_token_path in access_token_files:
            self.check_access_token(access_token_path)

    def retrieve_cred_dir(self):

        # retrieve access token directory
        if (htcondor is not None) and ('SEC_CREDENTIAL_DIRECTORY_OAUTH' in htcondor.param):
            self.cred_dir = htcondor.param.get('SEC_CREDENTIAL_DIRECTORY_OAUTH')
        else:
            raise RuntimeError(' The access token credential directory is not defined in the configuration \n')

        # check access token directory permissions
        try:
            if (os.stat(self.cred_dir).st_mode & (stat.S_IROTH | stat.S_IWOTH | stat.S_IXOTH)):
                self.logger.error(' The access token credential directory is readable and/or writable by others \n')
                raise RuntimeError(' The access token credential directory is readable and/or writable by others \n')
        except OSError:
            self.logger.error(' The credmon cannot verify the permissions of the access token credential directory \n')
            raise RuntimeError(' The credmon cannot verify the permissions of the access token credential directory \n')

        if not os.access(self.cred_dir, (os.R_OK | os.W_OK | os.X_OK)):
            self.logger.error(' The credmon cannot access the access token credential directory \n')
            raise RuntimeError(' The credmon cannot access the access token credential directory \n')

        self.logger.debug(' The access token credential directory has been retrieved successfully: %s \n', self.cred_dir)
        return self.cred_dir

    def get_encryption_key(self):
        if (htcondor is not None) and ('SEC_ENCRYPTION_KEY_DIRECTORY' in htcondor.param):
            self.encryption_key_file = htcondor.param.get('SEC_ENCRYPTION_KEY_DIRECTORY')
            try:
                with open(self.encryption_key_file, "r") as file:
                    self.encryption_key = str.encode(file.read())
                    self.logger.debug(' Encryption key for Fernet algorithm has been retrieved \n')
            except BaseException as error:
                self.logger.error(' Could not retrieve encryption key for Fernet algorithm: %s \n', error)
                raise SystemExit(' Could not retrieve encryption key for Fernet algorithm: %s \n', error)
        else:
            raise RuntimeError(' The encryption key for Fernet algorithm is not defined in the configuration \n')

    def get_access_token_time(self, access_token_path):
        flaat = Flaat()
        try:
            with open(access_token_path, "r") as file:
                token_data = file.read()
                access_token_info = flaat.get_info_thats_in_at(token_data)
                if access_token_info is None:
                    self.logger.error(' Access token credential information is absent \n')
                    return True # return true for renewal - if credential information is absent
                else:
                    self.logger.debug(' Information retrieved from access token credential file: %s \n', access_token_info)
        except BaseException as error:
            self.logger.error(' Access token credential information could not be retrieved: %s \n', error)
            return True # return true for renewal - if credential information can not be retrieved

        self.access_token_time = int(access_token_info['body']['exp'] - time.time())
        self.access_token_lifetime = int(access_token_info['body']['exp'] - os.path.getmtime(access_token_path))


    def setup_logger(self):

        # log_path
        if (htcondor is not None) and ('CREDMON_OAUTH_LOG' in htcondor.param):
            log_path = htcondor.param.get('CREDMON_OAUTH_LOG')
        else:
            print(' Please define the parameter CREDMON_OAUTH_LOG \n')
            return

        # log_level
        if (htcondor is not None) and ('CREDMON_OAUTH_LOG_LEVEL' in htcondor.param):
            log_level = logging.getLevelName(htcondor.param['CREDMON_OAUTH_LOG_LEVEL'])
        else:
            log_level = logging.INFO

        # logger
        root_logger = logging.getLogger()
        root_logger.setLevel(log_level)

        log_format = '%(asctime).19s - ' + pwd.getpwuid(os.getuid())[0] + ' - %(name)s - %(levelname)s - %(message)s'

        old_euid = os.geteuid()
        try:
            condor_euid = pwd.getpwnam("condor").pw_uid
            os.seteuid(condor_euid)
        except:
            pass

        try:
            log_handler = logging.handlers.WatchedFileHandler(log_path)
            log_handler.setFormatter(logging.Formatter(log_format))
            root_logger.addHandler(log_handler)

            # child logger
            self.logger = logging.getLogger(os.path.basename(sys.argv[0]) + '.' + self.__class__.__name__)

        finally:
            try:
                os.seteuid(old_euid)
            except:
                pass

        return self.logger
    