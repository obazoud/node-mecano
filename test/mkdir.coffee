
fs = require 'fs'
path = require 'path'
fs.exists ?= path.exists
should = require 'should'
mecano = if process.env.MECANO_COV then require '../lib-cov/mecano' else require '../lib/mecano'
misc = if process.env.MECANO_COV then require '../lib-cov/misc' else require '../lib/misc'
test = require './test'
they = require 'superexec/lib/they'
connect = require 'superexec/lib/connect'

describe 'mkdir', ->

  scratch = test.scratch @

  they 'should create dir', (ssh, next) ->
    source = "#{scratch}/a_dir"
    mecano.mkdir
      ssh: ssh
      directory: source
    , (err, created) ->
      return next err if err
      created.should.eql 1
      mecano.mkdir
        ssh: ssh
        directory: source
      , (err, created) ->
        return next err if err
        created.should.eql 0
        next()

  it 'should take source if first argument is a string', (next) ->
    source = "#{scratch}/a_dir"
    mecano.mkdir source, (err, created) ->
      return next err if err
      created.should.eql 1
      mecano.mkdir source, (err, created) ->
        return next err if err
        created.should.eql 0
        next()
  
  they 'should create dir recursively', (ssh, next) ->
    source = "#{scratch}/a_parent_dir/a_dir"
    mecano.mkdir
      ssh: ssh
      directory: source
    , (err, created) ->
      return next err if err
      created.should.eql 1
      next()
  
  they 'should create multiple directories', (ssh, next) ->
    mecano.mkdir
      ssh: ssh
      destination: [
        "#{scratch}/a_parent_dir/a_dir_1"
        "#{scratch}/a_parent_dir/a_dir_2"
      ]
    , (err, created) ->
      return next err if err
      created.should.eql 2
      next()
  
  they 'should stop when `exclude` match', (ssh, next) ->
    source = "#{scratch}/a_parent_dir/a_dir/do_not_create_this"
    mecano.mkdir
      ssh: ssh
      directory: source
      exclude: /^do/
    , (err, created) ->
      return next err if err
      created.should.eql 1
      misc.file.exists ssh, source, (err, created) ->
        created.should.not.be.ok
        source = path.dirname source
        misc.file.exists ssh, source, (err, created) ->
          created.should.be.ok 
          next()

  they 'should honore `cwd` for relative paths', (ssh, next) ->
    mecano.mkdir
      ssh: ssh
      directory: './a_dir'
      cwd: scratch
    , (err, created) ->
      return next err if err
      created.should.eql 1
      misc.file.exists ssh, "#{scratch}/a_dir", (err, created) ->
        created.should.be.ok
        next()

  they 'change mode as string', (ssh, next) ->
    # 40744: 4 for directory, 744 for permissions
    @timeout 10000
    mecano.mkdir
      ssh: ssh
      directory: "#{scratch}/ssh_dir_string"
      mode: '744'
    , (err, created) ->
      return next err if err
      misc.file.stat ssh, "#{scratch}/ssh_dir_string", (err, stat) ->
        return next err if err
        stat.mode.toString(8).should.eql '40744'
        next()

  they 'change mode as string', (ssh, next) ->
    # 40744: 4 for directory, 744 for permissions
    @timeout 10000
    mecano.mkdir
      ssh: ssh
      directory: "#{scratch}/ssh_dir_string"
      mode: 0o744
    , (err, created) ->
      return next err if err
      misc.file.stat ssh, "#{scratch}/ssh_dir_string", (err, stat) ->
        return next err if err
        stat.mode.toString(8).should.eql '40744'
        next()

  they 'detect a permission change', (ssh, next) ->
    # 40744: 4 for directory, 744 for permissions
    @timeout 10000
    mecano.mkdir
      ssh: ssh
      directory: "#{scratch}/ssh_dir_string"
      mode: 0o744
    , (err, created) ->
      return next err if err
      mecano.mkdir
        ssh: ssh
        directory: "#{scratch}/ssh_dir_string"
        mode: 0o755
      , (err, created) ->
        return next err if err
        created.should.be.ok
        mecano.mkdir
          ssh: ssh
          directory: "#{scratch}/ssh_dir_string"
          mode: 0o755
        , (err, created) ->
          return next err if err
          created.should.not.be.ok
          next()


