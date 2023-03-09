import Pkg;
Pkg.activate(".");
Pkg.instantiate();

include("./src/distributed/controlplane.jl")

function main(args)
    if length(args) != 1
        println("Usage: julia controlplane_main.jl <path>")
        return
    end

    @info "Running with $(Threads.nthreads()) threads"


    r = startControlPlane(args[1])
end


main(ARGS)

