include("BetterJavaCall/round4.jl")
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
println(tom.isAfter(now))

JString = @jimport java.lang.String
println(now.equals(LocalDate.parse(now.toString())))
println(now.equals(LocalDate.parse(JString(now.toString()))))

## Accessing fields
println(Math.PI == pi) # they are not strictly equal ;)
println(Math.abs(Math.PI - pi) < 1e-100)
println(Math.abs(Math.PI - pi) < 1e-1000)

# if the fields are not final, a setter is also available through
# Math.PI = 1, (no example found)
# instance fields are accessed in the same manner

## Creating new objects
URL = @jimport java.net.URL
url = @jnew URL("https://www.example.com")   # similar to URL.new(...)
println(propertynames(url))                  # list properties, works for REPL autocomplete
println(url.getHost())

url = @jnew URL("https", "www.example.com", 8443, "example")
println(url.getDefaultPort())

## Access to metadata about the proxies
println(typeof(url.δref))   # Access to metadata given with δ
URL.δmod                    # Module with evaluated methods/fields/constructors
URL.δmethods                # Static methods
URL.δfields                 # Static fields
URL.class                   # Similar to java's URL.class
URL.new                     # Constructor, also accessible through @jnew

url.δmod                    # Same as above
url.δref                    # Wrapped JavaCall.JObject for this object
url.δmethods                # Instance methods
## error because pairs returns a Dictionary which is not iterable, use zip(keys(methods), methods)
url.δfields                 # Instace fields
proxy.δmod.static_methods

## Varargs, overloads, etc

## Iterators

## Docs examples - Home
Math.sin(pi / 2)

Arrays = @jimport java.util.Arrays
Arrays.binarySearch([10, 20, 30, 40, 50, 60], 40)

## Docs examples - Reflection API
HashMap = @jimport java.util.HashMap
jmap = @jnew HashMap()

jmap.put(JObject("foo"), JObject("text value"))
