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

normalizeJavaType(name) =
    if name == "short" || name == "java.lang.Short"
        JavaCall.jshort
    elseif name == "int" || name == "java.lang.Integer"
        JavaCall.jint
    elseif name == "long" || name == "java.lang.Long"
        JavaCall.jlong
    elseif name == "byte" || name == "java.lang.Byte"
        JavaCall.jbyte
    elseif name == "char" || name == "java.lang.Char"
        JavaCall.jchar # UInt16
    elseif name == "float" || name == "java.lang.Float"
        JavaCall.jfloat
    elseif name == "double" || name == "java.lang.Double"
        JavaCall.jdouble
    elseif name == "boolean" || name == "java.lang.Boolean"
        JavaCall.jboolean # UInt8
    elseif name == "void" || name == "java.lang.Void"
        JavaCall.jvoid
    elseif (m = Base.match(r"([^\[\]]+)([\[\]]+)", name); typeof(m) != Nothing)
        local component = normalizeJavaType(m.captures[1])
        local n = length(m.captures[2]) ÷ 2
        eval(_nestedvector(component, n))
    else
        JavaCall.JavaObject{Symbol(name)}
    end

normalizeJavaType(x::JavaCall.JClass) =
    normalizeJavaType(JavaCall.getname(x))

_nestedvector(component::Type, n::Integer) =
    if n == 1
        :( Vector{$component} )
    else
        :( Vector{$(_nestedvector(component, n-1))} )
    end

java_primitive_types = Core.Union{Int8, Int16, Int32, Int64, Float32, Float64, Nothing}

unwrapped(x::InstanceProxy) = getfield(x, :ref)
unwrapped(x::Union{JavaCall.JavaObject, java_primitive_types, String}) = x
unwrapped(x::Array{T, N}) where {T, N} = map(unwrapped, x)
unwrapped(x::Bool) = UInt8(x)
unwrapped(x::Char) = UInt16(x)
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
wrapped(::Union{Type{JavaCall.JavaObject{Symbol("java.lang.String")}}, Type{JavaCall.JavaObject{Symbol("java.lang.CharSequence")}}}) = Union{
    String,
    InstanceProxy{<: typeTagForName("java.lang.String")},
    InstanceProxy{typeTagForName("java.lang.CharSequence")},
    Nothing,
}
wrapped(::Type{JavaCall.JavaObject{C}}) where {C} = Union{InstanceProxy{<: typeTagForName(string(C))}, Nothing}
wrapped(t::Type{<: Union{InstanceProxy, java_primitive_types}}) = t
wrapped(::Type{Array{T, N}}) where {T, N} = Array{wrapped(T), N}
