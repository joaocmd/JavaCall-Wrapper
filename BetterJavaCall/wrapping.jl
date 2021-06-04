InstanceProxy(ref::JavaCall.JavaObject{T}) where {T} = begin
    local classname = string(T)
    local mod = javaImport(classname).δmod

    InstanceProxy{typeTagForName(classname)}(ref, mod)
end

InstanceProxy(inst::InstanceProxy) = begin
    local classname = inst.getClass().getName()
    local mod = javaImport(classname).δmod

    InstanceProxy{typeTagForName(classname)}(inst.δref, mod)
end

ImportProxy(::Type{JavaCall.JavaObject{T}}) where {T} = begin
    local classname = string(T)
    local mod = javaImport(classname).δmod

    ImportProxy{typeTagForName(classname)}(mod)
end

java_primitive_types = Core.Union{Int8, Int16, Int32, Int64, Float32, Float64, Nothing}

unwrapped(x::InstanceProxy) = getfield(x, :ref)
unwrapped(x::Union{JavaCall.JavaObject, java_primitive_types, String}) = x
unwrapped(x::Array{T, N}) where {T, N} = map(unwrapped, x)
unwrapped(x::Bool) = UInt8(x)
unwrapped(x::Char) = UInt16(x)
unwrapped(t::Tuple) = t # for varargs (they have custom separate handling)

unwrapped(::Type{Bool}) = UInt8
unwrapped(::Type{Char}) = UInt16
unwrapped(t::Type{<: Union{JavaCall.JavaObject, java_primitive_types}}) = t
unwrapped(::Type{InstanceProxy}) = JavaCall.JavaObject
unwrapped(::Type{Array{T, N}}) where {T, N} = Array{unwrapped(T), N}

wrapped(x::Union{InstanceProxy, java_primitive_types, String}) = x
wrapped(x::JavaCall.JavaObject{C}) where {C} =
    if JavaCall.isnull(x)
        nothing
    else
        InstanceProxy(x)
    end
wrapped(x::Array{T, N}) where {T, N} = map(wrapped, x)
wrapped(x::UInt8) = Bool(x) # kinda ugly, but nothing else is a UInt8
wrapped(x::UInt16) = Char(x) # kinda ugly, but nothing else is a UInt16
wrapped(::Type{UInt8}) = Bool
wrapped(::Type{UInt16}) = Char
wrapped(::Type{JavaCall.JavaObject{C}}) where {C} = InstanceProxy{typeTagForName(string(C))}
wrapped(t::Type{<: Union{InstanceProxy, java_primitive_types}}) = t
wrapped(::Type{Array{T, N}}) where {T, N} = Array{wrapped(T), N}

wrapped_paramtype(x) = wrapped(x)
wrapped_paramtype(::Union{Type{JavaCall.JavaObject{Symbol("java.lang.String")}}, Type{JavaCall.JavaObject{Symbol("java.lang.CharSequence")}}}) = Union{
    String,
    InstanceProxy{<: typeTagForName("java.lang.String")},
    InstanceProxy{typeTagForName("java.lang.CharSequence")},
    Nothing,
}
wrapped_paramtype(::Type{JavaCall.JavaObject{C}}) where {C} = Union{InstanceProxy{<: typeTagForName(string(C))}, Nothing}

Base.convert(t::Type{JavaCall.@jimport java.lang.CharSequence}, x::JavaCall.JString) = t(x.ref)
Base.convert(t::Type{JavaCall.@jimport java.lang.CharSequence}, x::String) = t(JavaCall.JString(x).ref)
