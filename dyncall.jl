javaMetaclass(classname::String) = wrapped(JavaCall.classforname(classname))

arg_is_compatible(t::Type, x) = applicable(Base.convert, t, x)
# fast-path for superclasses
arg_is_compatible(::Type{InstanceProxy{T}}, ::InstanceProxy{U}) where {T, U <: T} = true
arg_is_compatible(::Type{InstanceProxy{T}}, ::InstanceProxy{U}) where {T, U} = begin
    local metaclassT = javaMetaclass(_classnameFromTypeTagSymbol(T))
    local metaclassU = javaMetaclass(_classnameFromTypeTagSymbol(U))
    metaclassT.IsAssignableFrom(metaclassU)
end

method_is_applicable(paramtypes::Vector{DataType}, args...) =
    all(map(((p, a)::Tuple) -> arg_is_compatible(p, a), zip(paramtypes, args)))

arg_type_lt(::Type{InstanceProxy{T}}, ::Type{InstanceProxy{U}}) where {T, U} = begin
    local metaclassT = javaMetaclass(_classnameFromTypeTagSymbol(T))
    local metaclassU = javaMetaclass(_classnameFromTypeTagSymbol(U))

    !metaclassT.isAssignableFrom(metaclassU) && metaclassU.isAssignableFrom(metaclassT)
end

variant_arg_types_lt(argtypes1::Vector{DataType}, argtypes2::Vector{DataType}) = begin
    for (a, b) in zip(argtypes1, argtypes2)
        if !arg_type_lt(a, b)
            return false
        end
    end

    true
end

getvariantparamtypes(method_or_ctor::Union{JavaCall.JMethod, JavaCall.JConstructor}) =
    map(
        t -> unwrapped(normalizeJavaType(t)),
        JavaCall.getparametertypes(method_or_ctor)
    )

choosevariant(variants::Vector{T}, args...) where {T <: Union{JavaCall.JMethod, JavaCall.JConstructor}} = begin
    variants = map(v -> (v, getvariantparamtypes(v)), variants)
    local applicable = filter(v -> method_is_applicable(v[2], args...), variants)
    if isempty(applicable)
        return (nothing, nothing)
    end

    sort!(applicable, lt=variant_arg_types_lt, by=v -> v[2])
    last(applicable) # (variant, paramtypes)
end

dyncallmethod(recv::Type{JavaCall.JavaObject{C}}, name::String, args...) where {C} =
    dyncallmethod(recv, recv, name, args...)
dyncallmethod(recv::JavaCall.JavaObject{C}, name::String, args...) where {C} =
    dyncallmethod(recv, typeof(recv), name, args...)
dyncallmethod(recv, t::Type{JavaCall.JavaObject{C}}, name::String, args...) where {C} = begin
    local unwrappedargs = map(unwrapped, args)

    local (method, paramtypes) = choosevariant(
        filter(m -> JavaCall.getname(m) == name, JavaCall.listmethods(t)),
        unwrappedargs...
    )
    if method === nothing
        Base.error("No matching method call for arguments $(Tuple(map(typeof, args)))")
    end

    local rettype = normalizeJavaType(JavaCall.getreturntype(method))

    local res = JavaCall.jcall(recv, name, rettype, Tuple(paramtypes), unwrappedargs...)
    wrapped(res)
end

dyncallctor(classname::String, args...) = begin
    args = map(unwrapped, args)
    local metaclass = JavaCall.classforname(classname)
    local (_, paramtypes) = choosevariant(
        JavaCall.jcall(metaclass, "getConstructors", Vector{JavaCall.JConstructor}, ()),
        args...
    )
    if paramtypes === nothing
        Base.error("No matching constructor call for arguments $(Tuple(map(typeof, args)))")
    end

    local res = JavaCall.jnew(Symbol(classname), Tuple(paramtypes), args...)
    wrapped(res)
end