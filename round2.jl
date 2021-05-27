import Pkg
Pkg.add("JavaCall")

##

using JavaCall

JavaCall.init(["-Xmx128M"])

##

macro pimport(package)
    local p = @jimport $package

end


@pimport java.lang.Math

##
normalizeJavaType(name::Union{Core.String, Base.SubString}) = begin
    if name == "short" || name == "java.lang.Short"
        JavaCall.jshort
    elseif name == "int" || name == "java.lang.Integer"
        JavaCall.jint
    elseif name == "long" || name == "java.lang.Long"
        JavaCall.jlong
    elseif name == "byte" || name == "java.lang.Byte"
        JavaCall.jbyte
    elseif name == "char" || name == "java.lang.Char"
        JavaCall.jchar
    elseif name == "float" || name == "java.lang.Float"
        JavaCall.jfloat
    elseif name == "double" || name == "java.lang.Double"
        JavaCall.jdouble
    elseif name == "boolean" || name == "java.lang.Boolean"
        JavaCall.jboolean
    elseif name == "void" || name == "java.lang.Void"
        JavaCall.jvoid
    elseif (m = Base.match(r"[^\][]+((\[])+)", name); typeof(m) != Nothing)
        n = m.captures[1].ncodeunits ÷ 2
        name_len = length(name) - m.captures[1].ncodeunits
        Array{normalizeJavaType(Base.SubString(name, 1:name_len)), n}
    else
        # TODO: wrapper? maybe?
        JavaCall.JavaObject{Symbol(name)}
    end
end

normalizeJavaType(x::JavaCall.JClass) = begin
    normalizeJavaType(getname(x))
end

##

jlm = @jimport java.lang.Math
methodNames = []

for method in JavaCall.listmethods(jlm)
    name = getname(method)
    hygienic_name = "pava2_" * name
    returntype = normalizeJavaType(getreturntype(method))
    parametertypes = Tuple(normalizeJavaType(p) for p in getparametertypes(method))
    nrparams = length(parametertypes)
    parameters = [Symbol("p" * string(i)) for i in 1:nrparams]

    typed_parameters = [:($(a[1])::$(a[2])) for a in zip(parameters, parametertypes)]

    methodNames = push!(methodNames, getname(method))
    newMethod = :( $(Symbol(hygienic_name))($(typed_parameters...)) = jcall(jlm, $name, $returntype, $parametertypes, $(parameters...)) )
    # dump(newMethod)
    eval(newMethod)
end

fields = []
for field in JavaCall.listfields(jlm)
    name = JavaCall.getname(field)
    type = JavaCall.jcall(field, "getType", JClass, ())
    type = normalizeJavaType(type)

    # HACK: fields may not be final, it's not desirable to be stuck with the value currently present
    val = JavaCall.jfield(jlm, name, type)
    fields = push!(fields, (Symbol(name), val))
end

unique!(methodNames) # maybe use a set?
methods_ = zip([Symbol(m) for m in methodNames], [eval(Symbol("pava2_" * m)) for m in methodNames])
Math = merge((;fields...), (;methods_...))

##
