abstract type JavaTypeTag end

_typeTagSymbolForName(name::String) = Symbol("JavaTypeTag" * name)
_classnameFromTypeTagSymbol(t::Type{<: JavaTypeTag}) = string(split(String(Base.nameof(t)), "JavaTypeTag", limit=2)[2])

_typeTagDecl_promote(x::String) = _typeTagSymbolForName(x)
_typeTagDecl_promote(x::Symbol) = x
_typeTagDecl(t::Union{Symbol, String}, u::Union{Symbol, String}) =
    quote
        abstract type $(_typeTagDecl_promote(t)) <: $(_typeTagDecl_promote(u)) end
    end

typeTagForName(name::String) = begin
    local sym = _typeTagSymbolForName(name)
    if ! Base.isdefined(Main.BetterJavaCall, sym)
        local class = JavaCall.classforname(name)
        local isinterface = Bool(JavaCall.jcall(class, "isInterface", JavaCall.jboolean, ()))

        local supertypename = if isinterface
            "interface"
        else
            local superclass = JavaCall.jcall(class, "getSuperclass", JavaCall.JClass, ())
            local superclassname = JavaCall.getname(superclass)
            typeTagForName(superclassname) # ensure it is created
            superclassname
        end

        eval(_typeTagDecl(sym, supertypename))
    end

    eval(sym)
end

macro deftype(e)
    local (t, u) = if e isa Expr && e.head == :<:
        local t = sprint(Base.show_unquoted, e.args[1])
        local u = sprint(Base.show_unquoted, e.args[2])
        (t, u)
    else
        e = sprint(Base.show_unquoted, e)
        @assert e == "java.lang.Object" || e == "interface"
        (e, :JavaTypeTag)
    end

    esc(_typeTagDecl(t, u))
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