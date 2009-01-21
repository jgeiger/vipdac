# Enable the will_paginate plugin
require 'will_paginate'

require 'constants'
require 'zip/zip'
require 'zip/zipfilesystem'
require 'right_aws'
require 'right_http_connection'
require 'sdb/active_sdb'
require 'yaml'
require 'fileutils'
require 'utilities'
require 'digest/sha1'
require 'digest/md5'
require 'beanstalk-client'

TandemParameterFile.import_from_simpledb
OmssaParameterFile.import_from_simpledb
