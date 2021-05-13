import Pkg
Pkg.add("JavaCall")
using JavaCall

JavaCall.init(["-Xmx128M"])

macro pimport(package)
    local p = @jimport $package
    
end


@pimport java.lang.Math

jlm = @jimport java.lang.Math
methods = listmethods(jlm)
getreturntype(methods[1])
methodNames = []


for method in methods
    name = getname(method)
    hygienic_name = "pava_" * name
    returntype = getreturntype(method)
    parametertypes = getparametertypes(method)
    nrparams = length(parametertypes)
    parameters = [Symbol("p" * string(i)) for i in 1:nrparams]

    methodNames = push!(methodNames, getname(method))
    # TODO: return types and parameter types
    # map abs(p1::Int64) to jcall(jint) and abs(p1::Float32) to jcall(jfloat) ? how ?
    newMethod = :( $(Symbol(hygienic_name))($(parameters...)) = jcall(jlm, $name, jint, (jint,), $(parameters...)) )
    dump(newMethod)
    eval(newMethod)
end

unique!(methodNames) # maybe use a set?
Math = (;zip([Symbol(m) for m in methodNames], [eval(Symbol("pava_" * m)) for m in methodNames])...)
