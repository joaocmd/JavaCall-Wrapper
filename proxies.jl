import JavaCall

Base.show(io::IO, obj::JavaCall.JavaObject) =
    if JavaCall.isnull(obj)
        print(io, "null")
    else
        print(io, JavaCall.jcall(obj, "toString", JavaCall.JString, ()))
    end
Base.show(io::IO, js::JavaCall.JString) =
    if JavaCall.isnull(js)
        print(io, "null")
    else
        print(io, convert(AbstractString, js))
    end

struct ImportProxy{T <: JavaTypeTag}
    mod::Module
end

Base.show(io::IO, proxy::ImportProxy) =
    print(io, "Java Import " * proxy.δmod.name)

Base.getproperty(proxy::ImportProxy, sym::Symbol) = begin
    if sym == :δmod
        # getfield is tiring, and most things are in δmod
        # use this as our (very short) recursion base case
        getfield(proxy, :mod)
    elseif sym == :δmethods
        proxy.δmod.static_methods
    elseif sym == :δfields
        proxy.δmod.static_fields
    elseif sym == :class
        wrapped(proxy.δmod.class)
    elseif sym == :new
        proxy.δmod.new
    elseif hasproperty(proxy.δmod.static_methods, sym)
        getfield(proxy.δmod.static_methods, sym)
    elseif hasproperty(proxy.δmod.static_fields, sym)
        getfield(proxy.δmod.static_fields, sym)() # call the getter
    else
        local classname = proxy.δmod.name
        Base.error("class $(classname) has no static method/field $(string(sym))")
    end
end

Base.setproperty!(proxy::ImportProxy, sym::Symbol, v::Any) = begin
    if hasproperty(proxy.δmod.static_fields, sym)
        getfield(proxy.δmod, sym)(v) # call the setter
    else
        local classname = proxy.δmod.name
        Base.error("class $(classname) has no static field $(string(sym))")
    end
end

Base.propertynames(proxy::ImportProxy) = union(
    (:class,),
    Base.propertynames(proxy.δmod.static_methods),
    Base.propertynames(proxy.δmod.static_fields),
    Base.isdefined(proxy.δmod, :new) ? (:new,) : (),
)

struct InstanceProxy{T <: JavaTypeTag}
    ref::JavaCall.JavaObject
    mod::Module
end

Base.show(io::IO, proxy::InstanceProxy) =
    show(io, proxy.δref)

Base.getproperty(proxy::InstanceProxy, sym::Symbol) = begin
    local this = getfield(proxy, :ref)
    if sym == :δmod
        # getfield is tiring, and most things are in δmod and δref
        # use this as our (very short) recursion base case
        getfield(proxy, :mod)
    elseif sym == :δref
        # getfield is tiring, and most things are in δmod and δref
        # use this as our (very short) recursion base case
        this
    elseif sym == :δmethods
        # bind methods to this instance
        NamedTuple(map(
            p -> (p.first, (args...) -> p.second(this, args...)),
            pairs(proxy.δmod.instance_methods)
        ))
    elseif sym == :δfields
        # bind field getters to this instance
        NamedTuple(map(
            p -> (p.first, p.second(this)),
            pairs(proxy.δmod.instance_fields)
        ))
    elseif hasproperty(proxy.δmod.instance_methods, sym)
        local method = getfield(proxy.δmod.instance_methods, sym)
        (args...) -> method(this, args...)
    elseif hasproperty(proxy.δmod.instance_fields, sym)
        getfield(proxy.δmod.instance_fields, sym)(this)() # call the getter
    else
        local classname = proxy.δmod.name
        Base.error("class $(classname) has no instance method/field $(string(sym))")
    end
end

Base.propertynames(proxy::InstanceProxy) = union(
    Base.propertynames(proxy.δmod.instance_methods),
    Base.propertynames(proxy.δmod.instance_fields)
)

Base.setproperty!(proxy::InstanceProxy, sym::Symbol, v::Any) = begin
    local this = proxy.δref
    if hasproperty(proxy.δmod.instance_fields, sym)
        getfield(proxy.δmod.instance_fields, sym)(this)(v) # call the setter
    else
        local classname = proxy.δmod.name
        Base.error("class $(classname) has no instance field $(string(sym))")
    end
end

Base.getproperty(ex::JavaException, sym::Symbol) =
    if sym ∈ (:msg, :ref)
        getfield(ex, sym)
    else
        getfield(wrapped(ex.ref), sym)
    end

Base.setproperty!(ex::JavaException, sym::Symbol, val) =
    if sym ∈ (:msg, :ref)
        setfield!(ex, sym, val)
    else
        setfield!(wrapped(ex.ref), sym, val)
    end

Base.propertynames(ex::JavaException) = begin
    # do try to make autocomplete better, but fail gracefully if errors occur
    local inner_names = try
        Base.propertynames(wrapped(ex.ref))
    catch
        ()
    end

    union((:msg, :ref), inner_names)
end