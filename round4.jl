import Pkg
Pkg.add("JavaCall")

##
module BetterJavaCall
    export ImportProxy, InstanceProxy, @jimport

    using JavaCall

    function init(args...)
        JavaCall.init(args...)
    end

    macro jimport(class::Expr)
        class = sprint(Base.show_unquoted, class)
        :(javaImport($class))
    end
    macro jimport(class::Symbol)
        class = string(class)
        :(javaImport($class))
    end
    macro jimport(class::AbstractString)
        :(javaImport($class))
    end

    Base.show(io::IO, obj::JavaCall.JavaObject) =
        print(io, jcall(obj, "toString", JString, ()))

    struct ImportProxy
        mod::Module
    end

    Base.show(io::IO, proxy::ImportProxy) =
        print(io, "Java Import " * getfield(proxy, :mod).name)

    Base.getproperty(proxy::ImportProxy, sym::Symbol) = begin
        if sym == :δmethods
            getfield(proxy, :mod).static_methods
        elseif sym == :δfields
            getfield(proxy, :mod).static_fields
        elseif sym == :δmod
            getfield(proxy, :mod)
        elseif sym == :class
            wrapped(getfield(proxy, :mod).class_class)
        elseif haskey(getfield(proxy, :mod).static_methods, sym)
            eval(:( getfield($proxy, :mod).static_methods.$sym ))
        elseif haskey(getfield(proxy, :mod).static_fields, sym)
            eval(:( getfield($proxy, :mod).static_fields.$sym() )) # call the getter
        else
            local classname = getfield(proxy, :mod).name
            Base.error("class $(classname) has no static method/field $(string(sym))")
        end
    end

    Base.setproperty!(proxy::ImportProxy, sym::Symbol, v::Any) = begin
        if haskey(getfield(proxy, :mod).static_fields, sym)
            eval(:( getfield($proxy, :mod).$sym($v) )) # call the setter
        else
            local classname = getfield(proxy, :mod).name
            Base.error("class $(classname) has no static field $(string(sym))")
        end
    end

    struct InstanceProxy
        ref::JavaCall.JavaObject
        mod::Module
    end

    Base.show(io::IO, proxy::InstanceProxy) =
        show(io, getfield(proxy, :ref))

    Base.getproperty(proxy::InstanceProxy, sym::Symbol) = begin
        local this = getfield(proxy, :ref)
        if sym == :δmethods
            getfield(proxy, :mod).instance_methods(this)
        elseif sym == :δfields
            getfield(proxy, :mod).instance_fields(this)
        elseif haskey(getfield(proxy, :mod).instance_methods, sym)
            eval(:( getfield($proxy, :mod).instance_methods.$sym($this) ))
        elseif haskey(getfield(proxy, :mod).instance_fields, sym)
            eval(:( getfield($proxy, :mod).instance_fields.$sym($this)() )) # call the getter
        else
            local classname = getfield(proxy, :mod).name
            Base.error("class $(classname) has no instance method/field $(string(sym))")
        end
    end

    Base.setproperty!(proxy::InstanceProxy, sym::Symbol, v::Any) = begin
        local this = getfield(proxy, :ref)
        if haskey(getfield(proxy, :mod).instance_fields, sym)
            eval(:( getfield($proxy, :mod).instance_fields.$sym($this)(v) )) # call the setter
        else
            local classname = getfield(proxy, :mod).name
            Base.error("class $(classname) has no instance field $(string(sym))")
        end
    end

    mdf = JavaCall.@jimport java.lang.reflect.Modifier
    isstatic(method::Union{JavaCall.JField,JavaCall.JMethod}) = begin
        local modifiers = JavaCall.jcall(method, "getModifiers", JavaCall.jint, ())
        Bool(JavaCall.jcall(mdf, "isStatic", JavaCall.jboolean, (JavaCall.jint,), modifiers))
    end
    isfinal(method::Union{JavaCall.JField,JavaCall.JMethod}) = begin
        local modifiers = JavaCall.jcall(method, "getModifiers", JavaCall.jint, ())
        Bool(JavaCall.jcall(mdf, "isFinal", JavaCall.jboolean, (JavaCall.jint,), modifiers))
    end

    normalizeJavaType(name::Union{Core.String,Base.SubString}) = begin
        if name == "short" || name == "java.lang.Short"
            JavaCall.jshort
        elseif name == "int" || name == "java.lang.Integer"
            JavaCall.jint
        elseif name == "long" || name == "java.lang.Long"
            JavaCall.jlong
        elseif name == "byte" || name == "java.lang.Byte"
            JavaCall.jbyte
        elseif name == "char" || name == "java.lang.Char"
            JavaCall.jchar
        elseif name == "float" || name == "java.lang.Float"
            JavaCall.jfloat
        elseif name == "double" || name == "java.lang.Double"
            JavaCall.jdouble
        elseif name == "boolean" || name == "java.lang.Boolean"
            JavaCall.jboolean
        elseif name == "void" || name == "java.lang.Void"
            JavaCall.jvoid
        elseif (m = Base.match(r"[^\][]+((\[])+)", name); typeof(m) != Nothing)
            local n = m.captures[1].ncodeunits ÷ 2
            local name_len = length(name) - m.captures[1].ncodeunits
            Array{normalizeJavaType(Base.SubString(name, 1:name_len)),n}
        else
            # TODO: wrapper? maybe?
            JavaCall.JavaObject{Symbol(name)}
        end
    end

    normalizeJavaType(x::JavaCall.JClass) = begin
        normalizeJavaType(getname(x))
    end

    java_primitive_types = Core.Union{Int8, Int16, Int32, Int64, UInt16, Float32, Float64, Nothing}

    unwrapped(x::InstanceProxy) = getfield(x, :ref)
    unwrapped(x::Union{JavaCall.JavaObject, java_primitive_types}) = x
    unwrapped(x::Array{T, N}) where {T, N} = map(unwrapped, x)
    unwrapped(x::Bool) = UInt8(x) # kinda ugly, but nothing else is a UInt8
    unwrapped(::Type{Bool}) = UInt8
    unwrapped(t::Type{<: Union{JavaCall.JavaObject, java_primitive_types}}) = t
    unwrapped(::Type{<: InstanceProxy}) = JavaCall.JavaObject
    unwrapped(::Type{Array{T, N}}) where {T, N} = Array{unwrapped(T), N}

    wrapped(x::Union{InstanceProxy, java_primitive_types, String}) = x
    wrapped(x::JavaCall.JavaObject{C}) where {C} = begin
        local classname = string(C)
        local mod = getfield(javaImport(classname), :mod)

        InstanceProxy(x, mod)
    end
    wrapped(x::Array{T, N}) where {T, N} = map(wrapped, x)
    wrapped(x::UInt8) = Bool(x) # kinda ugly, but nothing else is a UInt8
    wrapped(::Type{UInt8}) = Bool
    wrapped(::Type{<: JavaCall.JavaObject}) = InstanceProxy
    wrapped(t::Type{<: Union{InstanceProxy, java_primitive_types}}) = t
    wrapped(::Type{Array{T, N}}) where {T, N} = Array{wrapped(T), N}

    javaClassModuleName(classname::String) = "PAvaJavaInterop Class " * classname

    function javaImport(classname::String)
        if ! Base.isdefined(Main.BetterJavaCall, Symbol(javaClassModuleName(classname)))
            loadJavaClass(classname)
        end

        mod = eval(Symbol(javaClassModuleName(classname)))
        ImportProxy(mod)
    end

    function loadJavaClass(classname::String)
        local class = eval(JavaCall._jimport(classname))
        local mod_name = javaClassModuleName(classname)

        eval(:(
            module $(Symbol(mod_name))
                using JavaCall
                using Main.BetterJavaCall: wrapped, unwrapped

                class_class = $(JavaCall.classforname(classname))
                class_type = $class
                name = $classname
            end
        ))
        local mod = eval(Symbol(mod_name))
        local inst_param = :(inst::$(class))

        local instance_method_names = Set{String}()
        local static_method_names = Set{String}()
        for method in JavaCall.listmethods(class)
            local name = getname(method)
            local returntype = normalizeJavaType(getreturntype(method))
            local parametertypes = Tuple(normalizeJavaType(p) for p in getparametertypes(method))
            local parameternames = [:($(Symbol("p" * string(i)))) for i in 1:length(parametertypes)]
            local typed_parameters = [:($(a[1])::$(wrapped(a[2]))) for a in zip(parameternames, parametertypes)]

            local newmethod_def = if (isstatic(method))
                push!(static_method_names, name);

                quote
                    function $(Symbol("sm_" * name))($(typed_parameters...))
                        $(( :($pn = unwrapped($pn)) for pn in parameternames )...);

                        local res = JavaCall.jcall($class, $name, $returntype, $parametertypes, $(parameternames...))
                        wrapped(res)
                    end
                end
            else
                push!(instance_method_names, name);

                # TODO: overloads are impossible
                quote
                    function $(Symbol("im_" * name))(inst::$class)
                        ($(typed_parameters...),) -> begin
                            $(( :($pn = unwrapped($pn)) for pn in parameternames )...);

                            local res = JavaCall.jcall(inst, $name, $returntype, $parametertypes, $(parameternames...))
                            wrapped(res)
                        end
                    end
                end
            end

            Base.eval(mod, newmethod_def)
        end

        local static_field_names = Set{String}()
        local instance_field_names = Set{String}()
        for field in JavaCall.listfields(class)
            local name = JavaCall.getname(field)
            local type = normalizeJavaType(JavaCall.jcall(field, "getType", JClass, ()))

            if isstatic(field)
                # TODO: use better setter than the boxed get/set
                local getter = :( $(Symbol("sf_" * name))() = wrapped(JavaCall.jfield($class, $name, $type)) )
                Base.eval(mod, getter)

                if !isfinal(field)
                    local setter = :( $(Symbol("sf_" * name))(val::$(wrapped(type))) = JavaCall.jcall($field, "set", Nothing, ($type,), unwrapped(val)) )
                    Base.eval(mod, setter)
                end

                push!(static_field_names, name)
            else
                # TODO: use better setter than the boxed get/set
                local getter = :( $(Symbol("if_" * name))($inst_param) = wrapped(JavaCall.jfield($class, $name, $type)) )
                Base.eval(mod, getter)

                if !isfinal(field)
                    local setter = quote
                        function $(Symbol("if_" * name))($inst_param, val::$(wrapped(type)))
                            JavaCall.jcall($field, "set", JavaCall.jvoid, ($type,), unwrapped(val))
                        end
                    end
                    Base.eval(mod, mod)
                end

                push!(instance_field_names, name)
            end
        end

        local instance_methods = (:($(Symbol(n)) = $(Symbol("im_" * n))) for n in instance_method_names)
        local static_methods = (:($(Symbol(n)) = $(Symbol("sm_" * n))) for n in static_method_names)
        local instance_fields = (:($(Symbol(n)) = $(Symbol("if_" * n))) for n in instance_field_names)
        local static_fields = (:($(Symbol(n)) = $(Symbol("sf_" * n))) for n in static_field_names)

        Base.eval(mod, quote
            instance_methods = ($(instance_methods...),)
            static_methods = ($(static_methods...),)
            instance_fields = ($(instance_fields...),)
            static_fields = ($(static_fields...),)
        end)

        Base.eval(mod, :( new() = $("TODO: should be a constructor") )) # get all constructors
    end

    Base.convert(::Type{BetterJavaCall.InstanceProxy}, s::String) = wrapped(JavaCall.JString(s))
    Base.convert(::Type{String}, x::BetterJavaCall.InstanceProxy) = String(unwrapped(x))
end

##
using Main.BetterJavaCall
BetterJavaCall.init(["-Xmx128M"])
##

LocalDate = @jimport java.time.LocalDate

LocalDate.now()