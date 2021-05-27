import Pkg
# Pkg.add("JavaCall")

##

using JavaCall

JavaCall.init(["-Xmx128M"])
Base.show(io::IO, obj::JavaCall.JavaObject) =
    print(io, jcall(obj, "toString", JString, ()))

struct JavaValue
    ref::JavaCall.JavaObject 
    # maybe try to use a NamedTuple?
    methods::NamedTuple
end

Base.show(io::IO, jv::JavaValue) =
    show(io, getfield(jv, :ref))

Base.getproperty(jv::JavaValue, sym::Symbol) =
    getfield(jv, :methods)[sym](getfield(jv, :ref))

##

macro pimport(package)
    local p = @jimport $package
end

@pimport java.lang.Math

mdf = @jimport java.lang.reflect.Modifier
isstatic(method::JMethod) = begin
    modifiers = jcall(method, "getModifiers", jint, ())
    Bool(jcall(mdf, "isStatic", jboolean, (jint,), modifiers))
end

##
normalizeJavaType(name::Union{Core.String,Base.SubString}) = begin
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
        Array{normalizeJavaType(Base.SubString(name, 1:name_len)),n}
    else
        # TODO: wrapper? maybe?
        JavaCall.JavaObject{Symbol(name)}
    end
end

normalizeJavaType(x::JavaCall.JClass) = begin
    normalizeJavaType(getname(x))
end
    
##

jlm = @jimport java.time.LocalDate
methodnames = []
instancemethods = []

PROBLEM = Nothing

for method in JavaCall.listmethods(jlm)
    name = getname(method)
    hygienic_name = "pava2_" * name
    returntype = normalizeJavaType(getreturntype(method))
    parametertypes = Tuple(normalizeJavaType(p) for p in getparametertypes(method))
    parameters = [Symbol("p" * string(i)) for i in 1:length(parametertypes)]

    typed_parameters = [:($(a[1])::$(a[2])) for a in zip(parameters, parametertypes)]

    # TODO: in these functions, if the returned is an object, wrap it in the proxy
    # Same applies if a proxy is passed as function argument, will probably need some changes to the static
    # methods to allow that
    if (isstatic(method))
        push!(methodnames, getname(method))
        newmethod = :( $(Symbol(hygienic_name))($(typed_parameters...)) = jcall(jlm, $name, $returntype, $parametertypes, $(parameters...)) )
        eval(newmethod)
    else
        push!(instancemethods, getname(method))
        inst_param = :(inst::$(jlm))
        newmethod = :( $(Symbol(hygienic_name))($inst_param) = ($(typed_parameters...),) -> jcall(inst, $name, $returntype, $parametertypes, $(parameters...)))
        eval(newmethod)
    end
end

fields = []
for field in JavaCall.listfields(jlm)
    name = JavaCall.getname(field)
    type = JavaCall.jcall(field, "getType", JClass, ())
    type = normalizeJavaType(type)

    # HACK: fields may not be final, it's not desirable to be stuck with the value currently present
    # val = () -> JavaCall.jfield(jlm, name, type) something like this would be good but not really this??
    val = JavaCall.jfield(jlm, name, type)
    fields = push!(fields, (Symbol(name), val))
end

unique!(methodnames) # maybe use a set?
methods_ = zip([Symbol(m) for m in methodnames], [eval(Symbol("pava2_" * m)) for m in methodnames])
LocalDate = merge((;fields...), (;methods_...))

unique!(instancemethods)
instancemethods_ = (;zip([Symbol(m) for m in instancemethods], [eval(Symbol("pava2_" * m)) for m in instancemethods])...)

now = LocalDate.now()
method = (plusDays = (jtld) -> (days) -> jcall(jtld, "plusDays", jlm, (jlong,), days),)

a = JavaValue(now, instancemethods_)
#