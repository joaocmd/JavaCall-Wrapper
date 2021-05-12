using JavaCall

JavaCall.init(["-Xmx128M"])

jlm = @jimport java.lang.Math


jlm
jcall(jlm, "sin", jdouble, (jdouble,), pi / 2)
methods = listmethods(jlm)

first = methods[40]

macro generateFunction(method)
    print(getname(method))
end

@generateFunction $first


vars = split("abcdefghijklmnopqrstuvwxyz", "")

name = getname(first)
returntype = getreturntype(first)
parametertypes = getparametertypes(first)
nrparams = length(parametertypes)
# parameters = join(vars[1:nrparams], ", ")
parameters = vars[1:nrparams]


A = :($(Symbol(name)) = () -> 1,)
B = eval(A)
A = :($(Symbol(name)) = ($(Symbol(parameters))) -> 1,)
B = eval(A)
A = :($(Symbol(name)) = ($(map(p -> (Symbol(p), ','), parameters)...) -> 1,))
B = eval(A)

A = :($(map(Symbol, parameters)) -> 1)
B = eval(A)
Symbol(name)

# Parse is kinda dirty but it works, symbols are better.....
second = methods[1]
name = getname(second)
returntype = getreturntype(second)
parametertypes = getparametertypes(second)
nrparams = length(parametertypes)
parameters = join(vars[1:nrparams], ", ")

string = "($name=($parameters)->jcall(jlm, \"$name\", jint, (jint,), $parameters),)"
A = Meta.parse(string)
Math = eval(A)



concat(x::String) = x
concat(x::String, y::String) = x * y

A = (concat = concat,)

# TEST WITH MOCK
name = "abs"
nrparams = 1

abs(x) = jcall(jlm, name, jint, (jint,), x)

name = "abs"
nrparams = 2
abs(x, y) = jcall(jlm, name, jint, (jint, jint), x, y)

vars = split("abcdefghijklmnopqrstuvwxyz", "")
macro generateFunction(name, nrparams)
    local parameters = vars[1:nrparams]
    return  :( $name($([Symbol(p) for p in parameters]...)) = 1 )
end

name = "abs"
nrparams = 2
