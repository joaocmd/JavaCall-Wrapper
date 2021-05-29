import Pkg
Pkg.add("JavaCall")

##
using JavaCall
JavaCall.init(["-Xmx128M"])
##
Base.show(io::IO, obj::JavaCall.JavaObject) =
    print(io, jcall(obj, "toString", JString, ()))

struct JavaValue
    ref::JavaCall.JavaObject 
    methods::NamedTuple
end

struct ClassProxy
    name::String
    mod::Module
end

Base.show(io::IO, jv::JavaValue) =
    show(io, getfield(jv, :ref))

Base.getproperty(jv::JavaValue, sym::Symbol) =
    getfield(jv, :methods)[sym](getfield(jv, :ref))

    
Base.show(io::IO, cp::ClassProxy) =
    show(io, getfield(cp, :name))

Base.getproperty(cp::ClassProxy, sym::Symbol) = begin
    if string(sym) ∈ getfield(cp, :mod).final
        eval(:( getfield($cp, :mod).$(sym) )) # get the method/constant
    else
        eval(:( getfield($cp, :mod).$sym() )) # call the getter
    end
end

Base.setproperty!(cp::ClassProxy, sym::Symbol, v::Any) = begin
    eval(:( getfield($cp, :mod).$sym($v) ))
end

##

# public void f(Comparable<?> b)
# public void f(Serializable c)
# f(Serializable(o))

mdf = @jimport java.lang.reflect.Modifier
isstatic(method::Union{JavaCall.JField,JavaCall.JMethod}) = begin
    modifiers = jcall(method, "getModifiers", jint, ())
    Bool(jcall(mdf, "isStatic", jboolean, (jint,), modifiers))
end
isfinal(method::Union{JavaCall.JField,JavaCall.JMethod}) = begin
    modifiers = jcall(method, "getModifiers", jint, ())
    Bool(jcall(mdf, "isFinal", jboolean, (jint,), modifiers))
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

# jlm = @jimport java.time.LocalDate
# methodnames = []
# instancemethods = []

# module LocalDate

# methodnames = []
# instancemethodnames = []

function javaClassModuleName(classname::String)
    "PAvaJavaInterop Class " * classname
end

function javaClass(classname::String)
    if ! Base.isdefined(Main, Symbol(javaClassModuleName(classname)))
        javaClassModule(classname)
    end

    eval(Symbol(javaClassModuleName(classname)))
end

function javaClassModule(classname::String)
    class = eval(JavaCall._jimport(classname))
    mod_name = javaClassModuleName(classname)

    # create module
    eval(:(module $(Symbol(mod_name)) using JavaCall end))
    mod = eval(Symbol(mod_name)) 

    for method in JavaCall.listmethods(class)
        local name = getname(method)
        local returntype = normalizeJavaType(getreturntype(method))
        local parametertypes = Tuple(normalizeJavaType(p) for p in getparametertypes(method))
        local parameters = [Symbol("p" * string(i)) for i in 1:length(parametertypes)]
        local typed_parameters = [:($(a[1])::$(a[2])) for a in zip(parameters, parametertypes)]

        # TODO: in these functions, if the returned is an object, wrap it in the proxy
        # Same applies if a proxy is passed as function argument, will probably need some changes to the static
        # methods to allow that
        # getvalue(x) = x
        # getvalue(x::JavaValue) = getfield(x, :ref)

        # foo(bar) -> begin
        #     parameters = [getvalue(x) for x in parameters]
        #     res = jcall(jlm, $name, $returntype)
        #     if typeof(res) == JavaCall.JavaObject
        #         _instancemethods = @pimport getname(getclass(res)) # how?
        #         a = JavaValue(res, _instancemethods)
        #     else
        #         res
        #     end
        # end

        if (isstatic(method))
            newmethod = :( $(Symbol(name))($(typed_parameters...)) = jcall(class, $name, $returntype, $parametertypes, $(parameters...)) )
            Base.eval(mod, newmethod)
        else
            inst_param = :(inst::$(class))
            newmethod = :( $(Symbol(name))($inst_param) = ($(typed_parameters...),) -> jcall(inst, $name, $returntype, $parametertypes, $(parameters...)))
            Base.eval(mod, newmethod)
        end
    end

    Base.eval(mod, :( final = Set() ))
    for field in JavaCall.listfields(class)
        name = JavaCall.getname(field)
        union!(mod.final, [name])
        type = JavaCall.jcall(field, "getType", JClass, ())
        type = normalizeJavaType(type)

        if isstatic(field)
            # commented this out for testing getters/setters
            # if isfinal(field)
            #     val = JavaCall.jfield(class, name, type)
            #     Base.eval(mod, :( $(Symbol(name)) = $(val) ))
        # else
                # TODO: use better setter than the boxed get/set
                getter = :( $(Symbol(name))() = JavaCall.jfield($(class), $(name), $(type)) )
                setter = :( $(Symbol(name))(val::$(type)) = JavaCall.jcall($(field), "set", JavaCall.jvoid, ($(type)), ) )

                Base.eval(mod, getter)
                Base.eval(mod, setter)
            # end
        else
            # TODO
        end 
    end
    ClassProxy(classname, mod)
end

##
class = javaClassModule("java.time.LocalDate")
mod = getfield(class, :mod)

##
LocalDate = merge((;fields...), (;methods_...))

unique!(instancemethods)
instancemethods_ = (;zip([Symbol(m) for m in instancemethods], [eval(Symbol("pava2_" * m)) for m in instancemethods])...)

now = LocalDate.now()
method = (plusDays = (jtld) -> (days) -> jcall(jtld, "plusDays", jlm, (jlong,), days),)

a = JavaValue(now, instancemethods_)
# 
