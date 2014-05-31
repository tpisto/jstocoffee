PEG = require 'pegjs'
fs = require 'fs'
util = require 'util'
J2C = {}

class J2C.SyntaxTree
  constructor: (parent, tree) ->
    @tree = tree;  
    @parent = parent
    @childs = []
    @create()

  tabStr: (str) -> 
    ret = ""
    tabChars = new Array(3).join(' ')    
    mySplit = str.split("\n")
    for s in mySplit
      if s.length <= 0
        ret += "\n"
      else
        ret += "#{tabChars}#{s}\n"
    return ret

  trimFirst: (str) ->
    if str.charAt(1) == "\n" then return str.substring(1)
    else return str

  create: () ->
    return    

class J2C.BlockStatement extends J2C.SyntaxTree
  create: () ->
    @childs = []
    for t in @tree.body
      @childs.push new J2C[t.type](this, t)

  getCoffee: () ->  
    ret = []
    for c in @childs      
      ret.push c.getCoffee()
    return @tabStr "\n#{ret.join("\n")}"

class J2C.Program extends J2C.SyntaxTree
  constructor: (parent, tree) ->    
    super(parent, tree)

  create: () ->
    @childs = []
    for t in @tree.body
      @childs.push new J2C[t.type](this, t)

  getCoffee: () ->
    ret = []
    for c in @childs      
      ret.push c.getCoffee()
    return ret.join("\n")

class J2C.VariableDeclaration extends J2C.SyntaxTree
  create: () ->
    @declarations = []
    for t in @tree.declarations
      @declarations.push(new J2C[t.type](this, t))

  getCoffee: () ->
    ret = []
    for d in @declarations
      ret.push d.getCoffee()
    return ret.join("\n")

class J2C.VariableDeclarator extends J2C.SyntaxTree
  create: () ->
    @id = new J2C[@tree.id.type](this, @tree.id)
    if @tree.init? then @init = new J2C[@tree.init.type](this, @tree.init)
  
  getCoffee: () ->
    init = if @init? then @init.getCoffee() else undefined
    return "#{@id.getCoffee()} = #{init}"

class J2C.ExpressionStatement extends J2C.SyntaxTree
  create: () ->
    @expression = new J2C[@tree.expression.type](this, @tree.expression)
  getCoffee: () ->
    return @expression.getCoffee()

class J2C.CallExpression extends J2C.SyntaxTree
  create: () ->
    @callee = new J2C[@tree.callee.type](this, @tree.callee)
    # Arguments
    @arguments = []
    for a in @tree.arguments
      @arguments.push(new J2C[a.type](this, a))

  getCoffee: () ->
    ret = @callee.getCoffee()
    arg = []

    # If FunctionExpression, wrap to parenthesis
    if @callee instanceof J2C.FunctionExpression then ret = "(#{ret})"

    if @arguments.length <= 0
      ret += '()'
    else
      for a in @arguments
        arg.push a.getCoffee()
      myArgs = arg.join(', ')

      # If MemberExpression, use parenthesis
      if @parent instanceof J2C.MemberExpression then ret += "(#{myArgs})"
      else ret += @trimFirst(" #{myArgs}")
      
    return ret

class J2C.ReturnStatement extends J2C.SyntaxTree
  create: () ->
    if @tree.argument? then @argument = new J2C[@tree.argument.type](this, @tree.argument)

    # Flag that function has return statement
    if @parent.parent instanceof J2C.FunctionExpression
      @parent.parent.hasReturn = true

  getCoffee: () ->
    # Check if return is in last line
    if @parent instanceof J2C.BlockStatement
      if @parent.childs[@parent.childs.length-1] instanceof J2C.ReturnStatement
        @isLastLine = true
    
    returnString = if @isLastLine then '' else 'return '

    if @argument?
      return "#{returnString}#{@argument.getCoffee()}"
    else 
      return returnString.trim()

class J2C.MemberExpression extends J2C.SyntaxTree
  create: () ->
    @object = new J2C[@tree.object.type](this, @tree.object)
    @property = new J2C[@tree.property.type](this, @tree.property)
    @computed = @tree.computed

  getCoffee: () ->
    if !@computed
      dot = if @object instanceof J2C.ThisExpression then '' else '.'
      return "#{@object.getCoffee()}#{dot}#{@property.getCoffee()}"  
      return "#{@object.getCoffee()}.#{@property.getCoffee()}"
    else 
      return "#{@object.getCoffee()}[#{@property.getCoffee()}]"

class J2C.ObjectExpression extends J2C.SyntaxTree
  create: () ->
    @properties = []
    for t in @tree.properties
      @properties.push { key: new J2C[t.key.type](this, t.key), value: new J2C[t.value.type](this, t.value) }

  getCoffee: () ->  
    ret = []
    for c in @properties      
      ret.push "#{c.key.getCoffee()}: #{c.value.getCoffee()}"
    if @properties.length > 1
      return @tabStr "\n#{ret.join("\n")}"
    else 
      return ret[0]

class J2C.UnaryExpression extends J2C.SyntaxTree
  create: () ->
    @operator = @tree.operator
    @argument = new J2C[@tree.argument.type](this, @tree.argument)

  getCoffee: () ->
    return "#{@operator} #{@argument.getCoffee()}"

class J2C.DebuggerStatement extends J2C.SyntaxTree
  getCoffee: () ->
    return "debugger"

class J2C.Identifier extends J2C.SyntaxTree
  getCoffee: () ->    
    return @convertReserved @tree.name
  
  # Add underscore to identifier names that are conflicting with CoffeeScript reserved words
  convertReserved: (str) ->
    reserved = ['off', 'yes', 'is', 'isnt', 'not', 'and', 'or']
    for r in reserved
      if str == r then return str + '_'
    return str

class J2C.Literal extends J2C.SyntaxTree
  getCoffee: () ->
    if typeof @tree.value == 'string'
      return "\"#{@tree.value}\""
    else 
      return @tree.value

class J2C.FunctionExpression extends J2C.SyntaxTree
  create: () ->
    @hasReturn = false
    if @tree.id? then @id = new J2C[@tree.id.type](this, @tree.id)
    # Function parameters
    @params = []
    for p in @tree.params
      @params.push(new J2C[p.type](this, p))
    # Function body
    @body = new J2C[@tree.body.type](this, @tree.body)

  getCoffee: () ->
    ret = ''
    # Identifier
    if @id?
      ret += @id.getCoffee() + ' = '
    # Paramaters
    param = []
    for p in @params
      param.push p.getCoffee()
    if param.length > 0
      ret += "(#{param.join(', ')}) ->"
    else 
      ret += '->'

    # Add return to body block, if no return statement found
    if !@hasReturn
      @body.childs.push new J2C.ReturnStatement(this, { type: 'ReturnStatement', argument: null })

    ret += @body.getCoffee()    
    return ret

class J2C.BinaryExpression extends J2C.SyntaxTree
  create: () ->
    @left = new J2C[@tree.left.type](this, @tree.left)
    @right = new J2C[@tree.right.type](this, @tree.right)
    @operator = @tree.operator

  getCoffee: () ->
    ret = "#{@left.getCoffee()} #{@operator} #{@right.getCoffee()}"
    if @parent instanceof J2C.BinaryExpression and ((@left instanceof J2C.Literal or @left instanceof J2C.Identifier) or (@right instanceof J2C.Literal or @right instanceof J2C.Identifier))
      ret = "(#{ret})"
    return ret

class J2C.UpdateExpression extends J2C.SyntaxTree
  create: () ->
    @operator = @tree.operator
    @argument = new J2C[@tree.argument.type](this, @tree.argument)

  getCoffee: () ->
    return "#{@argument.getCoffee()}#{@operator}"

class J2C.AssignmentExpression extends J2C.SyntaxTree
  create: () ->
    @left = new J2C[@tree.left.type](this, @tree.left)
    @right = new J2C[@tree.right.type](this, @tree.right)
    @operator = @tree.operator

  getCoffee: () ->
    return "#{@left.getCoffee()} #{@operator} #{@right.getCoffee()}"

class J2C.ThisExpression extends J2C.SyntaxTree
  getCoffee: () ->
    return '@'

class J2C.ArrayExpression extends J2C.SyntaxTree
  create: () ->
    @elements = []
    for e in @tree.elements
      @elements.push new J2C[e.type](this, e)

  getCoffee: () ->  
    if @elements.length > 0
      ret = []
      for e in @elements      
        ret.push e.getCoffee()
      return "[#{ret.join(',')}]"
    else 
      return '[]'

class J2C.DoWhileStatement extends J2C.SyntaxTree
  create: () ->
    @body = new J2C[@tree.body.type](this, @tree.body)
    @body.childs.push new J2C.BreakUnless(this, @tree)

  getCoffee: () ->
    return "loop#{@body.getCoffee()}"

class J2C.BreakUnless extends J2C.SyntaxTree
  create: () ->
    @test = new J2C[@tree.test.type](this, @tree.test)
  getCoffee: () ->
    return "break unless #{@test.getCoffee()}"    

class J2C.FunctionDeclaration extends J2C.FunctionExpression

class J2C.EmptyStatement extends J2C.SyntaxTree
  getCoffee: () ->
    return ''

class J2C.Main
  
  constructor: () ->
    @file = fs.readFileSync("#{__dirname}/javascript.pegjs").toString()
    @parser = PEG.buildParser(@file)

  getSyntaxTree: () ->
    return @syntaxTree

  getCoffee: () ->
    return @classTree.getCoffee()

  showTree: () ->
    console.log util.inspect(@getSyntaxTree(), {showHidden: false, depth: null})
    console.log "\n--------\n"

  parse: (parseStr, show) ->
    if show?
      @syntaxTree = @parser.parse parseStr
      @showTree()
      return
    @syntaxTree = @parser.parse parseStr
    @classTree = new J2C.Program(this, @syntaxTree)
    return @classTree.getCoffee().trim()

module.exports = new J2C.Main()
