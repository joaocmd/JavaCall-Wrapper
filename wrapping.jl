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
    elseif (m = Base.match(r"[^\][]+((\[])+)", name); typeof(m) != Nothing)
        local n = m.captures[1].ncodeunits ÷ 2
        local name_len = length(name) - m.captures[1].ncodeunits
        Array{normalizeJavaType(SubString(name, 1:name_len)),n}
    else
        JavaCall.JavaObject{Symbol(name)}
    end

normalizeJavaType(x::JavaCall.JClass) =
    normalizeJavaType(JavaCall.getname(x))

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
wrapped(x::JavaCall.JavaObject{C}) where {C} = begin
    if JavaCall.isnull(x)
        return nothing
    end

    local classname = string(C)
    local mod = getfield(javaImport(classname), :mod)

    InstanceProxy{typeTagForName(classname)}(x, mod)
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