# Modifies JavaCall exception handling to expose the java exception object
import JavaCall.JNI
import JavaCall

struct JavaException
    msg::String
    ref::JavaCall.JavaObject{Symbol("java.lang.Throwable")}
end

const StackTraceElement = JavaCall.JavaObject{Symbol("java.lang.StackTraceElement")}
Base.showerror(io::IO, ex::JavaException) = begin
    println(io, ex.msg)

    local st = JavaCall.jcall(ex.ref, "getStackTrace", Vector{StackTraceElement}, ())
    for frame in st
        local repr = JavaCall.jcall(frame, "toString", JavaCall.JString, ())
        println(io, "\t at " * repr)
    end
end

# patch
JavaCall.eval(quote
    function geterror(allow=false)
        isexception = JNI.ExceptionCheck()

        if isexception == JNI_TRUE
            jthrow = JNI.ExceptionOccurred()
            jthrow==C_NULL && throw(JavaCallError("Java Exception thrown, but no details could be retrieved from the JVM"))
            # REMOVED: JNI.ExceptionDescribe() #Print java stackstrace to stdout
            JNI.ExceptionClear()
            jclass = JNI.FindClass("java/lang/Throwable")
            jclass==C_NULL && throw(JavaCallError("Java Exception thrown, but no details could be retrieved from the JVM"))
            jmethodId=JNI.GetMethodID(jclass, "toString", "()Ljava/lang/String;")
            jmethodId==C_NULL && throw(JavaCallError("Java Exception thrown, but no details could be retrieved from the JVM"))
            res = JNI.CallObjectMethodA(jthrow, jmethodId, Int[])
            res==C_NULL && throw(JavaCallError("Java Exception thrown, but no details could be retrieved from the JVM"))
            msg = unsafe_string(JString(res))
            # REMOVED: JNI.DeleteLocalRef(jthrow)
            # ADDED:
            throw($JavaException(msg, JavaObject{Symbol("java.lang.Throwable")}(jthrow)))
        else
            if allow==false
                return #No exception pending, legitimate NULL returned from Java
            else
                throw(JavaCallError("Null from Java. Not known how"))
            end
        end
    end
end)

# not exceptions but it was amiss
JavaCall.eval(quote
    function conventional_name(name::AbstractString)
        if startswith(name, "[")
            return conventional_name(name[2:end]) * "[]"
        elseif name == "Z"
            return "boolean"
        elseif name == "B"
            return "byte"
        elseif name == "C"
            return "char"
        elseif name == "I"
            return "int"
        elseif name == "J"
            return "long"
        elseif name == "F"
            return "float"
        elseif name == "D"
            return "double"
        elseif name == "V"
            return "void"
        elseif name == "S" # was missing in JavaCall :/
            return "short"
        elseif startswith(name, "L")
            return name[2:end-1]
        else
            return name
        end
    end
end)