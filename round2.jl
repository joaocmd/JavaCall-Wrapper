import Pkg
Pkg.add("JavaCall")
using JavaCall

JavaCall.init(["-Xmx128M"])

macro pimport(package)
    local p = @jimport $package
    
end


@pimport java.lang.Math

jlm = @jimport java.lang.Math
vars = split("abcdefghijklmnopqrstuvwxyz", "")
methods = listmethods(jlm)
methodNames = []

for method in methods
    name = "pava_" * getname(method)
    returntype = getreturntype(method)
    parametertypes = getparametertypes(method)
    nrparams = length(parametertypes)
    parameters = vars[1:nrparams]

    methodNames = push!(methodNames, getname(method))
    newMethod = :( $(Symbol(name))($([Symbol(p) for p in parameters]...)) = 1 )
    eval(newMethod)
end

unique!(methodNames) # maybe use a set?
(;zip([Symbol(m) for m in methodNames], [1 for m in methodNames])...)