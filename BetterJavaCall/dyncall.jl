isassignablefrom(t::Type{InstanceProxy{T}}, x::InstanceProxy{U}) where {T, U} = isassignablefrom(t, typeof(x))
isassignablefrom(::Type{InstanceProxy{T}}, ::Type{InstanceProxy{U}}) where {T, U <: T} = true
isassignablefrom(::Type{InstanceProxy{T}}, ::Type{InstanceProxy{U}}) where {T, U} = begin
    local metaclassT = JavaCall.classforname(_classnameFromTypeTagSymbol(T))
    local metaclassU = JavaCall.classforname(_classnameFromTypeTagSymbol(U))
    Bool(JavaCall.jcall(metaclassT, "isAssignableFrom", JavaCall.jboolean, (JavaCall.JClass,), metaclassU))
end

arg_is_compatible(t::Type, x) = applicable(Base.convert, t, x)
# fast-path for superclasses
arg_is_compatible(::Type{InstanceProxy{T}}, ::InstanceProxy{U}) where {T, U <: T} = true
arg_is_compatible(t::Type{InstanceProxy{T}}, x::InstanceProxy{U}) where {T, U} = isassignablefrom(t, x)

method_is_applicable(paramtypes::Vector{<: Type}, is_varargs::Bool, args...) =
    if length(paramtypes) < length(args) && is_varargs
        # check non-varargs
        if !all(map(((p, a)::Tuple) -> arg_is_compatible(p, a), zip(paramtypes[1:end-1], args[1:end-1])))
            return false
        end

        arg_is_compatible(paramtypes[end], [el for el in args[length(paramtypes):end]])
    elseif length(paramtypes) == length(args)
        # check all but last arg/param
        if !all(map(((p, a)::Tuple) -> arg_is_compatible(p, a), zip(paramtypes[1:end-1], args[1:end-1])))
            return false
        end

        arg_is_compatible(paramtypes[end], args[end]) || (is_varargs && arg_is_compatible(paramtypes[end], [args[end]]))
    else
        false
    end

arg_type_lt(::Type{Vector{T}}, ::Type{Vector{U}}) where {T, U} = arg_type_lt(T, U)
arg_type_lt(t::Type{InstanceProxy{T}}, u::Type{InstanceProxy{U}}) where {T, U} =
    !isassignablefrom(t, u) && isassignablefrom(u, t)
arg_type_lt(t::Type{InstanceProxy{T}}, ::Type{U}) where {T, U} = true
arg_type_lt(::Type{T}, u::Type{InstanceProxy{U}}) where {T, U} = false
arg_type_lt(::Type{T}, ::Type{U}) where {U, T <: U} = true
arg_type_lt(::Type{T}, ::Type{U}) where {T, U} = false

variant_lt(v1::Tuple, v2::Tuple) = begin
    local v1_isvarargs = isvarargs(v1[1])
    local v2_isvarargs = isvarargs(v2[1])
    local v1paramcount = v1_isvarargs ? length(v1[2]) - 1 : length(v1[2])
    local v2paramcount = v2_isvarargs ? length(v2[2]) - 1 : length(v2[2])

    variant_arg_types_lt(v1[2], v2[2]) ||
        v1paramcount < v2paramcount ||
        v1_isvarargs && !v2_isvarargs
end
variant_arg_types_lt(argtypes1::Vector{<: Type}, argtypes2::Vector{<: Type}) = begin
    for (a, b) in zip(argtypes1, argtypes2)
        if !arg_type_lt(a, b)
            return false
        end
    end

    true
end

getvariantparamtypes(method_or_ctor::Union{JavaCall.JMethod, JavaCall.JConstructor}) =
    map(
        t -> wrapped(normalizeJavaType(t)),
        JavaCall.getparametertypes(method_or_ctor)
    )

choosevariant(variants::Vector{T}, args...) where {T <: Union{JavaCall.JMethod, JavaCall.JConstructor}} = begin
    variants = map(v -> (v, getvariantparamtypes(v)), variants)
    local applicable = filter(v -> method_is_applicable(v[2], isvarargs(v[1]), args...), variants)
    if isempty(applicable)
        return nothing
    end

    sort!(applicable, lt=variant_lt)
    last(applicable)[1] # just return the variant (method/constructor)
end

dyncallmethod(recv::Type{JavaCall.JavaObject{C}}, name::String, args...) where {C} =
    dyncallmethod(recv, recv, name, args...)
dyncallmethod(recv::JavaCall.JavaObject{C}, name::String, args...) where {C} =
    dyncallmethod(recv, typeof(recv), name, args...)
dyncallmethod(recv, t::Type{JavaCall.JavaObject{C}}, name::String, args...) where {C} = begin
    local method = choosevariant(
        filter(m -> JavaCall.getname(m) == name, JavaCall.listmethods(t)),
        args...
    )
    if method === nothing
        Base.error("No matching method call for arguments $(Tuple(map(typeof, args)))")
    end

    local rettype = normalizeJavaType(JavaCall.getreturntype(method))

    local paramtypes = Tuple(map(normalizeJavaType, JavaCall.getparametertypes(method)))
    args = dyncall_fixargs(method, paramtypes, args)
    local res = JavaCall.jcall(recv, name, rettype, paramtypes, args...)
    wrapped(res)
end

dyncallctor(classname::String, args...) = begin
    local metaclass = JavaCall.classforname(classname)
    local ctor = choosevariant(
        JavaCall.jcall(metaclass, "getConstructors", Vector{JavaCall.JConstructor}, ()),
        args...
    )
    if ctor === nothing
        Base.error("No matching constructor call for arguments $(Tuple(map(typeof, args)))")
    end

    local paramtypes = Tuple(map(normalizeJavaType, JavaCall.getparametertypes(ctor)))
    args = dyncall_fixargs(ctor, paramtypes, args)
    local res = JavaCall.jnew(Symbol(classname), paramtypes, args...)
    wrapped(res)
end

dyncall_fixargs(method, paramtypes, args) = begin
    if isvarargs(method) && (length(args) > length(paramtypes) || _vanestlvl(args[end]) == _vanestlvl(paramtypes[end]) || args[end] isa Tuple)
        local normalargs = Vector{Any}([a for a in args[1:length(paramtypes)-1]])
        local vatype = wrapped(componenttype(paramtypes[end]))
        local varargs = [va for va in vaconvert(vatype, args[length(paramtypes):end])]
        push!(normalargs, varargs)
        args = normalargs
    end

    map(unwrapped, args)
end

_vanestlvl(::T) where {T} = _vanestlvl(T)
_vanestlvl(::Type{Vector{T}}) where {T} = 1 + _vanestlvl(T)
_vanestlvl(::Type{T}) where {T} = 0