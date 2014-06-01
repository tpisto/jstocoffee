PEG = require 'pegjs'
fs = require 'fs'
util = require 'util'
J2C = {}

class J2C.SyntaxTree
  constructor: (parent, tree) ->
    @type = tree.type
    @tree = tree;  
    @parent = parent
    @childs = []
    @tabSpace = 2
    @tabChars = new Array(@tabSpace+1).join(' ')    
    @create()

  tabStr: (str) -> 
    ret = ""
    tabChars = new Array(@tabSpace+1).join(' ')    
    mySplit = str.split("\n")
    for s in mySplit
      if s.trim().length <= 0
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
      myClass = new J2C[t.type](this, t)      
      # Do not add empty statements
      if !(myClass instanceof J2C.EmptyStatement)
        @childs.push myClass

  getCoffee: () -> 
    ret = []
    for c in @childs
      ret.push c.getCoffee()    
    return @tabStr "\n#{ret.join("\n")}"

class J2C.Program extends J2C.SyntaxTree
  create: () ->
    @childs = []
    for t in @tree.body
      myClass = new J2C[t.type](this, t)      
      # Do not add empty statements
      if !(myClass instanceof J2C.EmptyStatement)
        @childs.push myClass

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

    # Flag last return to function
    @findParent(@parent)?.lastReturn = this

  getCoffee: () ->
    returnString = 'return '
    # Check if return is in last line
    if @parent instanceof J2C.BlockStatement
      if @parent.childs[@parent.childs.length-1] instanceof J2C.ReturnStatement
        if @findParent(@parent)?.lastReturn == this
          returnString = ''

    if @argument?
      return "#{returnString}#{@argument.getCoffee()}"
    else 
      return returnString.trim()

  findParent: (myParent) -> 
    if myParent.type == 'Program'
      return null
    else if myParent.type == 'FunctionExpression' or myParent.type == 'FunctionDeclaration' or myParent.type == 'CallExpression'
      return myParent
    else
      return @findParent(myParent.parent)

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

class J2C.UBExpression extends J2C.SyntaxTree
  convertOperator: (operator) ->
    conversions = 
      '===': 'is'
      '==': 'is'
      '!==': 'isnt'
      '!!!': 'not'   
      '!!': ''   
      '!': 'not'      
    if conversions[operator]?
      return conversions[operator]
    else 
      return operator

class J2C.BinaryExpression extends J2C.UBExpression
  create: () ->
    @left = new J2C[@tree.left.type](this, @tree.left)
    @right = new J2C[@tree.right.type](this, @tree.right)
    @operator = @tree.operator
    @checkNullCase()

  getCoffee: () ->
    # Null case
    if @nullCase
      ret = "#{@left.getCoffee()}?"
    # Normal case
    else 
      ret = "#{@left.getCoffee()} #{@convertOperator(@operator)} #{@right.getCoffee()}"
    if @parent instanceof J2C.BinaryExpression and ((@left instanceof J2C.Literal or @left instanceof J2C.Identifier) or (@right instanceof J2C.Literal or @right instanceof J2C.Identifier))
      ret = "(#{ret})"
    ret = @wrapParenthesis(ret)
    return ret

  checkNullCase: () ->
    # Null or Void 0
    @nullCase = true
    if (@right.value == null and @operator == '==') or (@operator == '==' and @right?.operator == 'void')
      @nullEquals = true
    else if (@right.value == null and @operator == '!=')
      @nullEquals = false
    else 
      @nullCase = false

  wrapParenthesis: (str) ->
    if @parent instanceof J2C.UnaryExpression
      return "(#{str})";
    else
      return str

class J2C.UnaryExpression extends J2C.UBExpression
  create: () ->
    @operator = @tree.operator
    @argument = new J2C[@tree.argument.type](this, @tree.argument)

  getCoffee: () ->
    # Void
    if @operator == 'void'
      return 'undefined'
    else 
      if @operator == '-'
        return "#{@convertOperator(@operator)}#{@argument.getCoffee()}"
      else
        if @argument instanceof J2C.UnaryExpression
          @argument.operator += @operator
          return @argument.getCoffee()
        else
          whiteSpace = if @convertOperator(@operator).length > 0 then ' ' else ''
          return "#{@convertOperator(@operator)}#{whiteSpace}#{@argument.getCoffee()}"

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
  create: () ->
    @value = @tree.value    
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
      if @body.childs.length > 0 and !@lastReturn?
        @body.childs.push new J2C.ReturnStatement(this, { type: 'ReturnStatement', argument: null })

    # Trim if function is empty
    if @body.childs.length > 0
      ret += @body.getCoffee()
    else 
      ret += "\n" 

    # If function is object for meber
    if @parent instanceof J2C.MemberExpression
      ret = "(#{ret})"

    return ret

class J2C.UpdateExpression extends J2C.SyntaxTree
  create: () ->
    @operator = @tree.operator
    @prefix = @tree.prefix
    @argument = new J2C[@tree.argument.type](this, @tree.argument)

  getCoffee: () ->
    if @prefix
      return "#{@operator}#{@argument.getCoffee()}"
    else
      return "#{@argument.getCoffee()}#{@operator}"

class J2C.AssignmentExpression extends J2C.SyntaxTree
  create: () ->
    @left = new J2C[@tree.left.type](this, @tree.left)
    @right = new J2C[@tree.right.type](this, @tree.right)
    @operator = @tree.operator

  getCoffee: () ->
    # Trim the whitespace after operator
    whiteSpace = if @right instanceof J2C.ObjectExpression then '' else ' '
    return "#{@left.getCoffee()} #{@operator}#{whiteSpace}#{@right.getCoffee()}"

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

class J2C.TryStatement extends J2C.SyntaxTree
  create: () ->
    @block = new J2C[@tree.block.type](this, @tree.block)
    @handler = new J2C[@tree.handler.type](this, @tree.handler)
  getCoffee: () ->
    return "try#{@block.getCoffee()}#{@handler.getCoffee()}"

class J2C.CatchClause extends J2C.SyntaxTree
  create: () ->
    @param = new J2C[@tree.param.type](this, @tree.param)
    @body = new J2C[@tree.body.type](this, @tree.body)
  getCoffee: () ->
    if @body.getCoffee().trim().length > 0
      return "catch #{@param.getCoffee()}#{@body.getCoffee()}"
    else 
      return ''

class J2C.IfStatement extends J2C.SyntaxTree
  create: () ->
    @test = new J2C[@tree.test.type](this, @tree.test)
    @consequent = new J2C[@tree.consequent.type](this, @tree.consequent)
    @alternate = if @tree.alternate? then new J2C[@tree.alternate.type](this, @tree.alternate)
  getCoffee: () ->    
    myIf = @checkUnless()
    # If only one parameter in block, move consequent before clause
    if @consequent instanceof J2C.BlockStatement
      if @consequent.childs.length == 1
        consCoff = @consequent.getCoffee()
        return "#{consCoff.substring(3,consCoff.length-1)} #{myIf}#{@test.getCoffee()}"
    alternate = if @alternate? then "\nelse #{@alternate.getCoffee()}" else ''
    return "#{myIf}#{@test.getCoffee()} #{@consequent.getCoffee()}#{alternate}"
  checkUnless: () ->
    # If -> Unless
    if @test instanceof J2C.UnaryExpression and @test.operator == '!'
      myIf = 'unless '
      @test.operator = ''
    else if @test instanceof J2C.BinaryExpression and @test.operator == '!=' and not @test.nullCase
      myIf = 'unless '
      @test.operator = 'is'
    else if @test.nullCase and @test.nullEquals
      myIf = 'unless '
    else 
      myIf = 'if '
    return myIf    

class J2C.ForInStatement extends J2C.SyntaxTree
  create: () ->
    @left = new J2C[@tree.left.type](this, @tree.left)
    @right = new J2C[@tree.right.type](this, @tree.right)
    @body = new J2C[@tree.body.type](this, @tree.body)
    @fixEmptyBody()
  getCoffee: () ->
    return "for #{@left.getCoffee()} of #{@right.getCoffee()}#{@body.getCoffee()}"
  fixEmptyBody: () ->
    if @body.childs.length <= 0
      @body.childs.push new J2C.ContinueStatement(this, @tree)

class J2C.ForStatement extends J2C.SyntaxTree
  create: () ->
    if @tree.init? then @init = new J2C[@tree.init.type](this, @tree.init)
    if @tree.test? then @test = new J2C[@tree.test.type](this, @tree.test)    
    if @tree.update? then @update = new J2C[@tree.update.type](this, @tree.update)    
    @body = new J2C[@tree.body.type](this, @tree.body)
    # Add update inside the block
    if @update?
      @body.childs.push @update
  getCoffee: () ->
    init = if @init? then "#{@init.getCoffee()}\n" else ''
    if not @test? then return "#{init}loop#{@body.getCoffee()}"
    # Null case
    if @test.nullCase
      addNot = 'not '
    else 
      addNot = ''
    return "#{init}while #{addNot}#{@test.getCoffee()}#{@body.getCoffee()}"

class J2C.WhileStatement extends J2C.ForStatement
  getCoffee: () ->
    # Null case
    if @test.nullCase
      addNot = 'not '
    else 
      addNot = ''
    if @body instanceof J2C.BlockStatement
      if @body.childs.length == 1
        myBody = @body.getCoffee()
        return "#{myBody.substring(3,myBody.length-1)} #{if @test.nullCase then 'until' else 'while'} #{@test.getCoffee()}"
      else 
        return "while #{addNot}#{@test.getCoffee()}#{@body.getCoffee()}"

class J2C.FunctionDeclaration extends J2C.FunctionExpression

class J2C.ContinueStatement extends J2C.SyntaxTree
  getCoffee: () ->
    return 'continue'

class J2C.EmptyStatement extends J2C.SyntaxTree
  getCoffee: () ->
    return ''

class J2C.Main
  
  constructor: () ->
    @file = fs.readFileSync("#{__dirname}/javascript.pegjs").toString()
    @parser = PEG.buildParser(@file)

  getSyntaxTree: () ->
    return @syntaxTree

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
