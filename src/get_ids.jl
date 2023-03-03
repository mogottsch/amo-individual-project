import Pkg;
Pkg.activate(".");
Pkg.instantiate();

include("./ieee_parser.jl")

if length(ARGS) != 1
    println("Usage: julia get_ids.jl <ieee_file>")
end

busses, lines = read_IEEE_common_data_format(ARGS[1])

ids = Set()

for (id, bus) in busses
    push!(ids, id)
end

for (id, line) in lines
    push!(ids, id)
end

println("BEGIN IDS")
for id in ids
    println(id)
end
println("END IDS")
