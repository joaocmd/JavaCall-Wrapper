abstract type JavaTypeTag end

_typeTagSymbolForName(name::String) = Symbol("JavaTypeTag" * name)
_classnameFromTypeTagSymbol(t::Type{<: JavaTypeTag}) = split(String(Base.nameof(t)), "JavaTypeTag", limit=2)[2]

typeTagForName(name::String) = begin
    local typetags = _typeTagSymbolForName(name)
    if ! Base.isdefined(Main.BetterJavaCall, typetags)
        local class = JavaCall.classforname(name)
        local isinterface = Bool(JavaCall.jcall(class, "isInterface", JavaCall.jboolean, ()))

        local superclasstag = if isinterface
            _typeTagSymbolForName("interface")
        else
            local superclass = JavaCall.jcall(class, "getSuperclass", JavaCall.JClass, ())
            local superclassname = JavaCall.getname(superclass)
            typeTagForName(superclassname) # ensure it is created
            _typeTagSymbolForName(superclassname)
        end

        local def = quote
            abstract type $typetags <: $superclasstag end
        end

        eval(def)
    end

    eval(typetags)
end

macro deftype(e)
    if e.head == :.
        e = sprint(Base.show_unquoted, e)
        @assert e == "java.lang.Object" || e == "interface"
        t = _typeTagSymbolForName(e)

        quote
            abstract type $t <: JavaTypeTag end
        end
    elseif e.head == :<:
        t = _typeTagSymbolForName(sprint(Base.show_unquoted, e.args[1]))
        u = _typeTagSymbolForName(sprint(Base.show_unquoted, e.args[2]))

        quote
            abstract type $t <: $u end
        end
    else
        show(e)
        Base.error("you don't know what you're doing")
    end
end

@deftype java.lang.Object
@deftype interface
@deftype java.lang.Boolean <: java.lang.Object
@deftype java.lang.Character <: java.lang.Object

@deftype java.lang.Number <: java.lang.Object
@deftype java.lang.Byte <: java.lang.Number
@deftype java.lang.Short <: java.lang.Number
@deftype java.lang.Integer <: java.lang.Number
@deftype java.lang.Long <: java.lang.Number
@deftype java.lang.Float <: java.lang.Number
@deftype java.lang.Double <: java.lang.Number

@deftype java.lang.String <: java.lang.Object
@deftype java.lang.Throwable <: java.lang.Object
@deftype java.util.Iterator <: interface