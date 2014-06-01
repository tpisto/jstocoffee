js2c = require('parser.coffee')
fs = require 'fs'

str = '''
(function($) { return new jQuery.fn.init( selector, context ); })(jQuery);
'''

console.log "\n--------\n"
output = js2c.parse(str, true)
output = js2c.parse(str)
console.log str
console.log "\n--------\n"
console.log output
console.log "\n--------\n"

fs.writeFileSync('dev-output.coffee',output)