js2c = require('../parser.coffee')
glob = require('glob').globSync or require('glob').sync
fs = require('fs')
_ = require('underscore')
joe = require('joe')
assert = require('assert')
ansidiff = require('ansidiff')

files = glob(__dirname+'/done/*.js')

joe.suite 'js2coffee', (suite,test) ->
  _.each files, (f) ->
    test f, ->

      input = fs.readFileSync(f).toString().trim()
      output = js2c.parse(input)

      expected = fs.readFileSync(f.replace('.js', '.coffee')).toString().trim()

      if output isnt expected
        # show colored diff
        console.error ansidiff.lines output, expected

      assert.equal(output, expected)
