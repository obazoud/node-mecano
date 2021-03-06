
should = require 'should'
mecano = if process.env.MECANO_COV then require '../lib-cov/mecano' else require '../lib/mecano'
misc = if process.env.MECANO_COV then require '../lib-cov/misc' else require '../lib/misc'
test = require './test'

describe 'mecano', ->

  scratch = test.scratch @

  it 'should chain with error and end', (next) ->
    result = mecano
    .mkdir
      content: 'hello'
      destination: "#{scratch}/chain"
    .write
      content: 'hello'
      destination: "#{scratch}/chain/file"
    .write
      content: 'world'
      destination: "#{scratch}/chain/file"
      append: true
    .on 'error', (err) ->
      next err
    .on 'end', ->
      misc.file.readFile null, "#{scratch}/chain/file", 'utf8', (err, content) ->
        return next err if err
        content.should.eql 'helloworld'
        next()

  it 'should chain with both', (next) ->
    result = mecano
    .mkdir
      content: 'hello'
      destination: "#{scratch}/chain"
    .write
      content: 'hello'
      destination: "#{scratch}/chain/file"
    .write
      content: 'world'
      destination: "#{scratch}/chain/file"
      append: true
    .on 'both', (err) ->
      return next err if err
      misc.file.readFile null, "#{scratch}/chain/file", 'utf8', (err, content) ->
        return next err if err
        content.should.eql 'helloworld'
        next()

  it 'should handle error with error and end', (next) ->
    result = mecano
    .mkdir
      content: 'hello'
      destination: "#{scratch}/chain"
    .execute
      content: 'hello'
      cmd: "cd #{scratch}/should_not_exist"
    .write
      content: 'world'
      destination: "#{scratch}/chain/file"
      append: true
    .on 'error', (err) ->
      next()
    .on 'end', ->
      false.should.be.ok

  it 'should handle error with both', (next) ->
    result = mecano
    .mkdir
      content: 'hello'
      destination: "#{scratch}/chain"
    .execute
      content: 'hello'
      cmd: "cd #{scratch}/should_not_exist"
    .write
      content: 'world'
      destination: "#{scratch}/chain/file"
      append: true
    .on 'both', (err, modified)->
      next()
    result.id = 'toto'

