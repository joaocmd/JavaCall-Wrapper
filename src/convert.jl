# regular Object -> Object casting
Base.convert(::Type{InstanceProxy{T}}, x::InstanceProxy{U}) where {T, U} = begin
    local targetmod = javaImport(T).δmod
    local targetclassname = targetmod.name

    # will throw exception if cast is impossible
    local ref = convert(JavaCall.JavaObject{Symbol(targetclassname)}, getfield(x, :ref))
    InstanceProxy{T}(ref, targetmod)
end

# fast-path for subclasses, where static casts are safe
Base.convert(::Type{InstanceProxy{T}}, x::InstanceProxy{U}) where {T, U <: T} = begin
    local targetmod = javaImport(T).δmod
    InstanceProxy{T}(targetmod.jc_class(x.δref.ref), targetmod)
end

Base.convert(::Type{InstanceProxy{T}}, ::Nothing) where {T} = begin
    local targetmod = javaImport(T).δmod
    local targetclassname = targetmod.name

    local ref = JavaCall.JavaObject{Symbol(targetclassname)}(JavaCall.J_NULL)
    InstanceProxy{T}(ref, targetmod)
end

macro boxingConv(e::Expr)
    local unboxed = string(e.args[2])
    local boxed = string(e.args[3])

    local ptype = :( JavaCall.$(Symbol("j" * unboxed)) )
    local tt = typeTagForName(boxed)
    local boxed_type = InstanceProxy{tt}

    local unboxed_to_boxed_conv = begin
        local T = tt
        local decls = []

        while T !== JavaTypeTag
            local classname = _classnameFromTypeTagSymbol(T)
            local jc_type = JavaCall.JavaObject{Symbol(classname)}

            push!(decls, quote
                # JavaCall should be able to convert more stuff hehe
                Base.convert(::Type{$jc_type}, x::$ptype) = $jc_type(boxed(x).δref.ref)
                Base.convert(::Type{InstanceProxy{$T}}, x::$ptype) = boxed(x)
            end)

            T = supertype(T)
        end
        decls
    end
    esc(quote
        boxed(x::$ptype) = Base.invokelatest(javaImport($boxed).valueOf, x)
        boxed(::Type{$ptype}) = $boxed_type
        unboxed(x::$boxed_type) = x.$(Symbol(unboxed * "Value"))()
        unboxed(x::$ptype) = x
        $(unboxed_to_boxed_conv...)
        Base.convert(::Type{$ptype}, x::$boxed_type) = unboxed(x)
        Base.promote_rule(::Type{$boxed_type}, ::Type{$ptype}) = $boxed_type
    end)
end

boxed(x::InstanceProxy) = x
boxed(t::Type{InstanceProxy}) = t

# not strictly boxing, but JavaCall gets in our way with this
boxed(x::String) = javaImport("java.lang.String")(x)

@boxingConv char - java.lang.Character
@boxingConv boolean - java.lang.Boolean
@boxingConv byte - java.lang.Byte
@boxingConv short - java.lang.Short
@boxingConv int - java.lang.Integer
@boxingConv long - java.lang.Long
@boxingConv float - java.lang.Float
@boxingConv double - java.lang.Double

# additional conversions for quality of life
Base.convert(t::Type{InstanceProxy{typeTagForName("java.lang.Object")}}, x::AbstractString) =
    convert(t, convert(InstanceProxy{typeTagForName("java.lang.String")}, x))
Base.convert(t::Type{InstanceProxy{typeTagForName("java.lang.CharSequence")}}, x::AbstractString) =
    convert(t, convert(InstanceProxy{typeTagForName("java.lang.String")}, x))
Base.convert(::Type{InstanceProxy{typeTagForName("java.lang.String")}}, x::AbstractString) = wrapped(JavaCall.JString(x))
Base.convert(::Type{AbstractString}, x::InstanceProxy{typeTagForName("java.lang.String")}) = Base.convert(AbstractString, getfield(x, :ref))

Base.convert(t::Type{InstanceProxy{typeTagForName("java.lang.Boolean")}}, x::Bool) = Base.convert(t, JavaCall.jboolean(x))
boxed(::Type{Bool}) = InstanceProxy{typeTagForName("java.lang.Boolean")}
Base.convert(::Type{Bool}, x::InstanceProxy{typeTagForName("java.lang.Boolean")}) = Bool(x.booleanValue())

Base.convert(t::Type{InstanceProxy{typeTagForName("java.lang.Character")}}, x::Char) = Base.convert(t, JavaCall.jchar(x))
boxed(::Type{Char}) = InstanceProxy{typeTagForName("java.lang.Character")}
Base.convert(::Type{Char}, x::InstanceProxy{typeTagForName("java.lang.Character")}) = Char(x.charValue())

# Exception proxy stuff
Base.convert(::Type{InstanceProxy}, ex::JavaException) = wrapped(ex.ref)

# cast shortcut
(cast_target::ImportProxy{T})(x) where {T} = convert(InstanceProxy{T}, x)

# iterators
const JIterator = InstanceProxy{typeTagForName("java.util.Iterator")}
Base.iterate(itr::JIterator, state=nothing) =
    if has_next(itr)
        local o = itr.next()
        # pass it through InstanceProxy() to convert it to its most specific form
        return (InstanceProxy(o), state)
    else
        return nothing
    end

has_next(itr::JIterator) = itr.hasNext()