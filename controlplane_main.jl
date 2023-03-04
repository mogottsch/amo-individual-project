import Pkg;
Pkg.activate(".");
Pkg.instantiate();

include("./src/distributed/controlplane.jl")

function main(args)
    if length(args) != 1
        println("Usage: julia client.jl <id>")
        return
    end

    @info "Running with $(Threads.nthreads()) threads"


    r = startControlPlane(args[1])
    elapsed, objective = r
end


main(ARGS)

