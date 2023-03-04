import Pkg;
Pkg.activate(".");
Pkg.instantiate();


include("./src/distributed/server.jl")

function main(args)
    if length(args) != 1
        println("Usage: julia server.jl <path>")
        return
    end

    startFor(args[1])
end

main(ARGS)
