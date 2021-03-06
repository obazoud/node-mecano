
should = require 'should'
misc = if process.env.MECANO_COV then require '../lib-cov/misc' else require '../lib/misc'
test = require './test'
they = require 'superexec/lib/they'


describe 'ini', ->

  describe 'multi brackets', ->

    it 'parse style', ->
      res = misc.ini.parse_multi_brackets """
      ###########################################################################
      # Some comments

      [group1]
        
        key1a="value1a"

        # comment
        key1b=1

        # Administrators
        # ----------------
        [[group1a1]]
          ## [[[admin1aX]]]
          key1a1 = value1a1
        [[group1b]]
          # comment = value
          ## double comment = value
          key1b1 = value1b1
      [group2]
        key1=value1b
      """
      res.should.eql
        '###########################################################################': null
        '# Some comments': null
        group1:
          key1a: '"value1a"'
          '# comment': null
          key1b: '1'
          '# Administrators': null
          '# ----------------': null
          group1a1:
            '## [[[admin1aX]]]': null
            key1a1: 'value1a1'
          group1b:
            '# comment': 'value'
            '## double comment': 'value'
            key1b1: 'value1b1'
        group2:
          key1: 'value1b'

    it 'parse style with comment', ->
      res = misc.ini.parse_multi_brackets """
      # Some = comments
      [group1]
        [[group1b]]
          # comment = value
          ## double comment = value
          key1b1 = value1b1
      [group2]
        key1=value1b
      """, comment: '#'
      res.should.eql
        '# Some = comments': null
        group1:
          group1b:
            '# comment = value': null
            '## double comment = value': null
            key1b1: 'value1b1'
        group2:
          key1: 'value1b'

    it 'stringify style', ->
      res = misc.ini.stringify_multi_brackets 
        '###########################################################################': null
        '# Some comments': null
        group1:
          key1a: '"value1a"'
          '# comment': null
          key1b: '1'
          '# Administrators': null
          '# ----------------': null
          group1a1:
            '## [[[admin1aX]]]': null
            key1a1: 'value1a1'
          group1b:
            '# comment': 'value'
            '## double comment': 'value'
            key1b1: 'value1b1'
        group2:
          key1: 'value1b'
      res.should.eql """
      ###########################################################################
      # Some comments
      [group1]
        key1a = "value1a"
        # comment
        key1b = 1
        # Administrators
        # ----------------
        [[group1a1]]
          ## [[[admin1aX]]]
          key1a1 = value1a1
        [[group1b]]
          # comment = value
          ## double comment = value
          key1b1 = value1b1
      [group2]
        key1 = value1b

      """

  describe 'square and curly brackets', ->

    it 'stringify', ->
      res = misc.ini.stringify_square_then_curly 
        user: preference: color: true
        group:
          name: 'us'
      res.should.eql '[user]\n preference = {\n  color = true\n }\n\n[group]\n name = us\n\n'

