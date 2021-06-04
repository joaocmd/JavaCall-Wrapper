include("BetterJavaCall/BetterJavaCall.jl")
using .BetterJavaCall
##
BetterJavaCall.init(["-Xmx128M"])

## Basic usage
Math = @jimport java.lang.Math
LocalDate = @jimport java.time.LocalDate     # importing a class
now = LocalDate.now()                        # calling a static method
println(now)                                 # printing java objects
tom = now.plusDays(1)
println(tom)
println(now.plusDays(1).equals(tom))         # chained calls are possible
println(tom.isAfter(now))                    # conversion to interface ChronoLocalDate

JString = @jimport java.lang.String
println(now.equals(LocalDate.parse(now.toString())))
println(now.equals(LocalDate.parse(JString(now.toString()))))

## Accessing fields
println(Math.PI == pi) # they are not strictly equal ;)
println(Math.abs(Math.PI - pi) < 1e-100)
println(Math.abs(Math.PI - pi) < 1e-1000)

# if the fields are not final, a setter is also available:
# Math.PI = 1, (no example found)
# instance fields are accessed in the same manner

## Creating new objects
URL = @jimport java.net.URL
url = @jnew URL("https://www.example.com")   # similar to URL.new(...)
println(propertynames(url))                  # list properties, works for REPL autocomplete
println(url.getHost())

url = @jnew URL("https", "www.example.com", 8443, "example")
println(url.getPort())

## Access to metadata about the proxies
str = JString("ola")
println(typeof(str.δref))   # Access to metadata given with δ
JString.δmod                # Module with evaluated methods/fields/constructors
JString.δmethods            # Static methods
JString.δfields             # Static fields
JString.class               # Similar to java's String.class
JString.new                 # Constructor, also accessible through @jnew

str.δref                    # JavaCall.JObject for this object
str.δmethods                # Instance methods
str.δfields                 # Instace fields

strmod = str.δmod
strmod.static_methods
strmod.static_fields
strmod.instance_methods
strmod.instance_fields
methods(strmod.instance_methods.indexOf)


## Docs examples - Home
Math.sin(pi / 2)

Arrays = @jimport java.util.Arrays
Arrays.binarySearch([10, 20, 30, 40, 50, 60], 40)

## Docs examples - Reflection API
HashMap = @jimport java.util.HashMap
jmap = @jnew HashMap()

jmap.put("foo", "text value")
println(jmap)
println(typeof(jmap.get("foo")))
println(typeof(jmap.get("bar")))

## Docs examples - Iterators
ArrayList = @jimport java.util.ArrayList

words = @jnew ArrayList()
words.add("hello")
words.add("world")

for word in words.iterator() # .iterator() is an ArrayList method
    println(word)
end

## varargs

list = Arrays.asList(1, 2, 3, 4, 5)
println(list)
println(JObject(list).getClass().getName())

## Exceptions
try
    println("will now trigger an exception and print its type and stacktrace")
    URL.new("malformed url")
catch ex
    println(typeof(ex))
    # Note: not an InstanceProxy, but extended to allow easy access to all the usual proxied fields/methods

    ex.printStackTrace()

    proxy = convert(InstanceProxy, ex)
    println(typeof(proxy))
end

URL.new("malformed url") # Error includes java stack trace information