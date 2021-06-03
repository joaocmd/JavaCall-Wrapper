#import Pkg
#Pkg.add("JavaCall")

##
module BetterJavaCall
    export ImportProxy, InstanceProxy, @jimport

    include("javacall_patch.jl")
    include("type_tags.jl")
    include("proxies.jl")
    include("dyncall.jl")
    include("wrapping.jl")
    include("loader.jl")
    include("convert.jl")

    import JavaCall
    using JavaCall: JavaObject # why is this needed?

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
end

##
using Main.BetterJavaCall
BetterJavaCall.init(["-Xmx128M"])
##

LocalDate = @jimport java.time.LocalDate

now = LocalDate.now()
tom = now.plusDays(1)
println("now = ", now)
println("tom = ", tom)
println("tom.isAfter(now)? ", tom.isAfter(now))
##