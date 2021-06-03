# regular Object -> Object casting
Base.convert(::Type{InstanceProxy{T}}, x::InstanceProxy{U}) where {T, U} = begin
    local targetmod = javaImport(T).δmod
    local targetclassname = targetmod.name

    # will throw exception if cast is impossible
    local ref = convert(JavaCall.JavaObject{Symbol(targetclassname)}, getfield(inst, :ref))
    InstanceProxy{typeTagForName(targetclassname)}(ref, targetmod)
end

macro boxingConv(e::Expr)
    local unboxed = string(e.args[2])
    local boxed = string(e.args[3])

    local jc_type = :( JavaCall.$(Symbol("j" * unboxed)) )
    quote
        Base.convert(::Type{InstanceProxy{typeTagForName($boxed)}}, x::$jc_type) = javaImport($boxed).valueOf(x)
        Base.convert(::Type{$jc_type}, x::InstanceProxy{typeTagForName($boxed)}) = x.$(Symbol(unboxed * "Value"))()
    end
end

@boxingConv char - java.lang.Character
@boxingConv boolean - java.lang.Boolean
@boxingConv byte - java.lang.Byte
@boxingConv short - java.lang.Short
@boxingConv int - java.lang.Integer
@boxingConv long - java.lang.Long
@boxingConv float - java.lang.Float
@boxingConv double - java.lang.Double

# additional conversions for quality of life
Base.convert(::Type{InstanceProxy{typeTagForName("java.lang.String")}}, x::AbstractString) = wrapped(JavaCall.JString(x))
Base.convert(::Type{AbstractString}, x::InstanceProxy{typeTagForName("java.lang.String")}) = Base.convert(AbstractString, getfield(x, :ref))
Base.convert(t::Type{InstanceProxy{typeTagForName("java.lang.Boolean")}}, x::Bool) = Base.convert(t, JavaCall.jboolean(x))
Base.convert(::Type{Bool}, x::InstanceProxy{typeTagForName("java.lang.Boolean")}) = Bool(x.booleanValue())
Base.convert(t::Type{InstanceProxy{typeTagForName("java.lang.Character")}}, x::Char) = Base.convert(t, JavaCall.jchar(x))
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