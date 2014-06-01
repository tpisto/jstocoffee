js2c = require('parser.coffee')
fs = require 'fs'

str = '''
0 instanceof a;
!(1 instanceof a);
!!(2 instanceof a);
!!!(3 instanceof a);
if(a instanceof b) 4;
if(!(a instanceof b)) 5;
!(6 instanceof a) || b;
(!(7 instanceof a)) + b;
if(!(a instanceof b) || c) 8;
if(!(a instanceof b) + c) 9;
'''

console.log "\n--------\n"
output = js2c.parse(str, true)
output = js2c.parse(str)
console.log str
console.log "\n--------\n"
console.log output
console.log "\n--------\n"

fs.writeFileSync('dev-output.coffee',output)