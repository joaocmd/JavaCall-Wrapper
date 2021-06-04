javaImport(x) = javaImport(string(x))
javaImport(t::Type{<: JavaTypeTag}) = javaImport(_classnameFromTypeTagSymbol(t))
javaImport(classname::String) = begin
    if ! Base.isdefined(Main.BetterJavaCall, Symbol(javaClassModuleName(classname)))
        loadJavaClass(classname)
    end

    mod = eval(Symbol(javaClassModuleName(classname)))
    ImportProxy{typeTagForName(classname)}(mod)
end

javaClassModuleName(classname::String) = "PAvaJavaInterop Class " * classname

loadJavaClass(classname::String) = begin
    local jc_class = eval(JavaCall._jimport(classname))
    local mod_name = javaClassModuleName(classname)

    eval(:(
        module $(Symbol(mod_name))
            import JavaCall
            using Main.BetterJavaCall: wrapped, unwrapped

            jc_class = $jc_class
            class = $(JavaCall.classforname(classname))
            name = $classname
        end
    ))
    local mod = eval(Symbol(mod_name))

    loadJavaClassMethods(mod)
    loadJavaClassFields(mod)
    loadJavaClassConstructors(mod)
end

loadJavaClassMethods(mod::Module) = begin
    local instance_method_names = Set{String}()
    local static_method_names = Set{String}()

    for method in JavaCall.listmethods(mod.jc_class)
        local name = JavaCall.getname(method)
        local returntype = normalizeJavaType(JavaCall.getreturntype(method))
        local parametertypes = Tuple(map(normalizeJavaType, JavaCall.getparametertypes(method)))
        local parameternames = [Symbol("p" * string(i)) for i in 1:length(parametertypes)]
        local typed_parameters = gentypedparameters(method, parameternames, parametertypes)

        local (sym_prefix, receiver) = if isstatic(method)
            push!(static_method_names, name)
            ("sm_", mod.jc_class)
        else
            push!(instance_method_names, name)
            typed_parameters = [:( inst::$(mod.jc_class) ), typed_parameters...]
            ("im_", :inst)
        end

        local varargsconv = genvaconv(method, typed_parameters)
        local def = quote
            $(Symbol(sym_prefix * name))($(typed_parameters...)) = begin
                $(( :($pn = unwrapped($pn)) for pn in parameternames )...);

                $(varargsconv)
                local res = JavaCall.jcall($receiver, $name, $returntype, $parametertypes, $(parameternames...))
                wrapped(res)
            end
        end
        Base.eval(mod, def)
    end

    for methodname in instance_method_names
        Base.eval(mod, quote
            $(Symbol("im_" * methodname))(inst::$(mod.jc_class), args...) =
                $dyncallmethod(inst, $methodname, args...)
        end)
    end
    for methodname in static_method_names
        Base.eval(mod, quote
            $(Symbol("sm_" * methodname))(args...) =
                $dyncallmethod($(mod.jc_class), $methodname, args...)
        end)
    end

    local instance_methods = (:($(Symbol(n)) = $(Symbol("im_" * n))) for n in instance_method_names)
    local static_methods = (:($(Symbol(n)) = $(Symbol("sm_" * n))) for n in static_method_names)
    Base.eval(mod, quote
        instance_methods = ($(instance_methods...),)
        static_methods = ($(static_methods...),)
    end)
end

loadJavaClassFields(mod::Module) = begin
    local instance_field_names = Set{String}()
    local static_field_names = Set{String}()

    for field in JavaCall.listfields(mod.jc_class)
        local name = JavaCall.getname(field)
        local type = normalizeJavaType(JavaCall.jcall(field, "getType", JavaCall.JClass, ()))

        if isstatic(field)
            # TODO: use better setter than the boxed get/set
            local getter = quote
                function $(Symbol("sf_" * name))()
                    local res = JavaCall.jfield($(mod.jc_class), $name, $type)
                    wrapped(res)
                end
            end
            Base.eval(mod, getter)

            if !isfinal(field)
                local setter = quote
                    function $(Symbol("sf_" * name))(val::$(wrapped_paramtype(type)))
                        JavaCall.jcall($field, "set", Nothing, ($type,), unwrapped(val));
                    end
                end
                Base.eval(mod, setter)
            end

            push!(static_field_names, name)
        else
            # TODO: use better setter than the boxed get/set
            local getter = quote
                function $(Symbol("if_" * name))(inst::$(mod.jc_class))
                    local res = JavaCall.jfield($(mod.jc_class), $name, $type)
                    wrapped(res)
                end
            end
            Base.eval(mod, getter)

            if !isfinal(field)
                local setter = quote
                    function $(Symbol("if_" * name))(inst::$(mod.jc_class), val::$(wrapped(type)))
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

loadJavaClassConstructors(mod::Module) = begin
    local constructors = JavaCall.jcall(mod.class, "getConstructors", Vector{JavaCall.JConstructor}, ())

    for ctor in constructors
        local parametertypes = Tuple(map(normalizeJavaType, JavaCall.getparametertypes(ctor)))
        local parameternames = [:($(Symbol("p" * string(i)))) for i in 1:length(parametertypes)]
        local typed_parameters = gentypedparameters(ctor, parameternames, parametertypes)

        local ctordef = quote
            function new($(typed_parameters...))
                $(( :($pn = unwrapped($pn)) for pn in parameternames )...);

                $(genvaconv(ctor, typed_parameters))
                local res = JavaCall.jnew(Symbol($(mod.name)), $parametertypes, $(parameternames...))
                wrapped(res)
            end
        end
        Base.eval(mod, ctordef)
    end

    if !isempty(constructors)
        Base.eval(mod, quote
            new(args...) = $dyncallctor($(mod.name), args...)
        end)
    end
end

gentypedparameters(method::Union{JavaCall.JMethod, JavaCall.JConstructor}, paramnames, paramtypes) = begin
    local typedparams = [:($(a[1])::$(wrapped_paramtype(a[2]))) for a in zip(paramnames, paramtypes)]
    if isvarargs(method)
        local name = paramnames[end]
        local type = wrapped(componenttype(paramtypes[end]))

        typedparams[end] = :($name::$type...)
    end
    typedparams
end

genvaconv(method::Union{JavaCall.JMethod, JavaCall.JConstructor}, typed_params) = begin
    if !isvarargs(method)
        return :()
    end

    local vaname = typed_params[end].args[1].args[1]
    # cannot just use typed parameters because it is already wrapped (can be a Union or something)
    local vatype = componenttype(normalizeJavaType(last(JavaCall.getparametertypes(method))))

    :( $vaname = $vaconvert($vatype, $vaname) )
end

normalizeJavaType(name) =
    if name == "short"
        JavaCall.jshort
    elseif name == "int"
        JavaCall.jint
    elseif name == "long"
        JavaCall.jlong
    elseif name == "byte"
        JavaCall.jbyte
    elseif name == "char"
        JavaCall.jchar # UInt16
    elseif name == "float"
        JavaCall.jfloat
    elseif name == "double"
        JavaCall.jdouble
    elseif name == "boolean"
        JavaCall.jboolean # UInt8
    elseif name == "void"
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

isstatic(method::Union{JavaCall.JField,JavaCall.JMethod}) = begin
    local mdf = JavaCall.@jimport java.lang.reflect.Modifier
    local modifiers = JavaCall.jcall(method, "getModifiers", JavaCall.jint, ())
    Bool(JavaCall.jcall(mdf, "isStatic", JavaCall.jboolean, (JavaCall.jint,), modifiers))
end
isfinal(method::Union{JavaCall.JField,JavaCall.JMethod}) = begin
    local mdf = JavaCall.@jimport java.lang.reflect.Modifier
    local modifiers = JavaCall.jcall(method, "getModifiers", JavaCall.jint, ())
    Bool(JavaCall.jcall(mdf, "isFinal", JavaCall.jboolean, (JavaCall.jint,), modifiers))
end

isvarargs(method::Union{JavaCall.JMethod, JavaCall.JConstructor}) =
    Bool(JavaCall.jcall(method, "isVarArgs", JavaCall.jboolean, ()))
componenttype(::Type{Vector{T}}) where {T} = T

vaconvert(type, args) = begin
    show(type)
    if !(type <: Union{java_primitive_types, Bool, Char, UInt8, UInt16})
        args = map(boxed, args)
    end
    map(a -> Base.convert(type, a), args)
end