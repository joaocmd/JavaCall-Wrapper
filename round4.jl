#import Pkg
#Pkg.add("JavaCall")

##
module BetterJavaCall
    export ImportProxy, InstanceProxy, @jimport, JString, tojstring

    using JavaCall

    init(args...) = JavaCall.init(args...)

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
        if JavaCall.isnull(obj)
            print(io, "null")
        else
            print(io, jcall(obj, "toString", JString, ()))
        end
    Base.show(io::IO, js::JavaCall.JString) =
        if JavaCall.isnull(obj)
            show(io, "null")
        else
            show(io, convert(AbstractString, js))
        end

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
            wrapped(getfield(proxy, :mod).class)
        elseif sym == :new
            getfield(proxy, :mod).new
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

    Base.propertynames(proxy::ImportProxy) = union(
        Base.propertynames(getfield(proxy, :mod).static_methods),
        Base.propertynames(getfield(proxy, :mod).static_fields)
    )

    abstract type JavaTypeTag end

    struct InstanceProxy{T <: JavaTypeTag}
        ref::JavaCall.JavaObject
        mod::Module
    end

    Base.show(io::IO, proxy::InstanceProxy) =
        show(io, getfield(proxy, :ref))

    Base.getproperty(proxy::InstanceProxy, sym::Symbol) = begin
        local this = getfield(proxy, :ref)
        if sym == :δmethods
            getfield(proxy, :mod).instance_methods
        elseif sym == :δfields
            getfield(proxy, :mod).instance_fields
        elseif haskey(getfield(proxy, :mod).instance_methods, sym)
            local method = eval(:( getfield($proxy, :mod).instance_methods.$sym ))
            (args...) -> method(this, args...)
        elseif haskey(getfield(proxy, :mod).instance_fields, sym)
            eval(:( getfield($proxy, :mod).instance_fields.$sym($this)() )) # call the getter
        else
            local classname = getfield(proxy, :mod).name
            Base.error("class $(classname) has no instance method/field $(string(sym))")
        end
    end

    Base.propertynames(proxy::InstanceProxy) = union(
        Base.propertynames(getfield(proxy, :mod).instance_methods),
        Base.propertynames(getfield(proxy, :mod).instance_fields)
    )

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
            Array{normalizeJavaType(Base.SubString(name, 1:name_len)),n}
        else
            # TODO: wrapper? maybe?
            JavaCall.JavaObject{Symbol(name)}
        end
    end

    normalizeJavaType(x::JavaCall.JClass) = begin
        normalizeJavaType(getname(x))
    end

    java_primitive_types = Core.Union{Int8, Int16, Int32, Int64, Float32, Float64, Nothing}

    unwrapped(x::InstanceProxy) = getfield(x, :ref)
    unwrapped(::Nothing) = JavaCall.JObject(JavaCall.JavaNullRef())
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

    javaClassModuleName(classname::String) = "PAvaJavaInterop Class " * classname

    javaImport(classname::String) = begin
        if ! Base.isdefined(Main.BetterJavaCall, Symbol(javaClassModuleName(classname)))
            loadJavaClass(classname)
        end

        mod = eval(Symbol(javaClassModuleName(classname)))
        ImportProxy(mod)
    end

    _typeTagSymbolForName(name::String) = Symbol("JavaTypeTag" * name)
    _classnameFromTypeTagSymbol(t::Type{<: JavaTypeTag}) = split(String(Base.nameof(t)), "JavaTypeTag", limit=2)[2]

    typeTagForName(name::String) = begin
        local typetags = _typeTagSymbolForName(name)
        if ! Base.isdefined(Main.BetterJavaCall, typetags)
            local class = JavaCall.classforname(name)
            local isinterface = Bool(JavaCall.jcall(class, "isInterface", JavaCall.jboolean, ()))

            local superclasstag = if !isinterface && name != "java.lang.Object"
                local superclass = JavaCall.jcall(class, "getSuperclass", JavaCall.JClass, ())
                local superclassname = JavaCall.getname(superclass)
                typeTagForName(superclassname) # ensure it is created
                _typeTagSymbolForName(superclassname)
            else
                :JavaTypeTag
            end

            local def = quote
                abstract type $typetags <: $superclasstag end
            end

            eval(def)
        end

        eval(typetags)
    end

    javaMetaclass(classname::String) = wrapped(JavaCall.classforname(classname))

    arg_is_compatible(t::Type, x) = applicable(Base.convert, t, x)
    # fast-path for superclasses
    arg_is_compatible(::Type{InstanceProxy{T}}, ::InstanceProxy{U}) where {T, U <: T} = true
    arg_is_compatible(::Type{InstanceProxy{T}}, ::InstanceProxy{U}) where {T, U} = begin
        local metaclassT = javaMetaclass(_classnameFromTypeTagSymbol(T))
        local metaclassU = javaMetaclass(_classnameFromTypeTagSymbol(U))
        metaclassT.IsAssignableFrom(metaclassU)
    end

    method_is_applicable(argtypes::Tuple{Type}, args...) = all(map(arg_is_compatible, zip(argtypes, args)))

    arg_type_lt(::Type{InstanceProxy{T}}, ::Type{InstanceProxy{U}}) where {T, U} = begin
        local metaclassT = javaMetaclass(_classnameFromTypeTagSymbol(T))
        local metaclassU = javaMetaclass(_classnameFromTypeTagSymbol(U))

        !metaclassT.isAssignableFrom(metaclassU) && metaclassU.isAssignableFrom(metaclassT)
    end

    variant_arg_types_lt(argtypes1::Vector{Type}, argtypes2::Vector{Type}) = begin
        for (a, b) in zip(argtypes1, argtypes2)
            if !arg_type_lt(a, b)
                return false
            end
        end

        true
    end

    choosevariant(variants::Vector{Vector{Type}}, args...) = begin
        local argtypes = map(typeof, args)
        local applicable = filter(paramtypes -> method_is_applicable(paramtypes, argtypes), variants)

        sort!(applicable, lt=variant_arg_types_lt)
        last(applicable)
    end

    getparamtypes(method_or_ctor::InstanceProxy) = map(c -> unwrapped(normalizeJavaType(c.getName())), method_or_ctor.getParameterTypes())

    dyncallmethod(recv::Type{JavaCall.JavaObject{C}}, name::String, args...) where {C} =
        dyncallmethod(recv, javaMetaclass(string(C)), name, args...)
    dyncallmethod(recv::JavaCall.JavaObject{C}, name::String, args...) where {C} =
        dyncallmethod(recv, javaMetaclass(string(C)), name, args...)
    dyncallmethod(recv, metaclass::InstanceProxy, name::String, args...) = begin
        args = map(unwrapped, args)
        # TODO: don't use InstanceProxy, because circular deps
        local methods = filter(m -> m.getName() == name, metaclass.getMethods())
        local methods_paramtypes = [getparamtypes(m) for m in methods]
        local rettype = unwrapped(normalizeJavaType(methods[0].getReturnType().getName()))

        local paramtypes = Tuple(choosevariant(methods_paramtypes, args...))
        local res = JavaCall.jcall(recv, name, rettype, paramtypes, args...)
        wrapped(res)
    end

    dyncallctor(classname::String, args...) = begin
        args = map(unwrapped, args)
        # TODO: don't use InstanceProxy, because circular deps
        local metaclass = javaMetaclass(classname)
        local ctors = metaclass.getConstructors()
        local ctor_paramtypes = [getparamtypes(c) for c in ctors]

        local paramtypes = Tuple(choosevariant(ctor_paramtypes, args...))
        local res = JavaCall.jnew(Symbol(classname), paramtypes)
        wrapped(res)
    end

    loadJavaClassMethods(mod) = begin
        local instance_method_names = Set{String}()
        local static_method_names = Set{String}()

        for method in JavaCall.listmethods(mod.class_type)
            local name = getname(method)
            local returntype = normalizeJavaType(getreturntype(method))
            local parametertypes = Tuple(normalizeJavaType(p) for p in getparametertypes(method))
            local parameternames = [Symbol("p" * string(i)) for i in 1:length(parametertypes)]
            local typed_parameters = [:($(a[1])::$(wrapped(a[2]))) for a in zip(parameternames, parametertypes)]

            local (sym_prefix, receiver) = if isstatic(method)
                push!(static_method_names, name)
                ("sm_", mod.class_type)
            else
                push!(instance_method_names, name)
                typed_parameters = [:( inst::$(mod.class_type) ), typed_parameters...]
                ("im_", :inst)
            end

            local def = quote
                $(Symbol(sym_prefix * name))($(typed_parameters...)) = begin
                    $(( :($pn = unwrapped($pn)) for pn in parameternames )...);

                    local res = JavaCall.jcall($receiver, $name, $returntype, $parametertypes, $(parameternames...))
                    wrapped(res)
                end
            end
            Base.eval(mod, def)
        end

        for methodname in instance_method_names
            Base.eval(mod, quote
                $(Symbol("im_" * methodname))(inst::$(mod.class_type), args...) =
                    $dyncallmethod(inst, $methodname, args...)
            end)
        end
        for methodname in static_method_names
            Base.eval(mod, quote
                $(Symbol("sm_" * methodname))(args...) =
                    $dyncallmethod($(mod.class_type), $methodname, args...)
            end)
        end

        local instance_methods = (:($(Symbol(n)) = $(Symbol("im_" * n))) for n in instance_method_names)
        local static_methods = (:($(Symbol(n)) = $(Symbol("sm_" * n))) for n in static_method_names)
        Base.eval(mod, quote
            instance_methods = ($(instance_methods...),)
            static_methods = ($(static_methods...),)
        end)
    end

    loadJavaClassFields(mod) = begin
        local instance_field_names = Set{String}()
        local static_field_names = Set{String}()

        for field in JavaCall.listfields(mod.class_type)
            local name = JavaCall.getname(field)
            local type = normalizeJavaType(JavaCall.jcall(field, "getType", JClass, ()))

            if isstatic(field)
                # TODO: use better setter than the boxed get/set
                local getter = quote
                    function $(Symbol("sf_" * name))()
                        local res = JavaCall.jfield($(mod.class_type), $name, $type)
                        wrapped(res)
                    end
                end
                Base.eval(mod, getter)

                if !isfinal(field)
                    local setter = quote
                        function $(Symbol("sf_" * name))(val::$(wrapped(type)))
                            JavaCall.jcall($field, "set", Nothing, ($type,), unwrapped(val));
                        end
                    end
                    Base.eval(mod, setter)
                end

                push!(static_field_names, name)
            else
                # TODO: use better setter than the boxed get/set
                local getter = quote
                    function $(Symbol("if_" * name))(inst::$(mod.class_type))
                        local res = JavaCall.jfield($(mod.class_type), $name, $type)
                        wrapped(res)
                    end
                end
                Base.eval(mod, getter)

                if !isfinal(field)
                    local setter = quote
                        function $(Symbol("if_" * name))(inst::$(mod.class_type), val::$(wrapped(type)))
                            JavaCall.jcall($field, "set", JavaCall.jvoid, ($type,), unwrapped(val))
                        end
                    end
                    Base.eval(mod, setter)
                end

                push!(instance_field_names, name)
            end
        end

        local instance_fields = (:($(Symbol(n)) = $(Symbol("if_" * n))) for n in instance_field_names)
        local static_fields = (:($(Symbol(n)) = $(Symbol("sf_" * n))) for n in static_field_names)
        Base.eval(mod, quote
            instance_fields = ($(instance_fields...),)
            static_fields = ($(static_fields...),)
        end)
    end

    loadJavaClassConstructors(mod) = begin
        local constructors = JavaCall.jcall(mod.class, "getConstructors", Vector{JavaCall.JConstructor}, ())

        for ctor in constructors
            local parametertypes = begin
                local types = JavaCall.jcall(ctor, "getParameterTypes", Vector{JavaCall.JClass}, ())
                Tuple(normalizeJavaType(JavaCall.getname(t)) for t in types)
            end
            local parameternames = [:($(Symbol("p" * string(i)))) for i in 1:length(parametertypes)]
            local typed_parameters = [:($(a[1])::$(wrapped(a[2]))) for a in zip(parameternames, parametertypes)]

            local ctordef = quote
                function new($(typed_parameters...))
                    $(( :($pn = unwrapped($pn)) for pn in parameternames )...);

                    local res = JavaCall.jnew(Symbol($(mod.name)), $parametertypes, $(parameternames...))
                    wrapped(res)
                end
            end
            Base.eval(mod, ctordef)
        end

        Base.eval(mod, quote
            new(args...) = $dyncallctor($(mod.name), args...)
        end)
    end

    loadJavaClass(classname::String) = begin
        local class = eval(JavaCall._jimport(classname))
        local mod_name = javaClassModuleName(classname)

        eval(:(
            module $(Symbol(mod_name))
                using JavaCall
                using Main.BetterJavaCall: wrapped, unwrapped

                class_type = $class
                class = $(JavaCall.classforname(classname))
                name = $classname
            end
        ))
        local mod = eval(Symbol(mod_name))

        loadJavaClassMethods(mod)
        loadJavaClassFields(mod)
        loadJavaClassConstructors(mod)
    end

    (cast_target::ImportProxy)(inst::InstanceProxy) = begin
        local targetmod = getfield(cast_target, :mod)
        local targetclass = targetmod.class
        local targetclassname = targetmod.name

        # will throw exception if cast is impossible
        local ref = JavaCall.jcall(targetclass, "cast", JavaCall.JObject, (JavaCall.JObject,), getfield(inst, :ref))
        InstanceProxy{typeTagForName(targetclassname)}(ref, targetmod)
    end
    (cast_target::ImportProxy)(::Nothing) = begin # nulls are compatible with every type
        local targetmod = getfield(cast_target, :mod)
        local targetclassname = targetmod.name
        local ref = JavaCall.JavaObject{Symbol(targetclassname)}(JavaCall.JavaNullRef())
        InstanceProxy{typeTagForName(targetclassname)}(ref, targetmod)
    end

    Base.convert(::Type{InstanceProxy{T}}, x::InstanceProxy{U}) where {T, U} = javaImport(_classnameFromTypeTagSymbol(T))(x)

    # create type tags necessary for conversions without a java runtime running
    eval(quote
        abstract type $(_typeTagSymbolForName("java.lang.Object")) <: JavaTypeTag end
        abstract type $(_typeTagSymbolForName("java.lang.Number")) <: $(_typeTagSymbolForName("java.lang.Object")) end

        abstract type $(_typeTagSymbolForName("java.lang.String")) <: $(_typeTagSymbolForName("java.lang.Object")) end
        abstract type $(_typeTagSymbolForName("java.lang.Boolean")) <: $(_typeTagSymbolForName("java.lang.Object")) end
        abstract type $(_typeTagSymbolForName("java.lang.Character")) <: $(_typeTagSymbolForName("java.lang.Object")) end

        abstract type $(_typeTagSymbolForName("java.lang.Byte")) <: $(_typeTagSymbolForName("java.lang.Number")) end
        abstract type $(_typeTagSymbolForName("java.lang.Short")) <: $(_typeTagSymbolForName("java.lang.Number")) end
        abstract type $(_typeTagSymbolForName("java.lang.Integer")) <: $(_typeTagSymbolForName("java.lang.Number")) end
        abstract type $(_typeTagSymbolForName("java.lang.Long")) <: $(_typeTagSymbolForName("java.lang.Number")) end
        abstract type $(_typeTagSymbolForName("java.lang.Float")) <: $(_typeTagSymbolForName("java.lang.Number")) end
        abstract type $(_typeTagSymbolForName("java.lang.Double")) <: $(_typeTagSymbolForName("java.lang.Number")) end
    end)

    Base.convert(::Type{InstanceProxy{typeTagForName("java.lang.String")}}, x::AbstractString) = InstanceProxy{typeTagForName("java.lang.String")}(JavaCall.JString(x), javaImport("java.lang.String").δmod)
    Base.convert(::Type{InstanceProxy{typeTagForName("java.lang.Boolean")}}, x::Union{Bool, JavaCall.jboolean}) = javaImport("java.lang.Boolean").valueOf(JavaCall.jboolean(x))
    Base.convert(::Type{InstanceProxy{typeTagForName("java.lang.Character")}}, x::Union{Char, JavaCall.jchar}) = javaImport("java.lang.Character").valueOf(JavaCall.jchar(x))
    Base.convert(::Type{InstanceProxy{typeTagForName("java.lang.Byte")}}, x::JavaCall.jbyte) = javaImport("java.lang.Byte").valueOf(x)
    Base.convert(::Type{InstanceProxy{typeTagForName("java.lang.Short")}}, x::JavaCall.jshort) = javaImport("java.lang.Short").valueOf(x)
    Base.convert(::Type{InstanceProxy{typeTagForName("java.lang.Integer")}}, x::JavaCall.jint) = javaImport("java.lang.Integer").valueOf(x)
    Base.convert(::Type{InstanceProxy{typeTagForName("java.lang.Long")}}, x::JavaCall.jlong) = javaImport("java.lang.Long").valueOf(x)
    Base.convert(::Type{InstanceProxy{typeTagForName("java.lang.Float")}}, x::JavaCall.jfloat) = javaImport("java.lang.Float").valueOf(x)
    Base.convert(::Type{InstanceProxy{typeTagForName("java.lang.Double")}}, x::JavaCall.jdouble) = javaImport("java.lang.Double").valueOf(x)

    Base.convert(::Type{AbstractString}, x::InstanceProxy{typeTagForName("java.lang.String")}) = Base.convert(AbstractString, getfield(x, :ref))
    Base.convert(::Type{JavaCall.jboolean}, x::InstanceProxy{typeTagForName("java.lang.Boolean")}) = x.booleanValue()
    Base.convert(::Type{Bool}, x::InstanceProxy{typeTagForName("java.lang.Boolean")}) = Bool(x.booleanValue())
    Base.convert(::Type{JavaCall.jchar}, x::InstanceProxy{typeTagForName("java.lang.Character")}) = x.charValue()
    Base.convert(::Type{Char}, x::InstanceProxy{typeTagForName("java.lang.Character")}) = Char(x.charValue())
    Base.convert(::Type{JavaCall.jbyte}, x::InstanceProxy{typeTagForName("java.lang.Byte")}) = x.byteValue()
    Base.convert(::Type{JavaCall.jshort}, x::InstanceProxy{typeTagForName("java.lang.Short")}) = x.shortValue()
    Base.convert(::Type{JavaCall.jint}, x::InstanceProxy{typeTagForName("java.lang.Integer")}) = x.intValue()
    Base.convert(::Type{JavaCall.jlong}, x::InstanceProxy{typeTagForName("java.lang.Long")}) = x.longValue()
    Base.convert(::Type{JavaCall.jfloat}, x::InstanceProxy{typeTagForName("java.lang.Float")}) = x.floatValue()
    Base.convert(::Type{JavaCall.jdouble}, x::InstanceProxy{typeTagForName("java.lang.Double")}) = x.doubleValue()


    macro aaa(name)
        toupper(x) = uppercase(x[1]) * x[i+1:end]
        java_name = "java.lang.$(toupper(name))"
        jc_type = Symbol("JavaCall.j" * string(name))
        quote
            Base.convert(::Type{InstanceProxy{typeTagForName($java_name)}}, x::$jc_type) = javaImport($java_name).valueOf(x)
            Base.convert(::Type{$jc_type}, x::InstanceProxy{typeTagForName($java_name)}) = x.$(Symbol(name * "Value"))()
        end
    end
end

##
using Main.BetterJavaCall
BetterJavaCall.init(["-Xmx128M"])
##

LocalDate = @jimport java.time.LocalDate

now = LocalDate.now()
tom = now.plusDays(1)
println("hi")
##