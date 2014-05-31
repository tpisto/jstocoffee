js2c = require('parser.coffee')
fs = require 'fs'

str = '''
for (x=0; !x<2; x++) { alert(1) }
for (; !x<2; ) { alert(1) }
for (;;++x) { alert(1) }
for (;;) { alert(1) }
'''

console.log "\n--------\n"
output = js2c.parse(str, true)
output = js2c.parse(str)
console.log str
console.log "\n--------\n"
console.log output
console.log "\n--------\n"

fs.writeFileSync('dev-output.coffee',output)